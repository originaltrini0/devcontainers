# devcontainers

Versioned, publish-once devcontainer system for all `~/code/projects`: GHCR
images where prebuilding adds value, shared Features for everything else, thin
per-project configs. No compose file, no separate manifest, no per-project
Dockerfiles.

## Sharing contract

| Layer | Location | Owns |
|-------|----------|------|
| Images | `ghcr.io/originaltrini0/devcontainers/<image>:<X.Y.Z>` | OS/runtime plus stack tooling that benefits from prebuilding |
| Features | `ghcr.io/originaltrini0/devcontainers/<feature>:<X.Y.Z>` | Shared org tooling and per-project tool version overrides |
| Templates | `templates/<stack>/devcontainer.json` | Copyable thin configs |
| Projects | `<project>/.devcontainer/devcontainer.json` | Mounts, `runArgs`, extensions, `postCreateCommand` |

- **Images carry only prebuilt runtime/stack value.** Only `python` and `go`
  are published here. Kubernetes runs on the upstream
  `mcr.microsoft.com/devcontainers/base:ubuntu`; Ansible on the upstream
  `ghcr.io/ansible/community-ansible-dev-tools:v26.4.4`.
- **Features own shared tooling and version overrides.** `common` (gh, glab,
  jq, ripgrep, git safe-directory helper) and `k8s-tools` (kubectl, talosctl,
  flux, helm, kustomize, sops, age, cilium, yq, step-opt-in). `k8s-tools` is
  the sole owner of Kubernetes CLI version pins — there is no baked image
  baseline to drift from.
- **Projects own environment glue**: host mounts, `runArgs` (e.g. Ansible
  `--network=host`), VS Code extensions, `postCreateCommand`, secret-path
  mounts. Nothing project-specific is baked into an image or feature.
- **No compose, no manifest.** Project refs are validated against an
  allowlist by `scripts/validate-projects.sh` (Phase 4).

## Layout

```
images/{python,go}/          Dockerfiles (Phase 2/3)
src/{common,k8s-tools}/      devcontainer-feature.json + install.sh + lib.sh
test/<feature>/test.sh       feature version assertions
templates/{python,go,kubernetes,ansible}/.devcontainer/
scripts/                     canonical installers, lib.sh, sync/check tooling
```

`src/` + `test/` at the repo root is the layout `devcontainer features test`
and `publish` require (CLI v0.90.0 rejects a `features/<feature>/{src,test}`
nesting).

Feature packaging constraint: the Dev Container CLI packages only a feature's
`src/` directory, so `install.sh` can never source `../../scripts/`. The
canonical installers live in `scripts/`, and `scripts/sync-features.sh` vendors
`lib.sh` and the feature's installer (as `install.sh`) into each `src/<feature>/`.
CI runs `sync-features.sh --check` and fails on drift — never hand-edit a
vendored file.

Image builds must use the **repo root** as build context
(`docker buildx build -f images/python/Dockerfile .`) so `COPY scripts/` resolves.

## Versioning and reproducibility

- Git tag `vX.Y.Z` publishes image tags `X.Y.Z`, `X.Y`, `X`, `latest` and
  feature version `X.Y.Z`.
- Project configs pin **exact `X.Y.Z`** image and feature tags. `X`, `X.Y`,
  `latest` are convenience aliases only.
- Commit the generated `devcontainer-lock.json` per project. Rollback is
  reverting the exact tag plus the lockfile.
- `scripts/bump-version.sh` (Phase 4) updates image tags, feature versions and
  this README together.

## Current pins

| Stack | Image / base | Features (defaults) |
|-------|--------------|---------------------|
| Python | `ghcr.io/originaltrini0/devcontainers/python:1.0.2` | `common:1.0.2` — gh 2.104.0, glab 1.130.0; image: uv 0.13.8, ruff 0.17.5, pytest 9.2.0 |
| Go | `ghcr.io/originaltrini0/devcontainers/go:1.0.2` | `common:1.0.2`; image: gopls v0.24.0, dlv v1.27.2, staticcheck v0.8.2, gofumpt v0.12.0, goimports v0.52.0, govulncheck v1.9.0, gotest v0.0.7, air v1.67.4, golangci-lint 2.15.0 |
| Kubernetes | `mcr.microsoft.com/devcontainers/base:ubuntu` | `common:1.0.2`, `k8s-tools:1.0.2` — kubectl 1.35.2, talosctl 1.13.2, flux 2.10.0, helm 3.22.1, kustomize 5.8.3, sops 3.13.3, age 1.3.2, cilium 0.20.3, yq v4.54.3, step `none` (opt-in) |
| Ansible | `ghcr.io/ansible/community-ansible-dev-tools:v26.4.4` | `common:1.0.2` |

`1.0.1`/`1.0.2` changed no Dockerfiles: the images are content-identical to
the multi-arch `v1.0.0` CI release (the `1.0.2` tags alias its manifest
digests until the next tag rebuilds them), while the features carry real
fixes — `1.0.1` dispatches package installs across apt/dnf/apk bases and
`1.0.2` makes feature options actually apply (the devcontainer CLI exports
them as uppercase env vars, not `$OPTIONS`). Image sizes recorded at build:
Python 2277 MB (`linux/arm64`, Python 3.13.5), Go 4214 MB (`linux/arm64`,
Go 1.27.4). Kubernetes has no custom image and Ansible uses the upstream
`ghcr.io/ansible/community-ansible-dev-tools:v26.4.4` (tag verified pullable),
which already ships ansible-core, ansible-lint and molecule.

## Migrated projects

Every project in `~/code/projects` consumes the shared system at the exact
`1.0.2` pins, with a committed `devcontainer-lock.json`. `k8s-tools` options
are the single override point for per-cluster CLI divergence.

