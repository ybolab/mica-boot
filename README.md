# mica-boot

The boot tooling of Mica OS: the UKI/FIT and initramfs builders
(`initramfs.sh`, `kernel.sh`, `fit.sh`, the boot-tools `Dockerfile` and
`Dockerfile.fit`), dm-verity signing (`verity-tool.sh`), the development
signing inputs (`init-keys.sh`, `dev-keys.sh`), and under `common/` what
every board shares: the kernel configuration floor
(`mos-required.fragment`), the firmware record layout (`mos-records.h`),
the template `fstab.in`, the board packages' `copyright`, the FIT trust and
regdb helpers, and `kernel-config-test.sh`.

It is **consumed at `boot/` by the assembly (`ybolab/mica-build`) and by
every board repository** (`mica-x64`, `mica-virt-arm64`, `mica-cx3576`,
`mica-s905x5m`) through a source pin, exactly like `mica-build-env` at
`build-env/`: `deps/sources/mica-boot.json` in the consumer names a commit
and its source archive, published by this repository's CI as
`ghcr.io/ybolab/mica-boot:source.build-<commit12>`, and the consumer's
`make deps` unpacks it there.
Every script derives its consumer as the directory above `boot/`; a
standalone checkout carrying its own `build-env/` (`make deps`) runs its
own gates:

```
make deps            # build-env/ at deps/sources/mica-build-env.json
make build-env       # the builder images
make check           # lint, trust-domain-test, boot-package-test, boot-compression-test
make publish-source  # this commit as mica-boot:source.build-<commit12> (CI only)
```
