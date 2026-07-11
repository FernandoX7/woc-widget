# Verification

`./scripts/verify.sh` is the deterministic production gate. It runs the WoCKit unit tests, checks
every Swift source, builds preview and production bundles, validates signing/resources, and (unless
explicitly skipped) samples the closed-popover process. It also enforces two source-level contracts:

- `Sources/WoCKit` cannot import SwiftUI, AppKit, or Charts. This keeps the domain package
  headlessly testable and prevents a UI dependency from crossing the module boundary unnoticed.
- Every explicit `LocalizedStringKey`, `String(localized:)`, and Foundation `t(...)` key must have
  exactly one catalog counterpart, and every catalog key must remain reachable from Swift.

The fast source checks can also be run independently:

```sh
./scripts/check-source-invariants.sh
./scripts/check-localizations.py
```

## Live API contracts

`./scripts/smoke-live-api.py` makes real, credential-free requests to all seven public feeds used by
the app. It checks stable JSON shape, numeric safety, and the configured WOC market identity without
pinning volatile counts, prices, release text, or leaderboard membership.

Because network availability is nondeterministic, this script is intentionally absent from PR and
push CI. `.github/workflows/live-api-contracts.yml` runs it daily on the default branch and exposes a
manual workflow trigger. A scheduled failure therefore signals upstream downtime or schema drift
without blocking unrelated development. Maintainers still run and investigate it before a public
release, while distinguishing an upstream outage from a real contract change.
