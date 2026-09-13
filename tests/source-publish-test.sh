#!/usr/bin/env bash
# tools/deps.sh publish-source, bump and fetch against a real registry: the
# source artifact lives in the package named after its repository, an earlier
# commit is published with its own tree and nothing of the publishing
# checkout, and an expected digest refuses before anything is written.
#
#   bash tests/source-publish-test.sh        (docker on the host)
#
# The registry is the upstream registry image, run as a labelled sibling
# container on the docker network the host is on and spoken to over plain
# HTTP. Scratch lives under this checkout's .tmp/. No gh, no network beyond
# the sibling; nothing reaches ghcr.io.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/.." && pwd)"
for t in curl sha256sum jq docker git tar gzip; do
    command -v "${t}" >/dev/null 2>&1 || { echo "error: ${t} is required" >&2; exit 1; }
done
mkdir -p "${REPO}/.tmp"
WORK="$(mktemp -d "${REPO}/.tmp/source-publish-test.XXXXXX")"
NAME="ai-agent-source-publish-test-$$"
cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; rm -rf "${WORK}"; }
trap cleanup EXIT
PASS_N=0
FAIL_N=0
pass() { PASS_N=$((PASS_N + 1)); echo "PASS: $1"; }
fail() { FAIL_N=$((FAIL_N + 1)); echo "FAIL: $1"; sed 's/^/    /' "${LOG}" | tail -n 5; }
says() { grep -q -- "$2" "$1"; }

# ------------------------------------------------------------ the registry
IMAGE="${MICA_TEST_REGISTRY_IMAGE:-registry:2@sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373}"
NET="${MICA_TEST_NETWORK:-traefik}"
docker run -d --rm --label ai-agent=true --name "${NAME}" --network "${NET}" "${IMAGE}" >/dev/null
for _ in $(seq 1 30); do
    curl -sf -o /dev/null "http://${NAME}:5000/v2/" && break
    sleep 1
done
curl -sf -o /dev/null "http://${NAME}:5000/v2/" || { echo "error: the registry ${NAME} did not answer on ${NET}" >&2; exit 1; }
REGISTRY="${NAME}:5000"
export MICA_REGISTRY="${REGISTRY}/testorg" MICA_REGISTRY_USER=nobody MICA_REGISTRY_PLAIN_HTTP=1 \
    MICA_DEPS_TOKEN_VAR=OCI_TEST_TOKEN MICA_DEPS_NO_GH=1 OCI_TEST_TOKEN=fixture-token
LOG="${WORK}/log"
manifest() { # <package> <ref> <out> -> status
    curl -sS -o "$3" -w '%{http_code}' -H 'Accept: application/vnd.oci.image.manifest.v1+json' "http://${REGISTRY}/v2/testorg/$1/manifests/$2"
}
archive_sha() { # <checkout> <repository> <commit>
    git -C "$1" -c tar.tar.gz.command='gzip -cn' archive --format=tar.gz --prefix="$2-${3:0:12}/" "$3" | sha256sum | cut -d' ' -f1
}

# ------------------------------------------------------------ a producer checkout, two commits
SRC="${WORK}/src/mica-fixture"
mkdir -p "${SRC}/tools"
git -C "${SRC}" init -q
git -C "${SRC}" remote add origin https://example.invalid/testorg/mica-fixture.git
cp "${REPO}/tools/deps.sh" "${SRC}/tools/deps.sh"
printf 'first\n' >"${SRC}/content"
git -C "${SRC}" add -A
GIT_COMMITTER_DATE=2026-01-01T00:00:00Z git -C "${SRC}" -c user.name=t -c user.email=t@example.invalid commit -q -m one
FIRST="$(git -C "${SRC}" rev-parse HEAD)"
printf 'second\n' >"${SRC}/content"
printf 'a helper that only the later commit has\n' >"${SRC}/tools/later-helper"
git -C "${SRC}" add -A
GIT_COMMITTER_DATE=2026-02-01T00:00:00Z git -C "${SRC}" -c user.name=t -c user.email=t@example.invalid commit -q -m two
SECOND="$(git -C "${SRC}" rev-parse HEAD)"
OTHER="${WORK}/src/unrelated"
git -C "${WORK}/src" init -q unrelated
git -C "${OTHER}" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m unrelated
git -C "${SRC}" fetch -q "${OTHER}" HEAD 2>/dev/null
UNRELATED="$(git -C "${OTHER}" rev-parse HEAD)"

# ------------------------------------------------------------ HEAD
if bash "${SRC}/tools/deps.sh" publish-source >"${LOG}" 2>&1 \
    && says "${LOG}" "is published as ${REGISTRY}/testorg/mica-fixture:source.build-${SECOND:0:12}" \
    && [ "$(manifest mica-fixture "source.build-${SECOND:0:12}" "${WORK}/m2.json")" = 200 ] \
    && [ "$(jq -r '.annotations["org.opencontainers.image.revision"]' "${WORK}/m2.json")" = "${SECOND}" ] \
    && [ "$(jq -r '.layers[0].digest' "${WORK}/m2.json")" = "sha256:$(archive_sha "${SRC}" mica-fixture "${SECOND}")" ]; then
    pass "HEAD is published in the package named after the repository, tagged source.build-<commit12>"
