// Renovate global config — consumed by .github/workflows/renovate.yml.
//
// Per-repo behaviour (which managers, what to group, schedules, labels) lives
// in each repo's renovate.json. This file only declares WHICH repos this
// orchestrator manages and the global runtime knobs.
//
// To onboard a new repo:
//   1. Add it to `repositories` below.
//   2. Add a `renovate.json` at the root of that repo (see nextcloud for the
//      reference shape).
//   3. Add a CMDB-notify workflow in that repo (uses the reusable workflow at
//      .github/workflows/cmdb-notify-renovate.yml in this repo).

module.exports = {
  platform: 'github',
  endpoint: 'https://api.github.com/',
  username: 'renovate[bot]',
  gitAuthor: 'Renovate Bot <noreply@databaes.net>',

  // We pre-provide renovate.json in each managed repo, so skip the auto
  // onboarding PR and require the config to exist.
  onboarding: false,
  requireConfig: 'required',

  // Pilot scope proven end-to-end on nextcloud (2026-05-18) — widened
  // 2026-09-11 to cover the rest of the self-hosted COTS-app fleet for the
  // ops-portal Updates tab. `infra-platform` itself is included ONLY for its
  // Authentik version pin (see the repo's own renovate.json, which scopes
  // Renovate down to a single customManager regex against
  // ansible/sso/sso_setup.yml — it must NOT run infra-platform's default
  // managers against the rest of this repo).
  repositories: [
    'TomasBFerreira/nextcloud',
    'TomasBFerreira/wikijs',
    'TomasBFerreira/media-stack',
    'TomasBFerreira/infra-platform',
  ],

  // Concurrency caps so a sleepy Friday doesn't open 40 PRs at once.
  prHourlyLimit: 4,
  prConcurrentLimit: 6,

  // Default labels applied to every Renovate PR. The `renovate` label is what
  // the Slack GitHub-app subscription filters on for the #upgrades channel,
  // and what the CMDB-notify workflow's `if` condition keys off.
  labels: ['renovate'],
};
