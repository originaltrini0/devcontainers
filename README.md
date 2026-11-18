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
  jq, ripgrep, Node.js LTS with npm/npx for Kilo Code MCP servers, git
  safe-directory helper), `k8s-tools` (kubectl, talosctl,
  flux, helm, kustomize, sops, age, cilium, yq, step-opt-in) and
   `terraform-tools` (terraform/tofu engine via a `flavor` selector plus
   tflint, terraform-docs, terraform-ls, trivy, pre-commit) and `cloud-tools`
   (gcloud, aws, az, pwsh) and `docker-tools` (pinned Docker CLI/compose/buildx
   on the host daemon, opt-in — see *Docker model*). Each stack feature
   is the sole owner of its CLI version pins — there is no baked image baseline
   to drift from. `flavor: "tofu"` must pin its own `version` — the default
   `version` is the Terraform pin and 404s against OpenTofu releases.
- **Projects own environment glue**: host mounts, `runArgs` (e.g. Ansible
  `--network=host`), VS Code extensions, `postCreateCommand`, secret-path
  mounts. Nothing project-specific is baked into an image or feature.
- **No compose, no manifest.** Project refs are validated against an
  allowlist by `scripts/validate-projects.sh` (Phase 4).

## Layout

```
images/{python,go}/          Dockerfiles (Phase 2/3)
src/{common,k8s-tools,terraform-tools,cloud-tools,docker-tools}/
                             devcontainer-feature.json + install.sh + lib.sh
test/<feature>/test.sh       feature version assertions
templates/{python,go,kubernetes,ansible,terraform,cloud,docker}/.devcontainer/
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

## Docker model (DooD, opt-in)

Projects that need `docker build` / `docker compose` (e.g. `finscribe`) opt in
with a single `docker-tools` feature line instead of per-project `runArgs`. The
model is **Docker-outside-of-Docker**: the feature declares its own
`/var/run/docker.sock -> /var/run/docker-host.sock` bind and a pinned
client/compose/buildx, and talks to the **host** daemon — sharing its image and
layer cache, no `--privileged`. DinD was rejected (privileged nested daemon, no
host cache, flaky under Docker Desktop); the upstream
`docker-outside-of-docker` feature was rejected because it defaults to
`latest` and breaks the exact-pin contract. Caveats: the forwarded socket is
**host-root-equivalent**, so the feature ships only on projects that ask for
it; builds resolve contexts on the host FS, so configs need a same-path
workspace bind (`source=${localWorkspaceFolder},target=${localWorkspaceFolder}`);
the socket must exist at container create time (Docker Desktop, Colima and
hosted runners provide it; Linux rootless Docker / Podman hosts remap the
source — see below). Access uses the container-local `docker` group GID
(or a socat-forwarded socket when the host socket is root-owned, as on Docker
Desktop) — the host socket inode is **never chmod'd**.

### Non-default host sockets

The feature's bind **target** `/var/run/docker-host.sock` is fixed: feature
manifests cannot interpolate options into `mounts` (only `${devcontainerId}`
is substituted), and the `socket_path` option only reaches `install.sh` as an
env var — it moves the entrypoint's expected socket path, **not** the bind.
Leave `socket_path` at its default. The CLI dedupes mounts by **target** with
`devcontainer.json` winning, so non-default hosts override the **source** with
a same-target mount:

```jsonc
// Linux, rootless Docker
"mounts": [
  { "source": "/run/user/${localEnv:UID}/docker.sock",
    "target": "/var/run/docker-host.sock", "type": "bind" }
]
```

Swap the `source` for other runtimes: Podman uses
`/run/user/${localEnv:UID}/podman/podman.sock`. On Docker Desktop and Colima
no override is needed: their daemons run in a VM and resolve bind sources
**there**, where `/var/run/docker.sock` already exists, so the feature's
default bind works unchanged.

Sharp edge: a user mount at a **different** target does not dedupe against the
feature's mount, so the feature's own `source=/var/run/docker.sock` bind stays
in the create request and hard-fails container creation on hosts without that
path. Always keep the target identical.

Experimental, not supported: the spec says feature `mounts` may reference only
`${devcontainerId}`, but CLI v0.90.0 in practice also substitutes
`${localEnv:...}` inside feature manifest mounts (verified via
`read-configuration --include-merged-configuration`). Do not rely on it; the
`devcontainer.json` same-target mount above is the supported override.

## Current pins

| Stack | Image / base | Features (defaults) |
|-------|--------------|---------------------|
| Python | `ghcr.io/originaltrini0/devcontainers/python:1.0.7` | `ghcr.io/originaltrini0/devcontainers/common:1.0.7` — gh 2.104.0, glab 1.130.0, node 26.13.1; image: uv 0.13.8, ruff 0.17.5, pytest 9.2.0 |
| Go | `ghcr.io/originaltrini0/devcontainers/go:1.0.7` | `ghcr.io/originaltrini0/devcontainers/common:1.0.7`; image: gopls v0.24.0, dlv v1.27.2, staticcheck v0.8.2, gofumpt v0.12.0, goimports v0.52.0, govulncheck v1.9.0, gotest v0.0.7, air v1.67.4, golangci-lint 2.15.0 |
| Kubernetes | `mcr.microsoft.com/devcontainers/base:ubuntu` | `ghcr.io/originaltrini0/devcontainers/common:1.0.7`, `ghcr.io/originaltrini0/devcontainers/k8s-tools:1.0.7` — kubectl 1.35.2, talosctl 1.13.2, flux 2.10.0, helm 3.22.1, kustomize 5.8.3, sops 3.13.3, age 1.3.2, cilium 0.20.3, yq v4.54.3, step `none` (opt-in) |
| Ansible | `ghcr.io/ansible/community-ansible-dev-tools:v26.4.4` | `ghcr.io/originaltrini0/devcontainers/common:1.0.7` |
| Terraform / OpenTofu | `mcr.microsoft.com/devcontainers/base:ubuntu` | `ghcr.io/originaltrini0/devcontainers/common:1.0.7`, `ghcr.io/originaltrini0/devcontainers/terraform-tools:1.0.7` — flavor `terraform` v1.17.2 (alt: `tofu` 1.13.9), tflint 0.66.0, terraform-docs 0.25.1, terraform-ls 0.39.1, trivy 0.76.2, pre-commit 4.7.0. |
| Cloud CLI | `mcr.microsoft.com/devcontainers/base:ubuntu` | `ghcr.io/originaltrini0/devcontainers/common:1.0.7`, `ghcr.io/originaltrini0/devcontainers/cloud-tools:1.0.7` — aws 2.40.3, az 2.92.0, pwsh 7.7.0, gcloud 593.0.0 (apt soft-match, manual pin — no releases feed). Composable with any stack; compose with `terraform-tools` for cloud infra roots. Mount cloud credentials read-only or use container-local config dirs — never a read-write host cloud config. |
| Docker (opt-in) | `mcr.microsoft.com/devcontainers/base:ubuntu` | `ghcr.io/originaltrini0/devcontainers/common:1.0.7`, `ghcr.io/originaltrini0/devcontainers/docker-tools:1.0.7` — docker 29.10.0 (static client, manual pin — tgz has no upstream checksum), compose 5.8.0, buildx 0.39.0. Self-mounts the host socket (DooD); see *Docker model*. Publishes with the next release tag. |

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

Every project in `~/code/projects` consumes the shared system at exact pins
(1.0.2 line for the pre-Terraform stacks, 1.0.7 for the Terraform/Cloud
stacks), with a committed `devcontainer-lock.json`. `k8s-tools` options
are the single override point for per-cluster CLI divergence.

| Project | Image / base | Feature ref / options |
|---------|--------------|-----------------------|
| `sglang-benchmarks` | `python:1.0.2` | `common:1.0.2` |
| `finplanner` | `go:1.0.7` | `common:1.0.7`, `docker-tools:1.0.7` (added ahead of its container work; same-path workspace bind). No local `.git` — configs cannot be committed in-repo until the project is initialized. |
| `k8s-prod` | `mcr.microsoft.com/devcontainers/base:ubuntu` | `common:1.0.2`, `k8s-tools:1.0.2` defaults (prod baseline) |
| `k8s-dev` | `mcr.microsoft.com/devcontainers/base:ubuntu` | `k8s-tools:1.0.2` + kubectl 1.36.5, talosctl 1.14.2, flux 2.9.6, helm 4.3.0, cilium 0.20.1, step 0.31.0 (mirrors `.tool-versions`) |
| `k8s-dev-old` (archived, runnable) | `mcr.microsoft.com/devcontainers/base:ubuntu` | `k8s-tools:1.0.2` + kubectl 1.36.0, talosctl 1.13.2, flux 2.8.7 (era pins from its own manifests) |
| `ansible-homelab-ops` | `ghcr.io/ansible/community-ansible-dev-tools:v26.4.4` | `common:1.0.2`; root + `--network=host` + `--hostname=ansible-dev-env`, `.vault_pass` mounted at `${containerWorkspaceFolder}` |
| `ansible-collection-homelab-{os,infra,security,apps}` (under `ansible-collections/`) | `ghcr.io/ansible/community-ansible-dev-tools:v26.4.4` | `common:1.0.2` (thin configs; vendored `.ansible/collections/**` untouched). `ansible-homelab-ops` mounts them at `/workspaces/ansible-collections/...`, matching its `requirements.yml` relative sources. |
| `terraform-modules/terraform-google-*`, `terraform-modules/terraform-proxmox-virtual_machine` | `mcr.microsoft.com/devcontainers/base:ubuntu` | `common:1.0.7`, `terraform-tools:1.0.7` (thin configs + `safe.directory`). `terraform-google-identity` has no local `.git` — archive-or-migrate decision pending, and gets no `postCreateCommand`. |
| `proxmox_vm_{graylog,postgresql,tailscale}_server`, `proxmox_vm_template` | `mcr.microsoft.com/devcontainers/base:ubuntu` | `common:1.0.7`, `terraform-tools:1.0.7`; bpg/proxmox credentials via `${localEnv:PM_API_URL,PM_API_TOKEN_ID,PM_API_TOKEN_SECRET}` — never baked. These roots commit `terraform.tfvars`/`tfstate` with live API tokens and `insecure = true`: rotate, gitignore, move state to a backend. |
| `google-cloud-foundations` | `mcr.microsoft.com/devcontainers/base:ubuntu` | `common:1.0.7`, `terraform-tools:1.0.7`, `cloud-tools:1.0.7` (az/pwsh `none`); `~/.config/gcloud` mounted **read-only** for ADC (gcloud logs a write warning — harmless). A real `init`/`plan` against the GCS backend needs the user's `gcloud` re-auth; `init -backend=false` + `validate` are credential-free. |
| `finscribe` | `go:1.0.7` | `common:1.0.7`, `docker-tools:1.0.7` + same-path workspace bind (DooD: `docker build`/`compose` run on the host daemon). |

Library repos are grouped under `~/code/projects/terraform-modules/` and
`~/code/projects/ansible-collections/`, mirroring the GitLab namespaces;
deployments stay flat. Terraform module sources are remote git refs, so the
grouping needed no consumer edits beyond the `ansible-homelab-ops`
mounts/`requirements.yml`.

Validation matrix (all green): pytest 13 passed (`sglang-benchmarks`), full
Go tool-version checks (`finplanner`), ansible/ansible-lint/molecule + vault
read/encrypt (`ansible-homelab-ops` and the four collections — re-verified
after the grouping move), per-cluster
CLI pins + readable `SOPS_AGE_KEY_FILE` + kube/talos mounts (`k8s-prod`,
`k8s-dev`, `k8s-dev-old`). Terraform sweep across the 16 module/root repos:
`fmt`/`init -backend=false`/`validate` 14/16, tflint recommended-preset and
trivy config clean or style-only findings, `tofu 1.13.9` smoke validate on a
proxmox root. DooD smoke (`finscribe`, macOS/Docker Desktop): pinned
client/compose/buildx present, `docker info` hits the host daemon,
`compose config` parses, multi-stage `docker build` + `compose up` serve
HTTP 200 in-container and host-side (`finplanner` pins + socket check green). Pre-existing repo issues found by the sweep (owner fixes, not
stack issues): fmt drift in `terraform-google-network/modules/vpc` and the
three `google-cloud-foundations` roots; `terraform-google-workload-identities`
declares the reserved name `variable "provider"` (init fails); docs output
drift where `.docs/.terraform-docs.yml` exists. `templates/cloud` pins
verified through the published 1.0.7 refs (aws 2.40.3, az 2.92.0, pwsh 7.7.0,
gcloud alpha 2026.11.06).

## Onboarding a new project

1. **Pick a stack** from the Current pins table — one row only. Go/Python use
   the published `ghcr.io/originaltrini0/devcontainers/{go,python}` images;
   Kubernetes on upstream `mcr.microsoft.com/devcontainers/base:ubuntu` +
   `common`/`k8s-tools`; Ansible on upstream
   `ghcr.io/ansible/community-ansible-dev-tools`. Never create a project
   Dockerfile or compose file for dev purposes.
2. **Copy the template** into the project and set `"name"` to the project
   name — not the stack name (gotten wrong in the `finscribe` migration):
   `cp -r templates/<stack>/.devcontainer/ <project>/.devcontainer/`
3. **Pin exact `X.Y.Z`** image and feature tags (Versioning and
   reproducibility); never `X`, `X.Y`, `latest`. Verify tags exist before
   committing:
   `docker manifest inspect ghcr.io/originaltrini0/devcontainers/<image>:<X.Y.Z>`
4. **Per-cluster Kubernetes CLI divergence** goes only in `k8s-tools`
   feature options — never a custom image or hand-pinned binaries.
5. **Project glue** lives in the project config: host mounts (kilo
   config/share dirs, `/run/host-services/ssh-auth.sock`, `~/.ssh`,
   `~/.config/gh`, `~/.config/glab-cli`), `remoteUser: vscode`,
   `containerEnv.SSH_AUTH_SOCK`, VS Code extensions/settings, and for
   host-mounted workspaces a `postCreateCommand` running
   `git config --global --add safe.directory /workspaces/<project>`
   (missed in `finscribe`). Every bind-mount source must already exist on
   the host, or Docker fails the container.
6. **Commit `devcontainer-lock.json`** alongside `devcontainer.json` (the
   Migrated-projects contract). `devcontainer` CLI v0.90.0 has no `lock`
   subcommand: the lockfile is generated on first `devcontainer up`,
   refreshed with `devcontainer upgrade`, or copied verbatim from a sibling
   project with identical feature refs (identical refs resolve identical
   digests).
7. **Validate from this repo**: `scripts/validate-projects.sh` (scans
   `~/code/projects` by default, asserts refs are on the allowlist and
   published; `--offline`/`--allow-missing` exist). It must report the
   project's refs — confirm the checked-ref count grew; a wrong `--dirs`
   root silently scans 0 refs.
8. **Update this README**: add the project's row to the Migrated projects
   table and record validation results in the matrix sentence below it.
9. **Commit `.devcontainer/` in the project repo**: projects live in
   separate repos, and CI here can only validate `templates/`.

## Maintenance

### Tool version bumps (everyday)

- Canonical pins live in `scripts/install-{common,go,python,k8s}-tools.sh`;
  each feature's option defaults in `src/<feature>/devcontainer-feature.json`
  mirror them. Renovate's regex manager updates both in one PR (the "tool
  pins" group, scheduled Mondays); `renovate.json` describes the mapping.
- Never hand-edit `src/<feature>/install.sh` or vendored `lib.sh` — they are
  vendored copies. Edit the canonical script under `scripts/`, then run
  `scripts/sync-features.sh` to re-vendor; CI `sync-features.sh --check`
  fails on drift.
- If Renovate misses a pin: edit the canonical script and feature-option
  default together in one PR, then `sync-features.sh`.
- Merging to `main` triggers CI (build + feature tests) but publishes
  nothing; a bump is usable by projects only after a release:
  `scripts/bump-version.sh X.Y.Z`, commit, tag `vX.Y.Z`, push tag (see
  Release checklist). Feature versions are immutable — a fix after publish
  requires the next version.

### System version

- `scripts/bump-version.sh X.Y.Z` rewrites every owned ref
  (`ghcr.io/originaltrini0/devcontainers/<feature|image>:X.Y.Z` — feature
  names are derived from `ls src`, so a new feature needs no edit here) in
  feature manifests, template refs and this README in one step; `--check` is
  the CI consistency gate. Tool pins are not touched — Renovate owns those.

### Base images

- Upstream base image tags (Ansible `community-ansible-dev-tools`,
  `mcr.microsoft.com/devcontainers/*`) are Renovate-managed via the
  devcontainer/dockerfile managers ("base images" group, no automerge);
  `ARG GO_VERSION`-style args in `images/{python,go}/Dockerfile` bump the
  same way.

### Refreshing projects after a release

- Our own `ghcr.io/originaltrini0/devcontainers/*` tags are excluded from
  Renovate everywhere; each project repo bumps its exact pins manually: edit
  `.devcontainer/devcontainer.json`, refresh `devcontainer-lock.json`
  (`devcontainer upgrade`, CLI v0.90.0), then run
  `scripts/validate-projects.sh` from this repo to confirm the new tags are
  published and allowlisted. Rollback is revert tag pin + lockfile.

### Health checks

- Scheduled `smoke.yml` re-pulls the exact published pins and asserts tool
  versions + multi-arch manifests (see Release and CI); run it manually
  (workflow_dispatch) after any release.
- `validate-projects.sh` (`--offline`/`--allow-missing`) is the local drift
  check across `~/code/projects`.

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
4. First release of a new package (`go`, `k8s-tools`, `terraform-tools`,
   `docker-tools`): toggle its GHCR package
   visibility to public in org settings — workflow-created packages default to
   private (`validate-projects.sh` reports `MISS` for a pinned tag until the
   toggle lands).
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
