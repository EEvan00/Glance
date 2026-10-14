import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import worker, { WeatherService, TokenSigner, ServiceError } from '../src/worker.js';

const weather = JSON.parse(await readFile(new URL('./fixtures/apple-weather.json', import.meta.url)));
const attribution = JSON.parse(await readFile(new URL('./fixtures/apple-attribution.json', import.meta.url)));
let privateKeyPEM, publicKey;
before(async () => {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  publicKey = pair.publicKey;
  const bytes = Buffer.from(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  privateKeyPEM = `-----BEGIN PRIVATE KEY-----\n${bytes.toString('base64')}\n-----END PRIVATE KEY-----`;
});

// Models the storage boundary with atomic commits and persistent shared state.
// Reconstructing a service or storage object retains the committed database.
class FakeStorage {
  constructor(state = { data: new Map(), tail: Promise.resolve(), failWrites: false }) { this.state = state; }
  async transaction(body) {
    const run = this.state.tail.then(async () => {
      const copy = new Map(structuredClone([...this.state.data]));
      const tx = {
        get: async key => structuredClone(copy.get(key)),
        put: async (key, value) => { if (this.state.failWrites === true || this.state.failWrites === key) throw Error('database failed'); copy.set(key, structuredClone(value)); },
        list: async ({ prefix, limit }) => new Map([...copy].filter(([k]) => k.startsWith(prefix)).slice(0, limit)),
        delete: async keys => { for (const key of Array.isArray(keys) ? keys : [keys]) copy.delete(key); }
      };
      const result = await body(tx);
      this.state.data = copy;
      return result;
    });
    this.state.tail = run.catch(() => {});
    return run;
  }
}
function environment(extra = {}) {
  return { APPLE_WEATHER_PRIVATE_KEY: privateKeyPEM, APPLE_WEATHER_TEAM_ID: 'TEAM123456',
    APPLE_WEATHER_KEY_ID: 'KEY1234567', APPLE_WEATHER_SERVICE_ID: 'com.glance.weather', ...extra };
}
const query = { latitude: -33.87, longitude: 151.21, language: 'en', timezone: 'Australia/Sydney' };
const ip = 'a'.repeat(64);
function fixtureFetcher(calls = []) {
  return async (url, options) => {
    calls.push({ url: String(url), options });
    return Response.json(String(url).includes('/attribution/') ? attribution : weather);
  };
}
function makeService(options = {}) {
  const calls = [];
  const storage = options.storage ?? new FakeStorage();
  const service = new WeatherService(storage, environment(options.env), {
    now: options.now ?? (() => Date.parse('2026-10-13T04:00:00Z')),
    fetch: options.fetch ?? fixtureFetcher(calls), timeoutMS: options.timeoutMS ?? 100
  });
  return { service, calls, storage };
}
async function rejectsCode(promise, code) {
  await assert.rejects(promise, error => error instanceof ServiceError && error.code === code);
}

test('JWT has exact Apple claims, verified ES256 signature and short cached lifetime', async () => {
  let now = Date.parse('2026-10-13T04:00:00Z');
  const signer = new TokenSigner(environment(), () => now);
  const first = await signer.token();
  const [header, payload, sig] = first.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(header, 'base64url')), { alg: 'ES256', kid: 'KEY1234567', id: 'TEAM123456.com.glance.weather' });
  const claims = JSON.parse(Buffer.from(payload, 'base64url'));
  assert.deepEqual(Object.keys(claims).sort(), ['exp','iat','iss','sub']);
  assert.equal(claims.iss, 'TEAM123456');
  assert.equal(claims.sub, 'com.glance.weather');
  assert.equal(claims.exp - claims.iat, 310);
  assert.equal(Buffer.from(sig, 'base64url').length, 64);
  assert.equal(await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, publicKey, Buffer.from(sig, 'base64url'), new TextEncoder().encode(`${header}.${payload}`)), true);
  assert.equal(await signer.token(), first);
  now += 241_000;
  assert.notEqual(await signer.token(), first);
});

test('private key configuration fails closed without any upstream call', async () => {
  const { service, calls } = makeService({ env: { APPLE_WEATHER_PRIVATE_KEY: '' } });
  await rejectsCode(service.weather(query, ip), 'service_unavailable');
  assert.equal(calls.length, 0);
});

