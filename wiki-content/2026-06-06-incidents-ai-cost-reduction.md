# PAGE: `services/ops-portal/incidents-ai-cost-reduction` — NEW

**Title:** Ops Portal Incidents — AI remediation cost reduction

**Tags:** ops-portal, incidents, ai, cost, anthropic, runbook

# Ops Portal Incidents — AI remediation cost reduction

**Status:** Phase 1 shipped (PR on `feat/ai-cost-caching-and-model-routing`, 2026-06-06). Phase 2 (deterministic-first cascade) designed, not yet built.

This page is the plan and rationale for cutting the cost of the AI remediation worker in `ops-portal-incidents` without making it less reliable. It started from a simple question — *"AI is getting expensive; should I run a local LLM or build smarter automations?"* — and the answer turned out to be **neither first**: the biggest, safest wins are architectural.

## TL;DR

- A **local LLM does not "understand" your homelab better than retrieval does.** The worker already injects live context (pod logs, audit, runbooks, CMDB tier) at prompt time — that *is* a homelab-aware model, and it beats any fine-tune that goes stale the moment you deploy. Local is only ever a cost/privacy question, gated entirely on the GPU in `worker-node-gpu-01`.
- The real cost levers are: **(1) don't call an LLM for known failures, (2) prompt-cache the static prefix, (3) route by severity to cheaper models.**
- Phase 1 ships (2) and (3); Phase 2 is (1).

## How the worker calls Claude today

`internal/airemediation/worker.go` polls open incidents assigned to `ai` every 15s and, per incident:

1. Builds a prompt: incident metadata + alert payload + last 50 pod log lines + last 20 audit entries + service runbook + a static system prompt with the embedded ansible catalog.
2. Calls the Anthropic Messages API directly over HTTP (model was hardcoded `claude-opus-4-6`, `max_tokens` 1024).
3. Parses a `DECISION: RESOLVED|ESCALATE` line and an optional `ACTION:` line; Tier 0/0.5 actions are gated behind human approval (CMDB tier lookup), everything else can auto-execute.
4. On resolve, a second Claude call (`max_tokens` 256) writes the close-notes summary.

Cost scales with **real incident volume** — no incidents, no API calls (the 15s poll is a DB query). So the lever is per-incident cost, not the poll.

## Phase 1 — what shipped

### 1. Prompt caching on the decision system prompt
The system prompt + ansible catalog is byte-identical on every decision call. It's now sent as a `system` content block with `cache_control: {type: "ephemeral"}`. Prompt caching is **GA** — no `anthropic-beta` header needed with `anthropic-version: 2023-06-01`. On a cache hit the prefix is billed at ~0.1× and skips re-processing.

> **Caveat (verify, don't assume):** on Opus the **minimum cacheable prefix is 4096 tokens**. If the system block is below that, the API silently skips caching (`usage.cache_creation_input_tokens` stays 0) — the request still works, it just doesn't cache. The worker now logs `usage` (`cache_read`, `cache_write`, `input_tokens`, `output_tokens`) on every decision call so you can confirm hits in dev logs. If the prefix is under threshold, the summary-routing win below still stands on its own, and the prefix can be padded later if caching proves worthwhile.

### 2. Severity-based model routing
The decision can execute k8s/Proxmox actions, so **high-severity incidents stay on the capable model**; only low-severity (info) decisions and the close-note summary drop to cheaper tiers. All three are env-overridable; set them equal to disable routing entirely.

| Env var | Default | Used for |
|---|---|---|
| `AI_MODEL` | `claude-opus-4-6` | critical / warning / unknown-severity decisions |
| `AI_MODEL_LOW` | `claude-sonnet-4-6` | info-severity decisions |
| `AI_MODEL_SUMMARY` | `claude-haiku-4-5` | close-note synthesis (always) |

Unknown/empty severities fall through to the **high** tier, so a mislabelled incident is never under-served. The tier-guard (Tier 0/0.5 → human approval) is unchanged and protects critical infra regardless of which model made the call.

Relative pricing (per 1M tokens, in/out): Opus `$5/$25`, Sonnet `$3/$15`, Haiku `$1/$5`. Moving summaries Opus→Haiku is ~5× cheaper on those calls; info decisions Opus→Sonnet is ~1.7× cheaper.

**To disable routing** (pin everything to the old behaviour), set `AI_MODEL`, `AI_MODEL_LOW`, and `AI_MODEL_SUMMARY` all to `claude-opus-4-6` in the service's env / overlay.

### Testing
Unit tests cover severity→model mapping (incl. env overrides and the "routing disabled" case) and the outbound request shape against a mock Anthropic endpoint (`ANTHROPIC_BASE_URL`): the decision call sends exactly one `system` block with `cache_control: ephemeral` and threads the routed model through; the summary call sends no `cache_control` and uses the cheap model. No Slack is touched — Slack notifications only fire when `SLACK_WEBHOOK_URL` is set, which is prod-only, so dev/local testing is silent by design.

## Phase 2 — deterministic-first cascade (designed, not built)

The largest lever is **not calling an LLM at all for known failure signatures.** Most real incidents are ones you've seen: disk full → `disk_prune_logs`, DNS flake → `dns_flush`, CrashLoop → `pod_force_restart`. Those should be alert-rule → playbook mappings with zero LLM in the loop. The LLM is reserved for the novel/ambiguous incident.

```
alert ─▶ [deterministic rule match?] ─yes─▶ run playbook ─▶ Haiku writes debrief ─▶ auto-close
            │ no
            ▼
      [Haiku triage: known class?] ─▶ propose playbook (cached context)
            │ ambiguous / high-sev / Tier 0
            ▼
      [Opus decision] ─▶ execute or escalate-to-human
```

This is cheaper *and* faster (deterministic paths return in ms, not after a 90s API budget), and the "auto-close vs human-escalate" split the original question asked about falls out naturally. The cheap (Haiku) tier is also the clean drop-in point for a **local model later** — the client already honours `ANTHROPIC_BASE_URL`, so the cheap tier could point at a local OpenAI-compatible endpoint without touching the decision tier.

## On running a local LLM

Reframe it: knowledge of a constantly-changing homelab belongs in **retrieval**, not frozen weights. Don't fine-tune. The worker's existing prompt-time context injection is the right pattern. Local is purely a cost/privacy decision and hinges on one fact — **what GPU is in `worker-node-gpu-01`** (currently a GTX 970, passthrough deferred; see `/app/issues/gpu-passthrough-deferred.md`). A small local model (7B–32B) is fine for the cheap tier (classification, triage, debrief writing) but is **not** something to trust with "delete this prod pod." Keep the high-stakes decision on a frontier model.

## Open questions for the operator

1. **GPU in `worker-node-gpu-01`** — gates the local-model question entirely.
2. **Incidents/month hitting the AI worker** — tells us whether this is a $5/mo or a $200/mo problem, and how much of Phase 2 is worth building.

## References

- Repo: `ops-portal-incidents` branch `feat/ai-cost-caching-and-model-routing`.
- Rule: `/operations/cmdb-discipline` (a CMDB change was recorded for this work).
- Related: [GPU passthrough deferred](/infrastructure/proxmox-nodes) · `/app/issues/gpu-passthrough-deferred.md`.

---
