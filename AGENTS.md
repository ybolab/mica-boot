## Project Development

This repository follows the PMA workflow. The actual rules live in the `/pma`
skill — do not duplicate them here. If a rule in this file ever conflicts
with `/pma`, treat `/pma` as the source of truth and update this file.

### Skill stack

- `/pma` — workflow control, three-phase gate, task and plan tracking

The tree is bash, Python and Dockerfiles; no stack skill covers it, and
`/pma`'s *Delivery* rules apply directly.

### Triggers

Any feature, bug fix, refactor, planning, progress tracking, or multi-agent
execution goes through `/pma` (investigate → proposal → implement). Ceremony
is tiered by complexity per `/pma` *Task Tiers*: only trivial changes take
the fast path; everything else waits for explicit approval such as `proceed`.

### Project-specific facts

- The boot tooling of Mica OS: the UKI/FIT and initramfs builders (`initramfs.sh`, `kernel.sh`, `fit.sh`, `Dockerfile`, `Dockerfile.fit`), the boot-tools image (`build-tools.sh`), dm-verity signing (`verity-tool.sh`), the development signing inputs (`init-keys.sh`, `dev-keys.sh`), and under `common/` the inputs every board shares (`mos-required.fragment`, `mos-records.h`, `fstab.in`, `copyright`, the FIT trust and regdb helpers, `kernel-config-test.sh`)
- Consumed as the `boot/` **source pin** by the assembly (`mica-build`) and by every board repository (`mica-x64`, `mica-virt-arm64`, `mica-cx3576`, `mica-s905x5m`): `deps/sources/mica-boot.json` there names a commit and the source archive `mica-boot-<commit12>.tar.gz`; every script derives its consumer as the directory above `boot/`, or this checkout when it carries its own `build-env/`
- A change here is published by the workflow (`make publish-source`) as `ghcr.io/ybolab/mica-boot:source.build-<commit12>`, in the package named after this repository, and pinned in each consumer with `bash tools/deps.sh bump mica-boot`; a manual workflow run republishes an earlier commit byte-identically (`publish-source --revision <commit> --expect-sha256 <pinned digest>`)
- Quality gates: `make check` (lint, `trust-domain-test`, `boot-package-test`, `boot-compression-test`); the kernel-config check runs in each board repository over its own configuration
- Build resources: no fixed CPU, memory or job quotas; use the host and tool defaults

### Documentation entry points

- Tasks: `docs/task/index.md`
- Plans: `docs/plan/index.md`
- Changelog: `docs/changelog.md`
- Design and project management for the whole of Mica OS: `ybolab/mica`
