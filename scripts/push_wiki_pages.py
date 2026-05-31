#!/usr/bin/env python3
"""Push wiki pages to wikijs from a structured markdown report.

Source format — sections separated by `---` on a line by itself:

    # PAGE: `<wiki-path>` — NEW|UPDATE
    **Title:** <title>            # required for NEW; ignored on UPDATE
    **Tags:** tag1, tag2          # optional

    ```markdown
    <page content — can contain nested ``` code blocks safely>
    ```

    ---

The outer ` ```markdown ` wrapper is optional but recommended for readability.
Parser is fence-agnostic: it takes everything between the metadata header
and the next `---` separator, then strips a leading ` ```markdown ` and
trailing ` ``` ` line if present. So nested 3-backtick code blocks survive.

Operations:
    NEW    — create the page. If it already exists, switches to UPDATE-replace.
    UPDATE — refresh the page. By default APPENDs the new content using an
             HTML-comment marker so re-runs are idempotent (the marker block
             is replaced, not re-appended). Pages in REPLACE_PATHS (the home
             page) instead get a full content replacement.

Usage:
    python3 push_wiki_pages.py <source-md> <gql-url> <token-file> \
        [--marker-id <slug>] [--replace-paths home/home,...] [--dry-run]

The token-file path is a path to a file containing the raw bearer token
(no quotes, no Bearer prefix). Pass `-` to read from stdin.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path


# ── parser ─────────────────────────────────────────────────────────────────

def parse_report(text: str) -> list[dict]:
    pages: list[dict] = []
    for section in re.split(r"^---$", text, flags=re.MULTILINE):
        m_path = re.search(
            r"^#\s*PAGE:\s*`([^`]+)`\s*[—-]\s*(NEW|UPDATE)",
            section,
            flags=re.MULTILINE,
        )
        if not m_path:
            continue
        path, op = m_path.group(1).strip(), m_path.group(2)

        m_title = re.search(r"^\*\*Title:\*\*\s*(.+)$", section, flags=re.MULTILINE)
        title = m_title.group(1).strip() if m_title else path.split("/")[-1]

        m_tags = re.search(r"^\*\*Tags:\*\*\s*(.+)$", section, flags=re.MULTILINE)
        tags = [t.strip() for t in m_tags.group(1).split(",")] if m_tags else []

        # Body = everything after the last metadata line up to end of section.
        after_idx = m_path.end()
        for m in (m_title, m_tags):
            if m and m.end() > after_idx:
                after_idx = m.end()
        body_lines = section[after_idx:].strip().split("\n")

        while body_lines and body_lines[0].strip() == "":
            body_lines.pop(0)
        if body_lines and body_lines[0].rstrip() == "```markdown":
            body_lines.pop(0)
            for i in range(len(body_lines) - 1, -1, -1):
                if body_lines[i].rstrip() == "```":
                    del body_lines[i]
                    break

        content = "\n".join(body_lines).strip()
        if not content:
            print(f"  WARN: {path} has no content; skipping", file=sys.stderr)
            continue

        pages.append({"path": path, "title": title, "op": op,
                      "tags": tags, "content": content})
    return pages


# ── GraphQL helpers ────────────────────────────────────────────────────────

class WikiClient:
    def __init__(self, gql_url: str, token: str, timeout: int = 30):
        self.gql_url = gql_url
        self.timeout = timeout
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    def query(self, q: str, vars_: dict | None = None) -> dict:
        body = json.dumps({"query": q, "variables": vars_ or {}}).encode()
        req = urllib.request.Request(self.gql_url, data=body,
                                     headers=self.headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"HTTP {e.code} from wikijs: {e.read().decode()}")


LIST_Q = "{ pages { list(orderBy: PATH) { id path locale } } }"

SINGLE_Q = """
query Single($id: Int!) {
  pages {
    single(id: $id) { id path title description content tags { tag } locale }
  }
}
"""

CREATE_MUT = """
mutation Create($content: String!, $description: String!, $editor: String!,
                $isPublished: Boolean!, $isPrivate: Boolean!, $locale: String!,
                $path: String!, $tags: [String]!, $title: String!) {
  pages {
    create(content: $content, description: $description, editor: $editor,
           isPublished: $isPublished, isPrivate: $isPrivate, locale: $locale,
           path: $path, tags: $tags, title: $title) {
      responseResult { succeeded errorCode message }
      page { id path }
    }
  }
}
"""

UPDATE_MUT = """
mutation Update($id: Int!, $content: String!, $description: String!,
                $editor: String!, $isPrivate: Boolean!, $isPublished: Boolean!,
                $locale: String!, $path: String!, $tags: [String]!,
                $title: String!) {
  pages {
    update(id: $id, content: $content, description: $description, editor: $editor,
           isPrivate: $isPrivate, isPublished: $isPublished, locale: $locale,
           path: $path, tags: $tags, title: $title) {
      responseResult { succeeded errorCode message }
      page { id path }
    }
  }
}
"""


# ── push logic ─────────────────────────────────────────────────────────────

def push(client: WikiClient, pages: list[dict], *,
         marker_id: str,
         replace_paths: set[str],
         dry_run: bool = False) -> tuple[int, int, list[tuple]]:
    locale = "en"
    marker_inner = f"wiki-push: {marker_id}"
    marker = f"\n\n<!-- {marker_inner} -->\n\n"

    print(f"=== fetching existing page list ===", flush=True)
    resp = client.query(LIST_Q)
    existing = {(p["path"], p.get("locale") or "en"): p["id"]
                for p in resp["data"]["pages"]["list"]}
    print(f"  found {len(existing)} pages on wiki", flush=True)
    print(f"  marker: <!-- {marker_inner} -->", flush=True)

    ok = failed = 0
    report: list[tuple] = []

    for p in pages:
        path, op, title = p["path"], p["op"], p["title"]
        tags = p["tags"]
        content_in = p["content"]
        key = (path, locale)
        page_id = existing.get(key)

        print(f"\n--- {op:6} {path} ---", flush=True)

        # Decide action
        if op == "NEW" and page_id is not None:
            print(f"  page already exists at id={page_id}; switching to UPDATE-replace")
            op = "UPDATE-replace"

        if op == "UPDATE" and path in replace_paths:
            op = "UPDATE-replace"

        if op == "NEW":
            if dry_run:
                print(f"  DRY-RUN would CREATE  title={title!r} tags={tags} len={len(content_in)}")
                report.append((path, "dry-create", None, len(content_in)))
                ok += 1
                continue
            vars_ = {"content": content_in, "description": "", "editor": "markdown",
                     "isPublished": True, "isPrivate": False, "locale": locale,
                     "path": path, "tags": tags, "title": title}
            res = client.query(CREATE_MUT, vars_)["data"]["pages"]["create"]
            rr = res["responseResult"]
            if rr["succeeded"]:
                pid = res["page"]["id"]
                existing[key] = pid
                print(f"  CREATED id={pid}  len={len(content_in)}")
                ok += 1
                report.append((path, "created", pid, len(content_in)))
            else:
                print(f"  CREATE FAILED: {rr['message']}")
                failed += 1
                report.append((path, f"create-failed: {rr['message']}", None, None))
            continue

        # All remaining ops require the page to exist
        if page_id is None:
            print(f"  page does not exist — skipping (was UPDATE)")
            report.append((path, "skip-missing", None, None))
            failed += 1
            continue

        # Fetch current
        cur = client.query(SINGLE_Q, {"id": page_id})["data"]["pages"]["single"]
        cur_content = cur.get("content") or ""

        if op == "UPDATE-replace":
            new_content = content_in
            action = "replaced"
        else:
            # APPEND with marker (idempotent)
            if marker_inner in cur_content:
                # Truncate at marker and re-append
                idx = cur_content.index(marker_inner)
                # back up to the opening "<!--"
                lt = cur_content.rfind("<!--", 0, idx)
                if lt == -1:
                    lt = idx
                base = cur_content[:lt].rstrip()
                new_content = base + marker + content_in
                action = "re-appended"
            else:
                new_content = cur_content.rstrip() + marker + content_in
                action = "first-append"

        if new_content == cur_content:
            print("  no change — skipping")
            report.append((path, "no-change", page_id, len(cur_content)))
            ok += 1
            continue

        if dry_run:
            delta = len(new_content) - len(cur_content)
            print(f"  DRY-RUN would {action}  id={page_id}  {len(cur_content)} -> {len(new_content)} ({delta:+d})")
            report.append((path, f"dry-{action}", page_id, len(new_content)))
            ok += 1
            continue

        merged_tags = [t["tag"] for t in (cur.get("tags") or [])]
        for t in tags:
            if t not in merged_tags:
                merged_tags.append(t)
        vars_ = {"id": page_id, "content": new_content,
                 "description": cur.get("description") or "",
                 "editor": "markdown", "isPrivate": False, "isPublished": True,
                 "locale": cur.get("locale") or "en", "path": path,
                 "tags": merged_tags, "title": cur.get("title") or title}
        res = client.query(UPDATE_MUT, vars_)["data"]["pages"]["update"]
        rr = res["responseResult"]
        if rr["succeeded"]:
            delta = len(new_content) - len(cur_content)
            print(f"  {action.upper()} id={page_id}  {len(cur_content)} -> {len(new_content)} ({delta:+d})")
            ok += 1
            report.append((path, action, page_id, len(new_content)))
        else:
            print(f"  UPDATE FAILED: {rr['message']}")
            failed += 1
            report.append((path, f"update-failed: {rr['message']}", page_id, None))

    return ok, failed, report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", help="path to the markdown source file")
    ap.add_argument("gql_url", help="wikijs GraphQL endpoint URL")
    ap.add_argument("token_file", help="path to file containing the API token (or - for stdin)")
    ap.add_argument("--marker-id",
                    help="idempotency tag for APPEND updates "
                         "(default: source file basename without extension)")
    ap.add_argument("--replace-paths", default="home/home",
                    help="comma-separated wiki paths to fully REPLACE on UPDATE "
                         "(default: home/home)")
    ap.add_argument("--dry-run", action="store_true",
                    help="parse + plan only; no mutations")
    args = ap.parse_args()

    token = sys.stdin.read().strip() if args.token_file == "-" \
        else Path(args.token_file).read_text().strip()
    if not token:
        print("ERROR: empty token", file=sys.stderr)
        return 2

    text = Path(args.source).read_text()
    pages = parse_report(text)
    if not pages:
        print("ERROR: no sections parsed; check `# PAGE:` header format", file=sys.stderr)
        return 2

    marker_id = args.marker_id or Path(args.source).stem
    replace_paths = {p.strip() for p in args.replace_paths.split(",") if p.strip()}

    print(f"=== parsed {len(pages)} sections ===")
    for p in pages:
        print(f"  {p['op']:6}  {p['path']:55}  len={len(p['content']):>6}  title={p['title']!r}")

    client = WikiClient(args.gql_url, token)
    ok, failed, report = push(client, pages,
                              marker_id=marker_id,
                              replace_paths=replace_paths,
                              dry_run=args.dry_run)

    print(f"\n=== summary ===")
    print(f"  ok: {ok}   failed: {failed}")
    for row in report:
        print(f"  {row}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
