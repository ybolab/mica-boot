# mica-boot: the boot tooling of Mica OS -- the UKI/FIT and initramfs
# builders, the boot-tools image, dm-verity signing, the development signing
# inputs -- and the shared board inputs under common/. Consumed as the
# `boot/` source pin by the assembly and by every board repository; the
# targets here are the tooling's own gates.

ifeq ($(filter deps,$(MAKECMDGOALS)),)
ifeq ($(wildcard build-env/from.sh),)
$(error build-env/ is empty: the build substrate is fetched at its pin from ybolab/mica-build-env. Run: make deps)
endif
endif

MICA_SIGNING_OUTPUT ?= meta

.PHONY: help deps deps-check deps-bump build-env boot-tools keys-init devkeys trust-domain-test lint check publish-source

help:
	@echo "  deps                fetch build-env/ and debian/ at their pins (deps/sources/); deps-check reads without downloading"
	@echo "  build-env           the builder images, from the pins in build-env/images.env"
	@echo "  boot-tools          the boot-tools image (build-tools.sh)"
	@echo "  keys-init / devkeys development signing inputs into \$$MICA_SIGNING_OUTPUT (default meta/)"
	@echo "  trust-domain-test   the key generators refuse aliasing, symlinks and concurrent runs"
	@echo "  lint                shell hygiene of the tree"
	@echo "  check               lint and trust-domain-test"
	@echo "  publish-source      this commit as the release build-<commit12> (tools/deps.sh publish-source)"

deps:
	bash tools/deps.sh fetch
deps-check:
	bash tools/deps.sh fetch --check
deps-bump:
	@test -n "$(DEP)" || { echo "error: DEP=<repository> is required, e.g. make deps-bump DEP=mica-build-env" >&2; exit 1; }
	bash tools/deps.sh bump "$(DEP)" $(if $(DEP_TAG),--tag "$(DEP_TAG)")

build-env:
	bash build-env/build.sh

boot-tools:
	bash build-tools.sh

keys-init:
	bash init-keys.sh --out "$(MICA_SIGNING_OUTPUT)"
devkeys:
	bash dev-keys.sh --out "$(MICA_SIGNING_OUTPUT)"

trust-domain-test:
	bash tests/trust-domain-hygiene-test.sh

# tests/boot-startup-package-test.sh, tests/boot-startup-pack-fixture.sh
# and tests/boot-compression-test.sh are CONTAINER-SIDE scripts (they read
# /src, /input, /output and /tools of the boot-tools image) that no harness
# drove in the assembly either; they are kept with the tooling they test and
# are not wired to a target until a driver exists (see the changelog).

lint:
	bash gate/shell-lint.sh

check: lint trust-domain-test

publish-source:
	bash tools/deps.sh publish-source