test('fixed Apple URLs, bounded forecast range and normalized dynamic attribution', async () => {
  const { service, calls } = makeService();
  const result = await service.weather(query, ip);
  assert.deepEqual(result.weather, weather);
  assert.deepEqual(result.attribution, {
    combinedMarkLightURL: 'https://weatherkit.apple.com' + attribution['logoLight@2x'],
    combinedMarkDarkURL: 'https://weatherkit.apple.com' + attribution['logoDark@2x'],
    legalPageURL: 'https://developer.apple.com/weatherkit/data-source-attribution/'
  });
  assert.equal(calls.length, 2);
  const url = new URL(calls[0].url);
  assert.equal(url.pathname, '/api/v1/weather/en/-33.87/151.21');
  assert.equal(url.searchParams.get('dataSets'), 'currentWeather,forecastHourly,forecastDaily');
  assert.equal(url.searchParams.get('timezone'), 'Australia/Sydney');
  assert.equal(url.searchParams.get('hourlyEnd'), '2026-10-14T04:00:00.000Z');
  assert.equal(url.searchParams.get('dailyEnd'), '2026-10-15T04:00:00.000Z');
  assert.equal(calls[1].url, 'https://weatherkit.apple.com/attribution/en');
  assert.equal(calls[0].options.redirect, 'manual');
  assert.match(calls[0].options.headers.Authorization, /^Bearer [\w.-]+$/);
  assert.ok(!JSON.stringify(result).includes('Bearer'));
  assert.ok(!JSON.stringify(result).includes(privateKeyPEM));
});

test('same rounded location requests coalesce, cache for 15 minutes, then refresh', async () => {
  let now = Date.parse('2026-10-13T04:00:00Z');
  const { service, calls } = makeService({ now: () => now });
  const results = await Promise.all(Array.from({ length: 10 }, () => service.weather(query, ip)));
  assert.deepEqual(results[0], results[9]);
  assert.equal(calls.length, 2);
  now += 899_000;
  await service.weather(query, ip);
  assert.equal(calls.length, 2);
  now += 1_000;
  await service.weather(query, ip);
  assert.equal(calls.length, 4);
});

test('monthly quota persists across service and storage reconstruction', async () => {
  const storage = new FakeStorage();
  const first = makeService({ storage, env: { MONTHLY_UPSTREAM_LIMIT: '2' } });
  await first.service.weather(query, ip);
  const second = makeService({ storage: new FakeStorage(storage.state), env: { MONTHLY_UPSTREAM_LIMIT: '2' } });
  await rejectsCode(second.service.weather({ ...query, longitude: 151.22 }, ip), 'quota_exceeded');
  assert.equal(second.calls.length, 0);
});

test('daily quota resets at UTC midnight without resetting monthly quota', async () => {
  let now = Date.parse('2026-10-13T23:59:00Z');
  const { service, calls } = makeService({ now: () => now, env: { DAILY_UPSTREAM_LIMIT: '2', MONTHLY_UPSTREAM_LIMIT: '4' } });
  await service.weather(query, ip);
  await rejectsCode(service.weather({ ...query, longitude: 151.22 }, ip), 'quota_exceeded');
  now = Date.parse('2026-10-14T00:00:00Z');
  await service.weather({ ...query, longitude: 151.23 }, ip);
  assert.equal(calls.length, 3); // cached attribution uses no new call
  now = Date.parse('2026-10-15T00:00:00Z');
  await rejectsCode(service.weather({ ...query, longitude: 151.24 }, ip), 'quota_exceeded');
  assert.equal(calls.length, 4); // weather reserved fourth call, attribution rejected
});

test('parallel unique requests cannot overspend transactional monthly quota', async () => {
  const { service, calls } = makeService({ env: { MONTHLY_UPSTREAM_LIMIT: '3' } });
  const results = await Promise.allSettled(Array.from({ length: 8 }, (_, i) => service.weather({ ...query, longitude: 151 + i / 100 }, (i.toString(16)).repeat(64))));
  assert.ok(results.some(result => result.status === 'rejected'));
  assert.ok(calls.length <= 3);
});

test('per-IP minute and daily limits persist across restart and reset by time', async () => {
  let now = Date.parse('2026-10-13T04:00:00Z');
  const env = { IP_REQUESTS_PER_MINUTE: '2', IP_REQUESTS_PER_DAY: '3' };
  const first = makeService({ now: () => now, env });
  await first.service.weather(query, ip);
  await first.service.weather(query, ip);
  const second = makeService({ storage: new FakeStorage(first.storage.state), now: () => now, env });
  await rejectsCode(second.service.weather(query, ip), 'rate_limited');
  now += 60_000;
  await second.service.weather(query, ip);
  now += 60_000;
  await rejectsCode(second.service.weather(query, ip), 'rate_limited');
  now += 86_400_000;
  await second.service.weather(query, ip);
});

