#!/usr/bin/env python3
"""Provision an Authentik OAuth2/OIDC application for the public landing page.

The landing page (databaes.net) is a static SPA. To show/hide the account +
admin nav by login state and group membership, it does a silent OIDC check
against Authentik. This creates a PUBLIC (PKCE, no secret) OAuth2 provider +
application with the groups scope so the ID token carries `groups`. Idempotent.

Reads AK_BASE (default localhost), AK_TOKEN, and ENVIRONMENT (dev|qa|prod) to
pick redirect URIs. Prints the client_id + issuer for the frontend config.
"""
import os
import sys
import json
import urllib.parse
import urllib.request
import urllib.error

BASE = os.environ.get("AK_BASE", "http://localhost:9000/api/v3")
TOK = os.environ["AK_TOKEN"]
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")

# Public hostnames the SPA can be served from per env (origin + silent-refresh).
ORIGINS = {
    "prod": ["https://databaes.net", "https://databaes-landing-page.databaes.net"],
    "qa":   ["https://databaes-landing-page-qa.databaes.net"],
    "dev":  ["https://databaes-landing-page-dev.databaes.net"],
}[ENVIRONMENT]


def api(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method, headers={
        "Authorization": "Bearer " + TOK, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            t = r.read().decode()
            return r.status, (json.loads(t) if t else {})
    except urllib.error.HTTPError as e:
        return e.code, {"_error": e.read().decode()}


def must(st, obj, what):
    if st not in (200, 201):
        print("FAIL %s: HTTP %s %s" % (what, st, json.dumps(obj)[:600]))
        sys.exit(1)
    return obj


# Scope mappings: openid/email/profile (managed) + a custom "groups" scope.
maps = api("GET", "/propertymappings/provider/scope/?page_size=200")[1].get("results", [])
mg = lambda m: m.get("managed") or ""
scope_pks = [m["pk"] for m in maps if any(k in mg(m) for k in ("scope-openid", "scope-email", "scope-profile"))]
# This Authentik build ships no managed "groups" scope — find or create one so the
# ID token carries group membership (needed to gate the admin nav by ops-admins).
grp = next((m for m in maps if m.get("scope_name") == "groups" or m.get("name") == "OAuth Groups"), None)
if not grp:
    grp = must(*api("POST", "/propertymappings/provider/scope/", {
        "name": "OAuth Groups", "scope_name": "groups", "description": "User group memberships",
        "expression": "return {\"groups\": [group.name for group in request.user.ak_groups.all()]}"}),
        "create groups scope mapping")
    print("created custom 'groups' scope mapping")
scope_pks.append(grp["pk"])
print("scope mappings resolved:", len(scope_pks))

# Authorization flow: implicit consent (silent check must not prompt).
flows = api("GET", "/flows/instances/?slug=default-provider-authorization-implicit-consent")[1].get("results", [])
if not flows:
    print("FAIL: implicit-consent authorization flow not found"); sys.exit(1)
auth_flow = flows[0]["pk"]

# Redirect URIs (regex match on each origin so /, /callback, /silent-refresh.html all pass).
redirect_uris = [{"matching_mode": "regex", "url": "%s/.*" % o} for o in ORIGINS]

# Create/update the OAuth2 provider (public client = PKCE, no secret).
prov = api("GET", "/providers/oauth2/?name=" + urllib.parse.quote("Landing Page"))[1].get("results", [])
provider_body = {
    "name": "Landing Page",
    "authorization_flow": auth_flow,
    "client_type": "public",
    "redirect_uris": redirect_uris,
    "sub_mode": "user_id",
    "include_claims_in_id_token": True,
    "property_mappings": scope_pks,
}
if prov:
    p = must(*api("PATCH", "/providers/oauth2/%s/" % prov[0]["pk"], provider_body), "update provider")
    print("updated provider Landing Page")
else:
    p = must(*api("POST", "/providers/oauth2/", provider_body), "create provider")
    print("created provider Landing Page")
client_id = p["client_id"]
provider_pk = p["pk"]

# Create/bind the application.
app = api("GET", "/core/applications/?slug=landing-page")[1].get("results", [])
app_body = {"name": "Landing Page", "slug": "landing-page", "provider": provider_pk}
if app:
    must(*api("PATCH", "/core/applications/landing-page/", app_body), "update application")
else:
    must(*api("POST", "/core/applications/", app_body), "create application")

host = {"prod": "auth.databaes.net", "qa": "auth-qa.databaes.net", "dev": "auth-dev.databaes.net"}[ENVIRONMENT]
print("LANDING_OIDC client_id=%s" % client_id)
print("LANDING_OIDC issuer=https://%s/application/o/landing-page/" % host)
print("OK: landing-page OIDC app provisioned for %s" % ENVIRONMENT)