else fail "HEAD publication"; fi
if bash "${SRC}/tools/deps.sh" publish-source >"${LOG}" 2>&1 && says "${LOG}" "comparing bytes"; then
    pass "publishing the same commit again compares bytes and writes nothing new"
else fail "republication of HEAD"; fi
if [ "$(manifest mica-source "mica-fixture.build-${SECOND:0:12}" /dev/null)" != 200 ]; then
    pass "nothing is written to the shared mica-source package"
else fail "shared package written"; fi

# ------------------------------------------------------------ an earlier commit
FIRST_SHA="$(archive_sha "${SRC}" mica-fixture "${FIRST}")"
if ! bash "${SRC}/tools/deps.sh" publish-source --revision "${FIRST}" --expect-sha256 "$(printf '1%.0s' $(seq 1 64))" >"${LOG}" 2>&1 \
    && says "${LOG}" "nothing was published" \
    && [ "$(manifest mica-fixture "source.build-${FIRST:0:12}" /dev/null)" = 404 ]; then
    pass "a digest other than the expected one refuses before anything is written"
else fail "expected-digest refusal"; fi
printf 'uncommitted edit\n' >>"${SRC}/content"
if bash "${SRC}/tools/deps.sh" publish-source --revision "${FIRST}" --expect-sha256 "${FIRST_SHA}" >"${LOG}" 2>&1 \
    && [ "$(manifest mica-fixture "source.build-${FIRST:0:12}" "${WORK}/m1.json")" = 200 ] \
    && [ "$(jq -r '.layers[0].digest' "${WORK}/m1.json")" = "sha256:${FIRST_SHA}" ] \
    && [ "$(jq -r '.annotations["org.opencontainers.image.revision"]' "${WORK}/m1.json")" = "${FIRST}" ] \
    && [ "$(jq -r '.annotations["org.opencontainers.image.created"]' "${WORK}/m1.json")" = "$(git -C "${SRC}" show -s --format=%cI "${FIRST}")" ]; then
    pass "--revision publishes the earlier commit at the expected digest with its own revision and date"
else fail "--revision publication"; fi
curl -sS -o "${WORK}/first.tar.gz" "http://${REGISTRY}/v2/testorg/mica-fixture/blobs/sha256:${FIRST_SHA}"
tar -tzf "${WORK}/first.tar.gz" | sed 's|^mica-fixture-[0-9a-f]*/||' | grep -v '^$' | grep -v '/$' | LC_ALL=C sort >"${WORK}/listed"
git -C "${SRC}" ls-tree -r --name-only "${FIRST}" | LC_ALL=C sort >"${WORK}/tree"
if cmp -s "${WORK}/listed" "${WORK}/tree" && ! grep -qx tools/later-helper "${WORK}/listed" \
    && [ "$(tar -xzOf "${WORK}/first.tar.gz" "mica-fixture-${FIRST:0:12}/content")" = first ]; then
    pass "the earlier commit's archive is that commit's tree: no later helper, no uncommitted edit"
else LOG="${WORK}/listed"; fail "archive isolation"; fi
git -C "${SRC}" checkout -q -- content
printf 'dirty\n' >>"${SRC}/content"
if ! bash "${SRC}/tools/deps.sh" publish-source >"${LOG}" 2>&1 && says "${LOG}" "uncommitted changes"; then
    pass "HEAD with uncommitted changes is refused"
else fail "dirty HEAD"; fi
git -C "${SRC}" checkout -q -- content
for bad in "${FIRST:0:12}" main "${UNRELATED}"; do
    if ! bash "${SRC}/tools/deps.sh" publish-source --revision "${bad}" --expect-sha256 "${FIRST_SHA}" >"${LOG}" 2>&1 \
        && { says "${LOG}" "full 40-hex commit id" || says "${LOG}" "not in the history of HEAD"; }; then
        pass "--revision ${bad:0:12} is refused: not a full id of this history"
    else fail "--revision ${bad:0:12} accepted"; fi
done
if ! bash "${SRC}/tools/deps.sh" publish-source --revision "${FIRST}" >"${LOG}" 2>&1 \
    && says "${LOG}" "expect-sha256 is required with --revision"; then
    pass "--revision without an expected digest is refused"
else fail "--revision without --expect-sha256 accepted"; fi
if ! OCI_TEST_TOKEN= MICA_REGISTRY=127.0.0.1:9/unreachable bash "${SRC}/tools/deps.sh" publish-source --revision "${FIRST}" --expect-sha256 "$(printf '2%.0s' $(seq 1 64))" >"${LOG}" 2>&1 \
    && says "${LOG}" "nothing was published" && ! says "${LOG}" "could not be reached"; then
    pass "a wrong expected digest is refused before any token or registry access"
else fail "digest refusal reached the registry or token"; fi

