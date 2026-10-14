#!/usr/bin/env python3
"""Validate the public app endpoint without making a request or reading a key."""
import ipaddress
import re
import sys
from urllib.parse import urlsplit


def is_valid_endpoint(value):
    if not value or any(character.isspace() for character in value):
        return False
    try:
        endpoint = urlsplit(value)
        host = endpoint.hostname
        if (endpoint.scheme != "https" or not host or endpoint.username is not None
                or endpoint.password is not None or endpoint.query or endpoint.fragment
                or "?" in value or "#" in value
                or endpoint.path != "/v1/weather" or endpoint.port not in (None, 443)):
            return False
        try:
            return ipaddress.ip_address(host).is_global
        except ValueError:
            return ("." in host and not host.endswith((".local", ".localhost", ".internal", ".test", ".invalid"))
                    and len(host) <= 253 and all(
                        re.fullmatch(r"[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?", label)
                        for label in host.split(".")))
    except ValueError:
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2 or not is_valid_endpoint(sys.argv[1]):
        print("Error: invalid weather service URL.", file=sys.stderr)
        sys.exit(2)
