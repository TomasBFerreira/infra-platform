# wiki-content/

Source files for `push-wiki-pages.yml`. Each file is a batch of wiki page
mutations — new pages or updates to existing ones — pushed to wikijs prod
in one go.

## Workflow

1. Add or edit a `.md` file under this directory.
2. PR + review. Once merged to `main`, dispatch the push:

   ```bash
   gh workflow run push-wiki-pages.yml --repo TomasBFerreira/infra-platform \
     -f source_path=wiki-content/<your-file>.md
   ```

3. The workflow runs on `[self-hosted, prod]`, fetches the wikijs API token
   from bootstrap vault (`secret/wikijs/prod/api-token` field `token`), and
   POSTs each section. Idempotent — safe to re-run.

Use `-f dry_run=true` first if you want to see what would change without
mutating anything.

## File format

Sections are separated by `---` on a line by itself. Each section starts with
a `# PAGE:` header naming the wiki path + operation:

````markdown
# PAGE: `operations/runbooks/my-runbook` — NEW

**Title:** My runbook title

**Tags:** runbook, ops, automation

```markdown
# My runbook title

Body of the page. Can contain nested code blocks:

\`\`\`bash
echo "this is fine"
\`\`\`

(or just write triple-backtick fences directly — the parser handles them.)
```

---

# PAGE: `home/home` — UPDATE

**Title:** Homelab Wiki

```markdown
... full replacement content ...
```

---
````

### Fields

| Field | Required? | Notes |
|-------|-----------|-------|
| `# PAGE: <path> — NEW\|UPDATE` | yes | `path` is the wiki path without leading `/` |
| `**Title:** ...` | yes for NEW | Ignored on UPDATE — existing title preserved |
| `**Tags:** a, b, c` | no | Merged with existing tags on UPDATE |
| body inside ` ```markdown ... ``` ` | yes | The outer fence is optional — body content is everything between metadata lines and the next `---` separator |

### Operations

- **NEW** — create the page. If it already exists, the workflow flips to
  UPDATE-replace automatically (so a stale `NEW` flag won't error out).
- **UPDATE** — by default, **append** the body to the existing page using an
  HTML-comment marker. Re-runs of the same source file are idempotent: the
  marker block is replaced, not duplicated.
- **UPDATE for paths in `replace_paths`** (default: `home/home`) — full
  content replacement instead of append. Pass `-f replace_paths=path1,path2`
  to extend the list.

### Marker format

Append blocks land between `<!-- wiki-push: <marker-id> -->` and end-of-page.
The `marker-id` defaults to the source filename without extension
(`wiki-content/2026-05-31-pbs-restore.md` → marker-id `2026-05-31-pbs-restore`).
Override with `-f marker_id=<slug>` if you want multiple batches to coexist
on the same page.

## After a push

- Verify the touched pages in the wiki UI.
- The workflow's job log prints a summary table with before/after lengths.
- Log a CMDB change separately via `cmdb-record.yml` if the batch is
  substantive (this workflow does NOT auto-record).

## When something goes wrong

| Symptom | Likely cause |
|---------|--------------|
| `wikijs unreachable at http://192.168.10.21:3000/graphql` | wikijs pod down or the prod worker not running. Check via `wikijs-debug.yml`. |
| `ERROR: token at secret/wikijs/prod/api-token is empty` | Vault path missing. Seed via `seed-bootstrap-vault.yml` (`secret_path=...` — see `docs/vaults.md`). |
| `HTTP 401 Unauthorized` from wikijs | Token expired or revoked. Re-issue in wikijs (Administration → API Access) and re-seed in vault. |
| `parse error` / no sections parsed | Missing `# PAGE:` header or wrong format. Run the script locally against your source with `--dry-run` to spot it. |