test('persistent quota write failure prevents Apple calls', async () => {
  const storage = new FakeStorage();
  storage.state.failWrites = 'upstream';
  const { service, calls } = makeService({ storage });
  await rejectsCode(service.weather(query, ip), 'service_unavailable');
  assert.equal(calls.length, 0);
});

test('invalid or oversized upstream response is sanitized and never cached', async () => {
  for (const upstream of [() => new Response(null, {status:302,headers:{Location:'https://attacker.test/'}}), () => new Response('sensitive upstream detail', {status:401}),
    () => Response.json({ currentWeather: {} }),
    () => Response.json({...weather, currentWeather:{...weather.currentWeather, metadata:{attributionURL:'https://attacker.test/legal'}}}),
    () => new Response('x'.repeat(262145), { headers: { 'Content-Type':'application/json' } })]) {
    const { service } = makeService({fetch: async () => upstream()});
    await rejectsCode(service.weather(query, ip), 'upstream_unavailable');
    await rejectsCode(service.weather(query, ip), 'upstream_unavailable');
  }
});

test('timeout bounds upstream waits and permits a later retry', async () => {
  const { service } = makeService({timeoutMS: 5, fetch: async (_url, {signal}) => new Promise((_resolve, reject) => signal.addEventListener('abort', () => reject(Error('abort')), {once:true}))});
  await rejectsCode(service.weather(query, ip), 'upstream_timeout');
  await rejectsCode(service.weather(query, ip), 'upstream_timeout');
});

test('unknown paths, methods, malformed/duplicate/extra params and missing CF IP are rejected before any binding access', async () => {
  const valid = 'https://service.workers.dev/v1/weather?latitude=-33.87&longitude=151.21&language=en&timezone=Australia%2FSydney';
  const cases = [ [valid,'POST',405], [valid.replace('/v1/weather','/token'),'GET',404],
    [valid+'&url=https://attacker.test','GET',400], [valid+'&latitude=1','GET',400],
    [valid.replace('latitude=-33.87','latitude=NaN'),'GET',400],
    [valid.replace('longitude=151.21','longitude=181'),'GET',400],
    [valid.replace('language=en','language=xx'),'GET',400],
    [valid.replace('Australia%2FSydney','Invalid%2FZone'),'GET',400] ];
  for (const [url,method,status] of cases) {
    const response = await worker.fetch(new Request(url,{method,headers:{'CF-Connecting-IP':'203.0.113.1'}}),{});
    assert.equal(response.status,status,url);
    assert.equal(response.headers.get('Cache-Control'),'no-store');
  }
  assert.equal((await worker.fetch(new Request(valid),{})).status,503);
});

test('worker rounds coordinates, forwards only a daily hashed IP, and returns sanitized errors', async () => {
  let received;
  const env = { WEATHER_GATE: { getByName: name => {
    assert.equal(name, 'global-weather-v1');
    return { fetch: async request => { received = await request.json(); return Response.json({weather,attribution:{}}); } };
  } } };
  const request = new Request('https://service.workers.dev/v1/weather?latitude=-33.86785&longitude=151.2094&language=en&timezone=Australia%2FSydney',{headers:{'CF-Connecting-IP':'203.0.113.10'}});
  const response = await worker.fetch(request,env);
  assert.equal(response.status,200);
  assert.equal(received.latitude,-33.87);
  assert.equal(received.longitude,151.21);
  assert.match(received.ipHash,/^[a-f0-9]{64}$/);
  assert.ok(!JSON.stringify(received).includes('203.0.113.10'));
  const failed = await worker.fetch(request,{WEATHER_GATE:{getByName:()=>{throw Error('SECRET PRIVATE KEY AND IP');}}});
  assert.equal(failed.status,503);
  assert.deepEqual(await failed.json(),{error:'service_unavailable'});
});

test('calendar month quota resets on UTC boundary after restart', async () => {
  let now = Date.parse('2026-10-31T23:59:00Z');
  const first = makeService({now:()=>now,env:{MONTHLY_UPSTREAM_LIMIT:'2'}});
  await first.service.weather(query,ip);
  const restored = makeService({storage:new FakeStorage(first.storage.state),now:()=>now,env:{MONTHLY_UPSTREAM_LIMIT:'2'}});
  await rejectsCode(restored.service.weather(query,ip),'quota_exceeded');
  now = Date.parse('2026-11-01T00:00:00Z');
  await restored.service.weather(query,ip);
  assert.equal(restored.calls.length,2);
});

test('quota configuration cannot exceed safe defaults or silently accept malformed limits', async () => {
  for (const limit of ['400001','-1','0','abc','Infinity']) {
    const {service,calls} = makeService({env:{MONTHLY_UPSTREAM_LIMIT:limit}});
    await rejectsCode(service.weather(query,ip),'service_unavailable');
    assert.equal(calls.length,0);
  }
});

