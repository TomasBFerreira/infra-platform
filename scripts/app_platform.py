#!/usr/bin/env python3
"""Helpers for .github/workflows/app-provision.yml (Developer-area apps).

  app_platform.py check   <slug> <env> [--port N] [--request-id ID]
  app_platform.py unpack  <draft.tar.gz> <dest-dir>
  app_platform.py render  <slug> <env> <port> <image> [--template F]

check   validates the workflow inputs before anything uses them (exit 2 on
        refusal). Slug rules are app_dns.py's.
unpack  extracts a draft export into dest-dir, which must not exist yet.
        Developer content is only ever regular files below dest-dir: absolute
        paths, `..`, links, devices, hidden top-level `.git`/`.github` and
        oversized archives are refused, and file modes are reset to 0644.
render  prints the app's Kubernetes manifest from the fixed template.
"""
import argparse
import importlib.util
import os
import re
import string
import sys
import tarfile

here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("app_dns", os.path.join(here, "app_dns.py"))
app_dns = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(app_dns)
Refused = app_dns.Refused

# Only dev is enabled. QA and prod are promotions (spec slice 14) and each
# needs its own validation before it is switched on here.
ENABLED_ENVS = ("dev",)
PORT_RANGE = range(31000, 31900)
REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9-]{8,64}$")
IMAGE_RE = re.compile(r"^platform\.local/app-[a-z][a-z0-9-]{1,30}[a-z0-9]:[0-9a-f]{7,40}$")

MAX_FILES = 500
MAX_TOTAL_BYTES = 64 << 20
# One path segment: no control characters, no backslash, not `.` or `..`.
SEGMENT_RE = re.compile(r"^[^\x00-\x1f\x7f\\/]{1,255}$")
FORBIDDEN_TOP = {".git", ".github"}


def check(slug, env, port=None, request_id=None):
    app_dns.check_slug(slug)
    if env not in ENABLED_ENVS:
        raise Refused(f"env {env!r} is not enabled for app provisioning (enabled: {', '.join(ENABLED_ENVS)})")
    if port is not None and port not in PORT_RANGE:
        raise Refused(f"port {port} outside {PORT_RANGE.start}-{PORT_RANGE.stop - 1}")
    if request_id is not None and not REQUEST_ID_RE.match(request_id):
        raise Refused("request id must be 8-64 letters, digits or dashes")


def safe_parts(name):
    """Path segments of an archive member, or Refused."""
    if name.startswith("/") or name.startswith("./") and name[2:].startswith("/"):
        raise Refused(f"absolute path in archive: {name!r}")
    parts = [p for p in name.split("/") if p not in ("", ".")]
    if not parts:
        raise Refused(f"empty path in archive: {name!r}")
    for p in parts:
        if p == ".." or not SEGMENT_RE.match(p):
            raise Refused(f"unsafe path in archive: {name!r}")
    if parts[0].lower() in FORBIDDEN_TOP:
        raise Refused(f"{parts[0]} is not allowed in an app draft")
    return parts


def unpack(archive, dest):
    if os.path.exists(dest):
        raise Refused(f"{dest} already exists")
    os.makedirs(dest)
    root = os.path.realpath(dest)
    count = total = 0
    with tarfile.open(archive, "r:gz") as tf:
        for m in tf:
            if m.isdir():
                continue
            if not m.isreg():
                raise Refused(f"only regular files are allowed in a draft: {m.name!r}")
            parts = safe_parts(m.name)
            count += 1
            total += m.size
            if count > MAX_FILES:
                raise Refused(f"more than {MAX_FILES} files")
            if total > MAX_TOTAL_BYTES:
                raise Refused(f"archive larger than {MAX_TOTAL_BYTES} bytes unpacked")
            target = os.path.realpath(os.path.join(root, *parts))
            if not target.startswith(root + os.sep):
                raise Refused(f"path escapes the destination: {m.name!r}")
            os.makedirs(os.path.dirname(target), exist_ok=True)
            src = tf.extractfile(m)
            with open(target, "wb") as out:
                left = m.size
                while left > 0:
                    chunk = src.read(min(left, 1 << 16))
                    if not chunk:
                        raise Refused(f"truncated archive member {m.name!r}")
                    out.write(chunk)
                    left -= len(chunk)
            os.chmod(target, 0o644)
    return {"files": count, "bytes": total}


def render(slug, env, port, image, template):
    check(slug, env, port)
    if not IMAGE_RE.match(image):
        raise Refused(f"unexpected image reference {image!r}")
    if not image.startswith(f"platform.local/app-{slug}:"):
        raise Refused("image does not belong to this app")
    with open(template, encoding="utf-8") as f:
        tpl = string.Template(f.read())
    return tpl.substitute(slug=slug, env=env, port=port, image=image)


def main(argv):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check")
    c.add_argument("slug")
    c.add_argument("env")
    c.add_argument("--port", type=int)
    c.add_argument("--request-id")
    u = sub.add_parser("unpack")
    u.add_argument("archive")
    u.add_argument("dest")
    r = sub.add_parser("render")
    r.add_argument("slug")
    r.add_argument("env")
    r.add_argument("port", type=int)
    r.add_argument("image")
    r.add_argument("--template", default=os.path.join(os.path.dirname(here), "apps-platform", "manifest.tpl.yaml"))
    a = ap.parse_args(argv[1:])
    try:
        if a.cmd == "check":
            check(a.slug, a.env, a.port, a.request_id)
            print("ok")
        elif a.cmd == "unpack":
            res = unpack(a.archive, a.dest)
            print(f"unpacked {res['files']} file(s), {res['bytes']} bytes")
        else:
            sys.stdout.write(render(a.slug, a.env, a.port, a.image, a.template))
    except Refused as e:
        print(f"REFUSED: {e}", file=sys.stderr)
        return 2
    except (tarfile.TarError, OSError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
