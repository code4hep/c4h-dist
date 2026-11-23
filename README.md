# CODE4hep Distribution

This repository builds and distributes the Code4hep software stack: Spack, the
Spack environment `code4hep_env` with Code4hep and all its dependencies, and the
container images that contain them. The Spack packages themselves live in
[c4h-spack-packages](https://github.com/code4hep/c4h-spack-packages).

## Images and build cache

| Name | Content | Tags |
|---|---|---|
| `ghcr.io/code4hep/c4h-base` | AlmaLinux 9 with the system packages (`Dockerfile.base`) | `latest`, `sha-<commit>` |
| `ghcr.io/code4hep/c4h-full` | `c4h-base` plus Spack and `code4hep_env` installed in `/opt` (`Dockerfile.full`) | `latest`, `sha-<commit>`, `pkgs-<c4h-spack-packages commit>` |
| `oci://ghcr.io/code4hep/c4h-buildcache` | Spack binary build cache of all packages | |

`sha-` tags refer to the commit of this repository, `pkgs-` tags to the commit of
c4h-spack-packages the image was built from (set for builds triggered from there).

## Workflows

- **Base image** (`.github/workflows/base.yaml`): builds `c4h-base` when
  `Dockerfile.base` changes on `main` (or when started manually) and pushes it.
  Afterwards it starts the full-image workflow, because the system packages are
  externals of the Spack installation.
- **Full image** (`.github/workflows/full.yaml`): runs
  - when c4h-spack-packages is pushed to `main` (dispatched from there with the
    pushed commit as `packages_ref`),
  - when the files used for the full image change on `main`,
  - manually, with an optional `packages_ref` (branch, tag or commit).

  It has four jobs:
  1. `fill` installs the stack in the `c4h-base` container, building whatever is
     missing from the build cache, and pushes all packages to the cache.
  2. `image` builds `c4h-full`, which then only installs binaries from the cache,
     and pushes it under its `sha-` tag.
  3. `smoke-test` checks the run-time environment (`cmsRun`, Python
     configuration), creates a development area with `c4hinit`, checks that only
     Code4hep was rebuilt in it, and runs the Code4hep tests.
  4. `publish` moves `latest` (on `main`) and sets the `pkgs-` tag once the smoke
     test passed.

Pull requests build both images but push neither; pull requests from branches of
this repository do push binaries to the build cache.

### Why the build cache and the resumable fill exist

Building the full stack from source exceeds the 6 h GitHub job limit on a 4-core
runner. Binaries are therefore cached in an OCI build cache
(`oci://ghcr.io/code4hep/c4h-buildcache`). The `fill` job builds whatever is
missing for about 5 h 20 min, pushes all finished packages even when it runs out
of time, and re-dispatches the workflow (up to 6 attempts) until everything is
cached. The image build then only installs binaries from the cache. Both use
`scripts/install-stack.sh` with the same configuration, so the package hashes,
and therefore the cache hits, are identical.

## Policies

- **Target:** all packages are built for the portable `x86_64_v3` target (AVX2,
  no AVX-512), so the image and the binary cache work on any GitHub runner and
  most user machines. This is enforced with
  `packages: all: require: [target=x86_64_v3]`. A plain `target:` list is only a
  preference in Spack 1.0 and loses to reusing existing binaries. The image build
  checks that every Spack-built package has this target.
- **Versions:** HEP-specific versions are pinned in c4h-spack-packages; only the
  compiler and Python basics are pinned in `spack.yaml` here. The image contains
  the newest date version of Code4hep defined in c4h-spack-packages, so a Code4hep
  release is made by adding its version there. Spack itself (`v1.0.0`) and
  Spack's builtin package repository (a fixed commit) are pinned in
  `scripts/install-stack.sh`.
- **Configuration scope:** compilers, mirrors, repositories and the bootstrap
  location are written to Spack's *site* scope (`/opt/spack/etc/spack`), because
  GitHub container jobs override `HOME` and would not see the user scope.

## Using the release

```bash
podman run -it ghcr.io/code4hep/c4h-full:latest
c4henv            # sets up the run-time environment of code4hep_env
cmsRun --help
```

`c4henv` is defined in `/etc/profile.d/c4henv.sh` (login shells). It loads the
installed Code4hep and its dependencies with `spack load` and sources Stitched's
`stitched_env.sh`. Activating `code4hep_env` alone does not set up the run-time
environment.

## Developing Code4hep

`c4hinit` and `c4henv` are analogous to `cmsrel` and `cmsenv`:

```bash
c4hinit <area> [--source <path> | --ref <git-ref>] [--repo <url>] [-j N]
cd <area>
c4henv [--build-tree]
```

`c4hinit` creates the development area `<area>` as a Spack environment with the
same configuration and lock file as `code4hep_env`, clones Code4hep (`main`
unless `--ref` is given, or uses the sources given with `--source`), registers
it with `spack develop` under the release's Code4hep version, and installs it.
The release installation is used as a Spack upstream, so only Code4hep is
rebuilt in the area; everything else is reused. `<area>/build` links to the
CMake build tree.

Inside the area, `c4henv` sets up the environment for the Code4hep installed in
the area; `--build-tree` additionally puts the build tree first. After editing
the sources, rebuild incrementally with `spack -e <area> install`.

Nothing is written outside the area and `$HOME`, so this also works when the
release installation is read-only (e.g. on CVMFS). `$HOME/.spack` must be
writable (Spack's caches). Spack also writes to its bootstrap store, which the
image keeps in `/opt/spack-bootstrap`; with a read-only release, move it to a
writable location once (clingo is then downloaded again):

```bash
spack bootstrap root --scope user '~/.spack/bootstrap'
```

## One-time administrative setup

- Make the packages `c4h-base`, `c4h-full` and `c4h-buildcache` public in their
  package settings (this cannot be undone). Until then, the container jobs need
  the commented-out `credentials:` blocks in `full.yaml`, and users need to log in.
- Check that the organization allows public packages.
- Set up the token in c4h-spack-packages that dispatches the full-image workflow
  (see its README).

No secrets are needed in this repository: `GITHUB_TOKEN` covers ghcr and the
self-dispatch.

## Planned additions

- Nightly images (tag `nightly`) built from Code4hep `main`, separate from the
  release images, which keep building the newest date version.
- Starting the Code4hep CI after a new `c4h-full` image is published.
