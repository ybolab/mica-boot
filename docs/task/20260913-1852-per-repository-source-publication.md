# 20260913-1852-per-repository-source-publication Publish this repository's source to its own package from CI

- **status**: in_progress
- **priority**: P1
- **owner**: vwul1y5i
- **createdAt**: 2026-09-13 18:52

## Description

The user's 2026-09-13 direction (relayed by coordinator a0psyi7e): every
repository owns its CI and publishes a package named after itself, replacing
the shared `mica-source` package. Prepare mica-boot's source publication to
`ghcr.io/ybolab/mica-boot:source.build-<commit12>`, with a ref-selectable CI
path that republishes an already pinned commit (the assembly pins
`e7022164`) byte-identically, independent of later content.

Acceptance: the archive of an earlier commit is that commit's tree only and
matches the digest a consumer pins; a wrong expected digest writes nothing;
fetch and bump read the per-repository package; tests against a local registry.
No publication from a developer machine; publishing waits for the user's grant
and for the common publisher/reference contract.

## ActiveForm

Preparing per-repository source publication

## Dependencies

- **blocked by**: mica-build-env 211634797dde and mica-debian 8a3ef0d1e67a published to their own packages (CI `make deps`); package `ybolab/mica-boot` made public once after its first push
- **blocks**: consumers pinning mica-boot from its own package

## Notes

- `git archive` is compressed with `gzip -cn`: git 2.47 in-process gzip gives
  `f9cec147…` for e7022164, `gzip -cn` gives the pinned `5ae0c452…` under git
  2.34 and 2.47 alike. The same holds for this repository's pins
  mica-build-env 2116347 and mica-debian 8a3ef0d.
- Contract confirmed 2026-09-13: `<owner>/<repository>:source.build-<commit12>`.
  `tools/deps.sh` is vendored byte-for-byte from mica-build-env e242992
  (sha256 6e3b9441…): per-repository packages, a 404-only digest-verified read
  of the shared `mica-source` package, `gzip -cn` archives, and
  `publish-source --revision <40 hex> --expect-sha256 <64 hex>`.
- Two separate source contents, each labelled as itself: the transport-only
  baseline `e7022164` (sha256 5ae0c452…, already pinned by the assembly) and
  the runkit transition `5ac03711` (sha256 29f8a2b0…).
