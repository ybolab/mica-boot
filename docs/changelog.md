# Changelog

## 2026-09-13 16:30 [progress]

Created from `pkgs/mos-boot/` (21 commits) and `boards/common/` (12
commits) of `ybolab/mica-build`, each kept through `git subtree split` and
the shared inputs added back under `common/`, then the tree at the Mica OS
rename. Moved in with them: the trust-domain test (wired to `make check`), the
container-side boot-package and boot-compression scripts (no driver ran them
in the assembly; kept beside the tooling, unwired), and the kernel-config
check as `common/kernel-config-test.sh` for the board repositories to run.
The boot-tools image reads the Debian snapshot from the `mica-debian` pin,
at `rootfs/debian/` in the assembly and `debian/` elsewhere. Consumed
as the `boot/` source pin (`20260913-1600-split-boot-and-boards`).