test('bounded weather cache evicts older locations and expired attribution is refetched', async () => {
  const {service,calls} = makeService();
  for (let i=0;i<65;i++) {
    await service.weather({...query,longitude:150+i/100},i.toString(16).padStart(64,'0'));
  }
  assert.equal(calls.length,66);
  await service.weather({...query,longitude:150},ip);
  assert.equal(calls.length,67);
});

test('invalid official logo partial paths fail closed rather than returning attacker links', async () => {
  for (const logo of ['https://attacker.test/logo.png','//attacker.test/logo.png','/\\\\attacker.test/logo.png',null]) {
    const fetch = async url => Response.json(String(url).includes('/attribution/') ? {...attribution,'logoLight@2x':logo} : weather);
    const {service} = makeService({fetch});
    await rejectsCode(service.weather(query,ip),'upstream_unavailable');
  }
});

test('bounded concurrent unique locations fail busy while eight loads are active', async () => {
  let release, ready;
  const blocked = new Promise(resolve=>{release=resolve;});
  const started = new Promise(resolve=>{ready=resolve;});
  let count=0;
  const fetch = async url => {
    if (!String(url).includes('/attribution/')) {
      if (++count===8) ready();
      await blocked;
    }
    return Response.json(String(url).includes('/attribution/') ? attribution : weather);
  };
  const {service} = makeService({fetch,timeoutMS:1000});
  const waiting = Array.from({length:8},(_,i)=>service.weather({...query,longitude:150+i/100},ip));
  await started;
  await rejectsCode(service.weather({...query,longitude:160},ip),'service_busy');
  release();
  await Promise.all(waiting);
});


test('corrupt persisted counters fail closed instead of bypassing quota', async () => {
  const storage = new FakeStorage();
  storage.state.data.set('upstream',{month:'2026-10',day:'2026-10-13',monthly:-1,daily:0});
  const {service,calls} = makeService({storage});
  await rejectsCode(service.weather(query,ip),'service_unavailable');
  assert.equal(calls.length,0);
});

test('default fetch retains Worker global receiver', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async function(url, options) {
    assert.equal(this, globalThis, 'native Worker fetch requires its global receiver');
    return fixtureFetcher()(url, options);
  };
  try {
    const service = new WeatherService(new FakeStorage(), environment());
    const result = await service.weather(query, ip);
    assert.equal(result.weather.currentWeather.temperature, weather.currentWeather.temperature);
  } finally { globalThis.fetch = original; }
});

// Diagnose the exact rejected field without exposing upstream data.
test('weather validation identifies the exact failed shape or count check', async () => {
  const cases = [
    ['weather-temperature', data => { data.currentWeather.temperature = null; }],
    ['weather-hourly-shape', data => { data.forecastHourly.hours = null; }],
    ['weather-hourly-count', data => { data.forecastHourly.hours = Array(49).fill(data.forecastHourly.hours[0]); }],
    ['weather-daily-shape', data => { data.forecastDaily.days = null; }],
    ['weather-daily-count', data => { data.forecastDaily.days = Array(4).fill(data.forecastDaily.days[0]); }]
  ];
  for (const [stage, mutate] of cases) {
    const data = structuredClone(weather); mutate(data);
    const { service } = makeService({fetch: async () => Response.json(data)});
    await assert.rejects(service.weather(query, ip), error => error.code === 'upstream_unavailable' && error.stage === stage);
  }
});

test('explicit hourly start avoids the near-midnight default range exceeding 48 entries', async () => {
  const now = Date.parse('2026-10-14T12:36:00Z');
  const { service, calls } = makeService({now: () => now, fetch: async (raw, options) => {
    const url = new URL(raw); calls.push({url: String(raw), options});
    if (url.pathname.startsWith('/attribution/')) return Response.json(attribution);
    const data = structuredClone(weather);
    data.forecastHourly.hours = Array(url.searchParams.has('hourlyStart') ? 26 : 49).fill(data.forecastHourly.hours[0]);
    return Response.json(data);
  }});
  const result = await service.weather(query, ip);
  assert.equal(result.weather.forecastHourly.hours.length, 26);
  const url = new URL(calls[0].url);
  assert.equal(url.searchParams.get('hourlyStart'), '2026-10-14T12:36:00.000Z');
  assert.equal(Date.parse(url.searchParams.get('hourlyEnd')) - Date.parse(url.searchParams.get('hourlyStart')), 86_400_000);
});
