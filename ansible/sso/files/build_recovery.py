#!/usr/bin/env python3
"""Construct + bind Authentik's password-recovery flow (idempotent).

Authentik ships no recovery flow or blueprint, so build it from stages
(identification -> recovery email -> reuse the password-change prompt +
user-write stages), bind it to the brand, and set recovery_flow on the login
identification stage so the "Forgot password?" link renders. Reuses existing
objects on re-run. Reads AK_BASE (default localhost) + AK_TOKEN from env.

Run via the ansible `script` module (not an inline shell heredoc — ansible
tokenizes shell commands and chokes on embedded python quotes/braces).
"""
import os
import sys
import json
import urllib.request
import urllib.error

BASE = os.environ.get("AK_BASE", "http://localhost:9000/api/v3")
TOK = os.environ["AK_TOKEN"]


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


# 1) Recovery flow (reuse if present)
st, d = api("GET", "/flows/instances/?designation=recovery")
res = d.get("results", [])
flow = res[0] if res else must(*api("POST", "/flows/instances/", {
    "name": "Recovery", "title": "Reset your databaes.net password",
    "slug": "default-recovery-flow", "designation": "recovery",
    "authentication": "require_unauthenticated"}), "create flow")
flow_pk = flow["pk"]

# 2) Reuse the password-change prompt + user-write stages
st, allst = api("GET", "/stages/all/?page_size=200")
stages = allst.get("results", [])
bycomp = lambda sub: [s for s in stages if sub in (s.get("component") or "")]
named = lambda n: next((s for s in stages if s.get("name") == n), None)
prompt = next((s for s in bycomp("ak-stage-prompt")
               if "password" in (s.get("name") or "").lower()), None)
write = next(iter(bycomp("ak-stage-user-write")), None)
if not prompt or not write:
    print("no reusable prompt/write stages found")
    sys.exit(1)

# 3) Identification + 4) recovery email stages (create if absent)
ident = named("databaes-recovery-identification") or must(*api("POST", "/stages/identification/", {
    "name": "databaes-recovery-identification", "user_fields": ["username", "email"],
    "case_insensitive_matching": True}), "create identification")
email = named("databaes-recovery-email") or must(*api("POST", "/stages/email/", {
    "name": "databaes-recovery-email", "use_global_settings": True,
    "activate_user_on_success": True, "subject": "Reset your databaes.net password",
    "template": "email/password_reset.html"}), "create email")

# 5) Bind stages in order (idempotent)
st, existing = api("GET", "/flows/bindings/?target=%s" % flow_pk)
have = {b.get("stage") for b in existing.get("results", [])}
for spk, order in [(ident["pk"], 10), (email["pk"], 20), (prompt["pk"], 30), (write["pk"], 40)]:
    if spk in have:
        continue
    must(*api("POST", "/flows/bindings/", {
        "target": flow_pk, "stage": spk, "order": order,
        "evaluate_on_plan": True, "re_evaluate_policies": False}), "bind stage %s" % spk)

# 6) Bind flow to the brand (default recovery target)
buuid = api("GET", "/core/brands/")[1]["results"][0]["brand_uuid"]
must(*api("PATCH", "/core/brands/%s/" % buuid, {"flow_recovery": flow_pk}), "bind brand")

# 7) The "Forgot password?" LINK is rendered by the login flow's identification
#    stage (recovery_flow field). Re-send user_fields + sources because Authentik
#    re-validates the whole object on PATCH (omitted lists -> "need a source").
ids = api("GET", "/stages/identification/?page_size=200")[1].get("results", [])
for s in ids:
    nm = s.get("name") or ""
    if (nm == "default-authentication-identification" or "authentication" in nm.lower()) \
            and nm != "databaes-recovery-identification":
        must(*api("PATCH", "/stages/identification/%s/" % s["pk"], {
            "recovery_flow": flow_pk,
            "user_fields": s.get("user_fields") or [],
            "sources": s.get("sources") or []}), "set recovery_flow on %s" % nm)

print("recovery flow constructed + bound + login link enabled:", flow["slug"])