# ------------------------------------------------------------ a consumer
DEPS="${WORK}/consumer"
mkdir -p "${DEPS}/tools"
cp "${REPO}/tools/deps.sh" "${DEPS}/tools/deps.sh"
if (cd "${DEPS}" && bash tools/deps.sh bump mica-fixture --path vendor/fixture) >"${LOG}" 2>&1 \
    && [ "$(jq -r '.commit' "${DEPS}/deps/sources/mica-fixture.json")" = "${SECOND}" ]; then
    pass "bump pins the newest source artifact of the package by its created date"
else fail "bump newest"; fi
if (cd "${DEPS}" && bash tools/deps.sh bump mica-fixture --tag "build-${FIRST:0:12}") >"${LOG}" 2>&1 \
    && [ "$(jq -r '.sha256' "${DEPS}/deps/sources/mica-fixture.json")" = "${FIRST_SHA}" ] \
    && (cd "${DEPS}" && bash tools/deps.sh fetch) >"${LOG}" 2>&1 \
    && [ "$(cat "${DEPS}/vendor/fixture/content")" = first ] \
    && (cd "${DEPS}" && bash tools/deps.sh fetch --check) >"${LOG}" 2>&1 && says "${LOG}" "is published"; then
    pass "bump --tag, fetch and fetch --check read the earlier commit out of its own package"
else fail "consumer of the earlier commit"; fi

# ------------------------------------------------------------ this repository's pinned commit
# The assembly pins mica-boot e7022164 at the digest of the archive published
# before this change; republished here, it must be the same bytes.
PINNED=e7022164ed50b3bdefe0c368e7d9c47d2c264db8
PINNED_SHA=5ae0c45263cf228343272312571a3ad880a9d9be463d884da60829e5d14ec966
if git -C "${REPO}" cat-file -e "${PINNED}^{commit}" 2>/dev/null; then
    CLONE="${WORK}/src/mica-boot"
    git clone -q --no-hardlinks "${REPO}" "${CLONE}"
    cp "${REPO}/tools/deps.sh" "${CLONE}/tools/deps.sh"
    git -C "${CLONE}" -c user.name=t -c user.email=t@example.invalid commit -q -am "the publisher under test"
    if MICA_SOURCE_REPO=mica-boot bash "${CLONE}/tools/deps.sh" publish-source --revision "${PINNED}" --expect-sha256 "${PINNED_SHA}" >"${LOG}" 2>&1 \
        && [ "$(manifest mica-boot "source.build-${PINNED:0:12}" "${WORK}/pinned.json")" = 200 ] \
        && [ "$(jq -r '.layers[0].digest' "${WORK}/pinned.json")" = "sha256:${PINNED_SHA}" ]; then
        pass "mica-boot ${PINNED:0:12} republishes at the digest the assembly already pins"
    else fail "pinned mica-boot commit"; fi
    # The runkit content transition is its own commit, archived and labelled as
    # itself; the baseline keeps the startup inputs it was built with.
    RUNKIT="$(git -C "${REPO}" rev-parse --verify -q 5ac0371 || true)"
    if [ -n "${RUNKIT}" ]; then
        RUNKIT_SHA="$(archive_sha "${REPO}" mica-boot "${RUNKIT}")"
        curl -sS -o "${WORK}/pinned.tar.gz" "http://${REGISTRY}/v2/testorg/mica-boot/blobs/sha256:${PINNED_SHA}"
        if MICA_SOURCE_REPO=mica-boot bash "${CLONE}/tools/deps.sh" publish-source --revision "${RUNKIT}" --expect-sha256 "${RUNKIT_SHA}" >"${LOG}" 2>&1 \
            && [ "$(manifest mica-boot "source.build-${RUNKIT:0:12}" "${WORK}/runkit.json")" = 200 ] \
            && [ "$(jq -r '.annotations["org.opencontainers.image.revision"]' "${WORK}/runkit.json")" = "${RUNKIT}" ] \
            && [ "$(jq -r '.annotations["org.opencontainers.image.revision"]' "${WORK}/pinned.json")" = "${PINNED}" ] \
            && curl -sS -o "${WORK}/runkit.tar.gz" "http://${REGISTRY}/v2/testorg/mica-boot/blobs/sha256:${RUNKIT_SHA}" \
            && [ "$(tar -xzOf "${WORK}/runkit.tar.gz" "mica-boot-${RUNKIT:0:12}/initramfs.sh" | grep -c /input/mica-runkit)" -gt 0 ] \
            && [ "$(tar -xzOf "${WORK}/pinned.tar.gz" "mica-boot-${PINNED:0:12}/initramfs.sh" | grep -c /input/mica-init)" -gt 0 ] \
            && [ "$(tar -tzf "${WORK}/pinned.tar.gz" | grep -c tests/source-publish-test.sh)" = 0 ]; then
            pass "mica-boot ${RUNKIT:0:12} publishes as itself; ${PINNED:0:12} keeps its own tree and label"
        else fail "baseline and runkit transition kept apart"; fi
    fi
fi

echo "RESULT: ${PASS_N} passed, ${FAIL_N} failed"
[ "${FAIL_N}" = 0 ]
