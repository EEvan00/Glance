const APPLE_ORIGIN = 'https://weatherkit.apple.com';
const CACHE_MS = 15 * 60_000;
const MAX_CACHE_ENTRIES = 64;
const MAX_INFLIGHT = 8;
const MAX_IP_RECORDS = 2048;
const MAX_BODY_BYTES = 262_144;
const encoder = new TextEncoder();

export class ServiceError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
const unavailable = () => new ServiceError(503, 'service_unavailable');
function errorResponse(error) {
  const safe = error instanceof ServiceError ? error : unavailable();
  const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' };
  if (safe.status === 429) headers['Retry-After'] = safe.code === 'quota_exceeded' ? '3600' : '60';
  if (safe.status === 405) headers.Allow = 'GET';
  if (safe.stage) headers['X-Weather-Failure-Stage'] = safe.stage;
  if (safe.causeKind) headers['X-Weather-Failure-Kind'] = safe.causeKind;
  if (Number.isInteger(safe.upstreamStatus)) headers['X-Weather-Upstream-Status'] = String(safe.upstreamStatus);
  return new Response(JSON.stringify({ error: safe.code }), { status: safe.status, headers });
}
function responseJSON(value) {
  return Response.json(value, { headers: { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' } });
}
function coordinate(raw, max) {
  if (typeof raw !== 'string' || raw.length > 16 || !/^-?(?:\d+(?:\.\d+)?|\.\d+)$/.test(raw)) {
    throw new ServiceError(400, 'invalid_request');
  }
  const value = Number(raw);
  if (!Number.isFinite(value) || Math.abs(value) > max) throw new ServiceError(400, 'invalid_request');
  return Number(value.toFixed(2));
}
function normalizeQuery(input) {
  if (input.language !== 'en' || typeof input.timezone !== 'string' || input.timezone.length > 80 ||
      !/^[A-Za-z0-9_+-]+(?:\/[A-Za-z0-9_+-]+)*$/.test(input.timezone)) {
    throw new ServiceError(400, 'invalid_request');
  }
  let timezone;
  try { timezone = new Intl.DateTimeFormat('en', { timeZone: input.timezone }).resolvedOptions().timeZone; }
  catch { throw new ServiceError(400, 'invalid_request'); }
  return { latitude: coordinate(String(input.latitude), 90), longitude: coordinate(String(input.longitude), 180), language: 'en', timezone };
}
function parseRequest(request) {
  const url = new URL(request.url);
  if (url.pathname !== '/v1/weather') throw new ServiceError(404, 'not_found');
  if (request.method !== 'GET') throw new ServiceError(405, 'method_not_allowed');
  if (url.protocol !== 'https:' || request.url.length > 512) throw new ServiceError(400, 'invalid_request');
  const names = ['latitude','longitude','language','timezone'];
  if ([...url.searchParams].length !== 4 || names.some(name => url.searchParams.getAll(name).length !== 1)) {
    throw new ServiceError(400, 'invalid_request');
  }
  return normalizeQuery(Object.fromEntries(url.searchParams));
}
async function hashIP(request) {
  const ip = request.headers.get('CF-Connecting-IP');
  if (!ip || ip.length > 64 || !/^[a-fA-F0-9:.]+$/.test(ip)) throw unavailable();
  // Only Cloudflare's edge-supplied header is trusted. No raw IP is sent to DO/storage.
  const daily = new Date().toISOString().slice(0,10);
  const bytes = await crypto.subtle.digest('SHA-256', encoder.encode(`${daily}:${ip}`));
  return [...new Uint8Array(bytes)].map(value => value.toString(16).padStart(2,'0')).join('');
}
function positiveLimit(raw, fallback) {
  if (raw === undefined) return fallback;
  if (!/^\d+$/.test(String(raw)) || !Number.isSafeInteger(Number(raw)) || Number(raw) < 1 || Number(raw) > fallback) throw unavailable();
  return Number(raw);
}
function base64url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
}
function encodedJSON(value) { return base64url(encoder.encode(JSON.stringify(value))); }

export class TokenSigner {
  constructor(env, now = () => Date.now()) { this.env = env; this.now = now; this.cached = null; this.pending = null; this.key = null; }
  async token() {
    const now = Math.floor(this.now()/1000);
    if (this.cached && now >= this.cached.iat && now < this.cached.exp - 60) return this.cached.token;
    if (!this.pending) this.pending = this.create(now).finally(() => { this.pending = null; });
    return this.pending;
  }
  async create(now) {
    const team = this.env.APPLE_WEATHER_TEAM_ID, kid = this.env.APPLE_WEATHER_KEY_ID, service = this.env.APPLE_WEATHER_SERVICE_ID;
    const pem = this.env.APPLE_WEATHER_PRIVATE_KEY;
    if (!/^[A-Z0-9]{10}$/.test(team ?? '') || !/^[A-Z0-9]{10}$/.test(kid ?? '') ||
        !/^[A-Za-z0-9][A-Za-z0-9.-]{0,199}$/.test(service ?? '') || typeof pem !== 'string' || pem.length > 4096) throw unavailable();
    try {
      if (!this.key) {
        const match = /^\s*-----BEGIN PRIVATE KEY-----([\s\S]+?)-----END PRIVATE KEY-----\s*$/.exec(pem);
        if (!match) throw unavailable();
        const binary = atob(match[1].replace(/\s/g,''));
        this.key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(binary, character => character.charCodeAt(0)),
          {name:'ECDSA', namedCurve:'P-256'}, false, ['sign']);
      }
      const iat = now - 10, exp = now + 300;
      const input = encodedJSON({alg:'ES256',kid,id:`${team}.${service}`}) + '.' + encodedJSON({iss:team,iat,exp,sub:service});
      const signature = new Uint8Array(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},this.key,encoder.encode(input)));
      const token = input + '.' + base64url(signature);
      this.cached = { token, iat, exp };
      return token;
    } catch { throw unavailable(); }
  }
}

