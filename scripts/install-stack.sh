#!/bin/bash
# Installs Spack and the Code4hep software stack into /opt.
#
# Usage: install-stack.sh PHASE...
#   setup  clone Spack and the package repositories, write the site configuration,
#          bootstrap clingo and create the code4hep_env environment
#   build  install gcc@14 and the environment
#   check  fail if any Spack-built package has a target other than $C4H_TARGET
#   push   push all installed packages to the build cache (needs GHCR_USER/GHCR_TOKEN)
#   fill   build within $C4H_FILL_SECONDS, then push if GHCR_TOKEN is set; exits 0
#          when the build finished, 124 when it ran out of time, anything else on failure
#
# The same script is used by Dockerfile.full and by the cache-fill job, so both
# produce identical configurations and therefore identical package hashes.
#
# All configuration goes to Spack's site scope ($SPACK_ROOT/etc/spack), because
# GitHub container jobs override HOME, which hides the user scope.
set -euo pipefail

C4H_DIST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SPACK_ROOT=/opt/spack
SPACK_VERSION=v1.0.0
# Spack 1.0.0 clones the default branch (develop) of spack-packages regardless of
# the configured branch, so the builtin repository is pinned to a commit instead.
SPACK_PACKAGES_COMMIT=2c274bdba63d3c9c8ab4bd78e073f0b8c6e14539
C4H_SPACK_PACKAGES_REPO=${C4H_SPACK_PACKAGES_REPO:-https://github.com/code4hep/c4h-spack-packages.git}
C4H_SPACK_PACKAGES_REF=${C4H_SPACK_PACKAGES_REF:-main}
C4H_CACHE_URL=${C4H_CACHE_URL:-oci://ghcr.io/code4hep/c4h-buildcache}
C4H_TARGET=x86_64_v3
C4H_INSTALL_ARGS=${C4H_INSTALL_ARGS:---fail-fast --show-log-on-error -j$(nproc)}
C4H_FILL_SECONDS=${C4H_FILL_SECONDS:-19200}
spack=$SPACK_ROOT/bin/spack

setup() {
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$SPACK_VERSION" https://github.com/spack/spack.git "$SPACK_ROOT"

    git init -q /opt/spack-packages
    git -C /opt/spack-packages fetch -q --depth 1 https://github.com/spack/spack-packages.git "$SPACK_PACKAGES_COMMIT"
    git -C /opt/spack-packages checkout -q FETCH_HEAD
    $spack repo set --scope site --destination /opt/spack-packages builtin

    # clone + checkout works for branches, tags and commits
    git clone -q "$C4H_SPACK_PACKAGES_REPO" /opt/c4h-spack-packages
    git -C /opt/c4h-spack-packages checkout -q "$C4H_SPACK_PACKAGES_REF"

    $spack compiler find --scope site
    $spack mirror add --scope site --unsigned c4h "$C4H_CACHE_URL"
    $spack bootstrap root --scope site /opt/spack-bootstrap
    $spack bootstrap now

    $spack env create code4hep_env "$C4H_DIST_DIR/spack.yaml"
}

build() {
    # The target requirement also covers gcc's dependencies, which would
    # otherwise be built for the host's target.
    # shellcheck disable=SC2086
    $spack -c "packages:all:require:[target=$C4H_TARGET]" install $C4H_INSTALL_ARGS gcc@14 %gcc@11.5.0
    $spack -e code4hep_env concretize -f
    # shellcheck disable=SC2086
    $spack -e code4hep_env install $C4H_INSTALL_ARGS
}

check() {
    # Externals (prefix outside the install tree) carry the host target but are
    # not built by Spack.
    $spack find --format '{name} {arch.target} {prefix}' |
        awk -v root="$SPACK_ROOT/opt/" -v target="$C4H_TARGET" \
            'index($3, root) == 1 && $2 != target {print "wrong target: " $0; bad = 1} END {exit bad}'
}

push() {
    $spack mirror add --unsigned --oci-username-variable GHCR_USER \
        --oci-password-variable GHCR_TOKEN c4h-push "$C4H_CACHE_URL"
    # shellcheck disable=SC2046
    $spack buildcache push --unsigned --update-index c4h-push $($spack find --format '/{hash}')
}

fill() {
    local status=0
    timeout -s INT -k 300 "$C4H_FILL_SECONDS" "$0" build || status=$?
    [ -z "${GHCR_TOKEN:-}" ] || push
    return "$status"
}

for phase in "$@"; do
    "$phase"
done