| Project | Image / base | Feature ref / options |
|---------|--------------|-----------------------|
| `sglang-benchmarks` | `python:1.0.2` | `common:1.0.2` |
| `finplanner` | `go:1.0.2` | `common:1.0.2` |
| `k8s-prod` | `mcr.microsoft.com/devcontainers/base:ubuntu` | `common:1.0.2`, `k8s-tools:1.0.2` defaults (prod baseline) |
| `k8s-dev` | `mcr.microsoft.com/devcontainers/base:ubuntu` | `k8s-tools:1.0.2` + kubectl 1.36.5, talosctl 1.14.2, flux 2.9.6, helm 4.3.0, cilium 0.20.1, step 0.31.0 (mirrors `.tool-versions`) |
| `k8s-dev-old` (archived, runnable) | `mcr.microsoft.com/devcontainers/base:ubuntu` | `k8s-tools:1.0.2` + kubectl 1.36.0, talosctl 1.13.2, flux 2.8.7 (era pins from its own manifests) |
| `ansible-homelab-ops` | `ghcr.io/ansible/community-ansible-dev-tools:v26.4.4` | `common:1.0.2`; root + `--network=host` + `--hostname=ansible-dev-env`, `.vault_pass` mounted at `${containerWorkspaceFolder}` |
| `ansible-collection-homelab-{os,infra,security,apps}` | `ghcr.io/ansible/community-ansible-dev-tools:v26.4.4` | `common:1.0.2` (thin configs; vendored `.ansible/collections/**` untouched) |

Validation matrix (all green): pytest 13 passed (`sglang-benchmarks`), full
Go tool-version checks (`finplanner`), ansible/ansible-lint/molecule + vault
read/encrypt (`ansible-homelab-ops` and the four collections), per-cluster
CLI pins + readable `SOPS_AGE_KEY_FILE` + kube/talos mounts (`k8s-prod`,
`k8s-dev`, `k8s-dev-old`).

## Registry and visibility

- Registry: GHCR under `originaltrini0`, repository path
  `originaltrini0/devcontainers`. GitLab remains the project remotes; GitHub
  hosts only this devcontainer repo.
- Repo visibility: **private** (chosen) — internal tooling, no reason to
  publish the configs.
- GHCR package visibility: **public** (chosen) — images and features contain no
  secrets, and public packages pull on any machine without `docker login`.
- Publishing uses `GITHUB_TOKEN` in CI (`packages: write`); no long-lived PAT.
  Local publishing needs a **classic PAT with `write:packages`** (+ `repo`, the
  package links to the private repo): the `packages` scope cannot be added to
  the gh CLI token (`gh auth refresh -s packages` fails `invalid_scope`). Use it
  directly with `docker login ghcr.io -u gerard-samuel --password-stdin`; image
  pushes and `devcontainer features publish` both use Docker's stored
  credentials. `originaltrini0` is an organization owned by `gerard-samuel`.

## Release checklist

1. Land changes on `main` (CI builds and tests every image/feature).
2. `scripts/bump-version.sh X.Y.Z`, commit, tag `vX.Y.Z`, push tag.
3. Release workflow pushes one multi-arch build per image as manifest lists
   (`X.Y.Z` / `X` / `X.Y` / `latest`) via the shared BuildKit worker and
   publishes the feature collection (`devcontainer features publish src`);
   never re-issue an already-published feature version.
4. First release of a new package (`go`, `k8s-tools`): toggle its GHCR package
   visibility to public in org settings — workflow-created packages default to
   private.
5. Projects bump exact pins via Renovate; commit refreshed lockfiles.
6. Rollback: revert the exact tag + lockfile, redeploy the container.

## Release and CI

- **CI on PRs and pushes to `main`** (`.github/workflows/ci.yml`):
  `scripts/sync-features.sh --check` gates feature src/ drift and
  `scripts/bump-version.sh --check` gates version consistency. Image builds
  (`python`, `go`) run on ARC self-hosted runners (`github-runner-scale-set`)
  against the shared remote BuildKit worker `buildkitd-github`
  (`.github/actions/buildkit-builder`) — those pods have no Docker daemon, so
  CI builds emit `type=cacheonly` and the Dockerfiles' RUN version checks are
  the gate; arm64 is emulated inside BuildKit. Feature tests and template
  devcontainer builds stay on GitHub-hosted runners because the devcontainer
  CLI needs a Docker daemon. Template refs are allowlist-checked with
  `validate-projects.sh --dirs "$PWD/templates" --allow-missing`.
- **Tool-pin ownership**: Renovate bumps the canonical pins in
  `scripts/install-*.sh` and the mirrored feature-option defaults in
  `src/*/devcontainer-feature.json` in one PR — keep both in sync in the same
  PR (`renovate.json`). Our own `ghcr.io/originaltrini0/devcontainers/*`
  image/feature tags are excluded from Renovate and move only via
  `bump-version.sh`.
- **Smoke** (`.github/workflows/smoke.yml`, scheduled + manual): re-pulls the
  exact pinned published tags, asserts the canonical tool versions and the
  multi-arch manifest. It fails by design until the first multi-arch release
  replaces the current arm64-only `python:1.0.0`.
- **Required checks**: the job set is `sync-features`,
  `version-consistency`, `validate-refs`, `images (*)`, `features (*)`,
  `templates (*)`. GitHub refuses branch protection on free-plan private
  repositories (403), so treat these as review gates until the org upgrades
  or the repo goes public; the protection payload (matrix-leg contexts) is
  one `gh api PUT branches/main/protection` call away.
- `validate-projects.sh` also scans `~/code/projects` locally; projects live
  in separate repos, so CI validates `templates/` only.