/// Core has injected transport/clock to keep offline verification independent of Cloudflare.
export class WeatherService {
  constructor(storage, env, { fetch: transport = globalThis.fetch.bind(globalThis), now = () => Date.now(), timeoutMS = 8000 } = {}) {
    this.storage = storage; this.env = env; this.fetch = transport; this.now = now; this.timeoutMS = timeoutMS;
    this.signer = new TokenSigner(env, now);
    this.cache = new Map(); this.inflight = new Map(); this.attributionCache = null; this.attributionPending = null;
  }
  async weather(rawQuery, ipHash) {
    try {
      const query = normalizeQuery(rawQuery);
      if (!/^[a-f0-9]{64}$/.test(ipHash ?? '')) throw unavailable();
      await this.rateLimit(ipHash);
      const key = JSON.stringify(query), now = this.now();
      const cached = this.cache.get(key);
      if (cached && now >= cached.at && now - cached.at < CACHE_MS) return cached.value;
      this.cache.delete(key);
      if (this.inflight.has(key)) return await this.inflight.get(key);
      if (this.inflight.size >= MAX_INFLIGHT) throw new ServiceError(503, 'service_busy');
      const pending = this.load(query).then(value => {
        for (const [existing, entry] of this.cache) if (this.now() < entry.at || this.now() - entry.at >= CACHE_MS) this.cache.delete(existing);
        if (this.cache.size >= MAX_CACHE_ENTRIES) this.cache.delete(this.cache.keys().next().value);
        this.cache.set(key,{at:this.now(),value});
        return value;
      }).finally(() => { this.inflight.delete(key); });
      this.inflight.set(key,pending);
      return await pending;
    } catch (error) { throw error instanceof ServiceError ? error : unavailable(); }
  }
  async rateLimit(ipHash) {
    const now = this.now(), day = new Date(now).toISOString().slice(0,10), minute = Math.floor(now/60_000);
    const minuteLimit = positiveLimit(this.env.IP_REQUESTS_PER_MINUTE,20), dailyLimit = positiveLimit(this.env.IP_REQUESTS_PER_DAY,300);
    await this.storage.transaction(async tx => {
      let index = await tx.get('ip-index');
      if (!index || index.day !== day) {
        const old = await tx.list({prefix:'ip:',limit:MAX_IP_RECORDS+1});
        const keys = [...old.keys()];
        for (let start=0; start<keys.length; start+=128) await tx.delete(keys.slice(start,start+128));
        index = {day,unique:0};
      }
      const key = `ip:${ipHash}`;
      const previous = await tx.get(key);
      if (!previous && index.unique >= MAX_IP_RECORDS) throw new ServiceError(429,'rate_limited');
      const daily = previous?.day === day ? previous.daily : 0;
      const perMinute = previous?.minute === minute ? previous.perMinute : 0;
      if (daily >= dailyLimit || perMinute >= minuteLimit) throw new ServiceError(429,'rate_limited');
      if (!previous) { index.unique += 1; await tx.put('ip-index',index); }
      await tx.put(key,{day,minute,daily:daily+1,perMinute:perMinute+1});
    });
  }
  async reserveUpstream() {
    const date = new Date(this.now()).toISOString(), month = date.slice(0,7), day = date.slice(0,10);
    const monthlyLimit = positiveLimit(this.env.MONTHLY_UPSTREAM_LIMIT,400_000), dailyLimit = positiveLimit(this.env.DAILY_UPSTREAM_LIMIT,15_000);
    await this.storage.transaction(async tx => {
      const previous = await tx.get('upstream');
      if (previous && (!Number.isSafeInteger(previous.monthly) || previous.monthly < 0 ||
          !Number.isSafeInteger(previous.daily) || previous.daily < 0 ||
          !/^\d{4}-\d{2}$/.test(previous.month ?? '') || !/^\d{4}-\d{2}-\d{2}$/.test(previous.day ?? '') ||
          previous.month > month || previous.day > day)) throw unavailable();
      const monthly = previous?.month === month ? previous.monthly : 0;
      const daily = previous?.day === day ? previous.daily : 0;
      if (monthly >= monthlyLimit || daily >= dailyLimit) throw new ServiceError(429,'quota_exceeded');
      // Persist before any network I/O; failed/timeout attempts stay charged.
      await tx.put('upstream',{month,day,monthly:monthly+1,daily:daily+1});
    });
  }
  async upstreamJSON(url) {
    const token = await this.signer.token();
    await this.reserveUpstream();
    const abort = new AbortController();
    let timer;
    const timeout = new Promise((_resolve,reject) => { timer = setTimeout(() => {
      reject(new ServiceError(504,'upstream_timeout'));
      abort.abort();
    },this.timeoutMS); });
    try {
      return await Promise.race([timeout,(async () => {
        const response = await this.fetch(url,{headers:{Authorization:`Bearer ${token}`,Accept:'application/json'},signal:abort.signal,redirect:'manual'});
        if (!response.ok || !response.headers.get('Content-Type')?.toLowerCase().includes('application/json') || !response.body) {
          await response.body?.cancel();
          const failure = new ServiceError(502,'upstream_unavailable');
          failure.stage = new URL(url).pathname.startsWith('/attribution/') ? 'attribution-response' : 'weather-response';
          failure.upstreamStatus = response.status;
          throw failure;
        }
        const reader = response.body.getReader(), chunks = []; let size = 0;
        for (;;) {
          const {value,done} = await reader.read();
          if (done) break;
          size += value.byteLength;
          if (size > MAX_BODY_BYTES) { await reader.cancel(); throw new ServiceError(502,'upstream_unavailable'); }
          chunks.push(value);
        }
        const bytes = new Uint8Array(size); let offset = 0;
        for (const chunk of chunks) { bytes.set(chunk,offset); offset += chunk.byteLength; }
        return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
      })()]);
    } catch (error) {
      const failure = error instanceof ServiceError ? error : new ServiceError(502,'upstream_unavailable');
      failure.stage ??= new URL(url).pathname.startsWith('/attribution/') ? 'attribution-transport' : 'weather-transport';
      if (!(error instanceof ServiceError)) { const message = String(error?.message ?? ''); failure.causeKind = /redirect/i.test(message) ? 'redirect' : /illegal invocation/i.test(message) ? 'receiver' : /tls|ssl|certificate/i.test(message) ? 'tls' : /dns|resolve/i.test(message) ? 'dns' : /url/i.test(message) ? 'url' : /context|request/i.test(message) ? 'context' : 'other'; }
      throw failure;
    } finally { clearTimeout(timer); }
  }
  async load(query) {
    const url = new URL(`${APPLE_ORIGIN}/api/v1/weather/en/${query.latitude}/${query.longitude}`);
    url.searchParams.set('dataSets','currentWeather,forecastHourly,forecastDaily');
    url.searchParams.set('timezone',query.timezone);
    // Apple's default start can include the beginning of the local day. Near
    // midnight that makes a nominal 24-hour end exceed our bounded response.
    const forecastStart = this.now();
    url.searchParams.set('hourlyStart',new Date(forecastStart).toISOString());
    url.searchParams.set('hourlyEnd',new Date(forecastStart+86_400_000).toISOString());
    url.searchParams.set('dailyEnd',new Date(this.now()+172_800_000).toISOString());
    const response = await this.upstreamJSON(url);
    const current = response?.currentWeather, hourly = response?.forecastHourly, daily = response?.forecastDaily;
    const invalidStage = !Number.isFinite(current?.temperature) ? 'weather-temperature'
      : !Array.isArray(hourly?.hours) ? 'weather-hourly-shape'
      : hourly.hours.length > 48 ? 'weather-hourly-count'
      : !Array.isArray(daily?.days) ? 'weather-daily-shape'
      : daily.days.length > 3 ? 'weather-daily-count' : null;
    if (invalidStage) { const failure = new ServiceError(502,'upstream_unavailable'); failure.stage = invalidStage; throw failure; }
    let legalPageURL;
    try { legalPageURL = officialURL(current.metadata?.attributionURL); } catch(error) { error.stage = 'legal-link'; throw error; }
    const logos = await this.attribution();
    return { weather:{currentWeather:current,forecastHourly:hourly,forecastDaily:daily}, attribution:{...logos,legalPageURL} };
  }
  async attribution() {
    const now = this.now();
    if (this.attributionCache && now >= this.attributionCache.at && now - this.attributionCache.at < CACHE_MS) return this.attributionCache.value;
    if (!this.attributionPending) this.attributionPending = this.upstreamJSON(`${APPLE_ORIGIN}/attribution/en`).then(value => {
      let logos;
      try { logos = {combinedMarkLightURL:officialURL(value?.['logoLight@2x'],true),combinedMarkDarkURL:officialURL(value?.['logoDark@2x'],true)}; } catch(error) { error.stage = 'logo-links'; throw error; }
      this.attributionCache = {at:this.now(),value:logos};
      return logos;
    }).finally(() => { this.attributionPending = null; });
    return this.attributionPending;
  }
}
function officialURL(raw, partial = false) {
  if (typeof raw !== 'string' || raw.length > 1024 || (partial && (!raw.startsWith('/') || raw.startsWith('//')))) throw new ServiceError(502,'upstream_unavailable');
  let url;
  try { url = partial ? new URL(raw,APPLE_ORIGIN) : new URL(raw); } catch { throw new ServiceError(502,'upstream_unavailable'); }
  const legalOrigin = !partial && url.origin === 'https://developer.apple.com' && url.pathname === '/weatherkit/data-source-attribution/' && !url.search;
  if ((url.origin !== APPLE_ORIGIN && !legalOrigin) || url.username || url.password || url.hash) throw new ServiceError(502,'upstream_unavailable');
  return url.href;
}

// Legacy constructor/fetch shape is supported without cloudflare:workers imports;
// this lets the exact core execute under Node's built-in test runner as well.
export class WeatherGate {
  constructor(ctx,env) { this.service = new WeatherService(ctx.storage,env); }
  async fetch(request) {
    try {
      if (request.method !== 'POST' || Number(request.headers.get('Content-Length') ?? 0) > 1024) throw new ServiceError(400,'invalid_request');
      const input = await request.json();
      return responseJSON(await this.service.weather(input,input.ipHash));
    } catch (error) { return errorResponse(error); }
  }
}
export default {
  async fetch(request,env) {
    try {
      const query = parseRequest(request);
      const ipHash = await hashIP(request);
      if (!env.WEATHER_GATE) throw unavailable();
      const gate = env.WEATHER_GATE.getByName('global-weather-v1');
      return await gate.fetch(new Request('https://internal.weather/v1/weather',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...query,ipHash})}));
    } catch (error) { return errorResponse(error); }
  }
};
