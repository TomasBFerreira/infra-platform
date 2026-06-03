#!/usr/bin/env python3
"""Construct + bind Authentik's password-recovery flow (idempotent, self-healing).

Authentik ships no recovery flow or blueprint, so build it from stages:
  identification -> recovery email -> (password prompt) -> (user write)
reusing the canonical password-change flow's prompt + user-write stages, bind it
to the brand, and set recovery_flow on the login identification stage so the
"Forgot password?" link renders.

Self-correcting: removes stray/wrong stage bindings (e.g. an OOBE password prompt
or source-enrollment write picked up by an earlier non-deterministic selection)
and re-adds the correct ones. Reads AK_BASE (default localhost) + AK_TOKEN.

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
    if st not in (200, 201, 204):
        print("FAIL %s: HTTP %s %s" % (what, st, json.dumps(obj)[:600]))
        sys.exit(1)
    return obj


# 1) Recovery flow (reuse if present)
res = api("GET", "/flows/instances/?designation=recovery")[1].get("results", [])
flow = res[0] if res else must(*api("POST", "/flows/instances/", {
    "name": "Recovery", "title": "Reset your databaes.net password",
    "slug": "default-recovery-flow", "designation": "recovery",
    "authentication": "require_unauthenticated"}), "create flow")
flow_pk = flow["pk"]

# 2) Reuse the password prompt + user-write stages from the canonical
#    default-password-change flow (deterministic — NOT a fuzzy first-match, which
#    picked the OOBE prompt / source-enrollment write and broke the flow).
prompt_pk = write_pk = None
pcf = api("GET", "/flows/instances/default-password-change/")
if pcf[0] == 200:
    for b in api("GET", "/flows/bindings/?target=%s" % pcf[1]["pk"])[1].get("results", []):
        so = b.get("stage_obj", {})
        comp = so.get("component") or ""
        if "ak-stage-prompt" in comp and not prompt_pk:
            prompt_pk = b["stage"]
        if "ak-stage-user-write" in comp and not write_pk:
            write_pk = b["stage"]
# Fallback to well-known stage names if the password-change flow wasn't found.
allstages = api("GET", "/stages/all/?page_size=200")[1].get("results", [])
named = lambda n: next((s for s in allstages if s.get("name") == n), None)
if not prompt_pk:
    s = named("default-password-change-prompt")
    prompt_pk = s and s["pk"]
if not write_pk:
    s = named("default-user-settings-write")
    write_pk = s and s["pk"]
if not prompt_pk or not write_pk:
    print("FAIL: could not resolve password-change prompt/write stages")
    sys.exit(1)

# 3) Identification + 4) recovery email stages (create if absent)
ident = named("databaes-recovery-identification") or must(*api("POST", "/stages/identification/", {
    "name": "databaes-recovery-identification", "user_fields": ["username", "email"],
    "case_insensitive_matching": True}), "create identification")
email = named("databaes-recovery-email") or must(*api("POST", "/stages/email/", {
    "name": "databaes-recovery-email", "use_global_settings": True,
    "activate_user_on_success": True, "subject": "Reset your databaes.net password",
    "template": "email/password_reset.html"}), "create email")

# 5) Self-correcting bindings: remove any stage binding that isn't one of the four
#    desired stages (repairs earlier wrong picks), then add the missing ones.
desired = [(ident["pk"], 10), (email["pk"], 20), (prompt_pk, 30), (write_pk, 40)]
desired_pks = {pk for pk, _ in desired}
existing = api("GET", "/flows/bindings/?target=%s" % flow_pk)[1].get("results", [])
for b in existing:
    if b.get("stage") not in desired_pks:
        must(*api("DELETE", "/flows/bindings/%s/" % b["pk"]), "delete stray binding")
        print("removed stray binding:", (b.get("stage_obj") or {}).get("name"))
have = {b.get("stage") for b in existing if b.get("stage") in desired_pks}
for spk, order in desired:
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
for s in api("GET", "/stages/identification/?page_size=200")[1].get("results", []):
    nm = s.get("name") or ""
    if (nm == "default-authentication-identification" or "authentication" in nm.lower()) \
            and nm != "databaes-recovery-identification":
        must(*api("PATCH", "/stages/identification/%s/" % s["pk"], {
            "recovery_flow": flow_pk,
            "user_fields": s.get("user_fields") or [],
            "sources": s.get("sources") or []}), "set recovery_flow on %s" % nm)

print("recovery flow OK: stages = identification -> email -> password-prompt -> user-write; bound + link enabled")

# 8) Keep USERNAME admin-only: Authentik's default user-settings prompt lets users
#    self-edit their username (the login identifier). Drop the username field so
#    only name + email (+ password via the change flow) are self-service. Idempotent.
usf = api("GET", "/flows/instances/?slug=default-user-settings-flow")[1].get("results", [])
if usf:
    for b in api("GET", "/flows/bindings/?target=%s" % usf[0]["pk"])[1].get("results", []):
        if "prompt" not in ((b.get("stage_obj") or {}).get("component") or ""):
            continue
        st = api("GET", "/stages/prompt/stages/%s/" % b["stage"])[1]
        fields = st.get("fields", [])
        keep = [fpk for fpk in fields
                if (api("GET", "/stages/prompt/prompts/%s/" % fpk)[1].get("field_key") or "").lower() != "username"]
        if len(keep) != len(fields):
            must(*api("PATCH", "/stages/prompt/stages/%s/" % b["stage"], {"fields": keep}), "drop username from user-settings")
            print("user-settings: removed self-service username field (now admin-only)")
