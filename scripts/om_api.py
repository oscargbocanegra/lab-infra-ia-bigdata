#!/usr/bin/env python3
"""
OpenMetadata API helper script for Phase 9A ingestion setup.
Run inside Docker on master1 with --network internal.
"""

import requests
import json
import sys

BASE = "http://openmetadata_openmetadata-server:8585/api/v1"

# ---------------------------------------------------------------------------
# Login
# ---------------------------------------------------------------------------
r = requests.post(
    BASE + "/users/login",
    json={"email": "admin@lab.local", "password": "T3Blbk1ldGFkYXRhMjAyNiE="},
)
r.raise_for_status()
token = r.json()["accessToken"]
print("LOGIN OK", file=sys.stderr)

headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json",
}

# ---------------------------------------------------------------------------
# 1. Get ingestion-bot user ID
# ---------------------------------------------------------------------------
r2 = requests.get(BASE + "/users/name/ingestion-bot", headers=headers)
print("=== ingestion-bot ===")
print(json.dumps(r2.json(), indent=2))
bot_id = r2.json().get("id")
print(f"\nBot ID: {bot_id}", file=sys.stderr)

# ---------------------------------------------------------------------------
# 2. Generate bot JWT token (try different JWTTokenExpiry values)
# ---------------------------------------------------------------------------
for expiry in ["Unlimited", "90", "60", "30", "7", "OneYear", "NoExpiry"]:
    resp = requests.put(
        BASE + "/users/security/token",
        headers=headers,
        json={"JWTTokenExpiry": expiry, "tokenName": f"ingestion-bot-{expiry}"},
    )
    print(f"\n--- JWTTokenExpiry={expiry} => HTTP {resp.status_code} ---")
    print(resp.text[:500])
    if resp.status_code == 200:
        print(f"\n✅ SUCCESS with JWTTokenExpiry={expiry}")
        bot_token = resp.json().get("JWTToken") or resp.json().get("token")
        print(f"BOT TOKEN: {bot_token}")
        break
