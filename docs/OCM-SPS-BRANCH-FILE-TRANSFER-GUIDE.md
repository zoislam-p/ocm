# OCM SPS Branch File Transfer Guide

## Purpose

This guide explains how to copy the verified UBI9 and SPS build changes from the public reference branch into the IBM internal OCM feature branch.

| Item | Value |
|---|---|
| Reference repository | `https://github.com/zoislam-p/ocm.git` |
| Reference branch | `feature/ubi9-ocm-migration` |
| Reference commit reviewed | `17e1d022476801b8381deca6d8e1f33315888750` |
| Destination repository | `https://github.ibm.com/Sovereign-Core/ocm` |
| Destination branch | `feature/ubi9-ocm-migration` |
| Working directory | The root of the IBM OCM checkout—the directory containing `Makefile`, `build/`, and `hack/` |

> Before starting, commit or stash any destination-branch work. Do not copy `.git`, credentials, tokens, kubeconfig files, or the public repository's `.secrets.baseline`.

## Why the SPS build failed

The SPS log showed that it was building IBM repository commit `353a850f8d3e616ac6643978fadbe85514025c23`. At that commit SPS reported:

```text
Makefile doesn't contain target docker-build
No Makefile docker-build target found, building Dockerfile directly...
No Dockerfile found at /workspace/app/ocm/Dockerfile
```

This is expected fallback behavior:

1. SPS first searches the root `Makefile` for a `docker-build` target.
2. If the target is absent, SPS tries to build a single root-level `Dockerfile`.
3. OCM has five component Dockerfiles under `build/`; it intentionally has no root `Dockerfile`.
4. Therefore the IBM branch must contain the wrapper `Makefile` and its supporting files, and that branch must be pushed before SPS is rerun.

The screenshots also showed a local commit followed by a cancelled `git push`. A local commit is not visible to SPS until it exists on the IBM remote branch.

## Files required for the SPS image build

Copy these files as one coordinated change. Copying only the `Makefile` is incomplete because its targets call the verification scripts and build the five component Dockerfiles.

| File | Why SPS needs it |
|---|---|
| `Makefile` | Adds the SPS-facing `pre-build`, `docker-build`, and `docker-test` wrapper targets. |
| `Makefile.org` | Preserves the original upstream Makefile and lets wrapper targets delegate to upstream behavior. |
| `build/Dockerfile.registration` | Builds the UBI9 registration controller image. |
| `build/Dockerfile.work` | Builds the UBI9 work controller image. |
| `build/Dockerfile.placement` | Builds the UBI9 placement controller image. |
| `build/Dockerfile.registration-operator` | Builds the UBI9 registration operator image. |
| `build/Dockerfile.addon` | Builds the UBI9 addon manager image. |
| `build/Dockerfile.registration.org` | Backup of the original upstream registration Dockerfile. |
| `build/Dockerfile.work.org` | Backup of the original upstream work Dockerfile. |
| `build/Dockerfile.placement.org` | Backup of the original upstream placement Dockerfile. |
| `build/Dockerfile.registration-operator.org` | Backup of the original upstream operator Dockerfile. |
| `build/Dockerfile.addon.org` | Backup of the original upstream addon Dockerfile. |
| `hack/verify-ubi9-dockerfiles.sh` | Static checks used by `make pre-build`. |
| `hack/verify-ubi9-images.sh` | Runtime image checks used by `make docker-test`. |

Recommended supporting file:

| File | Purpose |
|---|---|
| `pipeline/README.md` | Documents the pipeline contract, inputs, evidence, and external SPS gates. It is not executable pipeline configuration. |

The Helm and local deployment files are not required to resolve this specific SPS Dockerfile error. Transfer them separately when the Helm/deployment phase is being integrated.

## Files not to copy

- `.git/` — repository metadata must remain tied to the IBM clone.
- `.secrets.baseline` — preserve the IBM repository's baseline; update it only through the approved IBM security workflow.
- Local kubeconfig files, registry credentials, tokens, or secret values.
- Manager reports, Word documents, or local test evidence unless the team explicitly wants them in the internal repository.
- A newly invented root `Dockerfile` as a workaround. OCM is a multi-image repository and the wrapper target should select the existing component Dockerfiles.

## Exact transfer commands

Run all commands from the root of the IBM OCM checkout.

### 1. Confirm the destination

```bash
pwd
git remote -v
git switch feature/ubi9-ocm-migration
git status --short
```

Confirm that `origin` points to `github.ibm.com/Sovereign-Core/ocm`. If `git status --short` shows unrelated changes, commit or stash them before continuing.

### 2. Add and fetch the public reference

Run this once:

```bash
git remote add ubi9-reference https://github.com/zoislam-p/ocm.git
git fetch ubi9-reference feature/ubi9-ocm-migration
```

If the remote already exists:

```bash
git remote set-url ubi9-reference https://github.com/zoislam-p/ocm.git
git fetch ubi9-reference feature/ubi9-ocm-migration
```

Confirm the fetched reference:

```bash
git rev-parse ubi9-reference/feature/ubi9-ocm-migration
```

Expected reference commit for this version of the guide:

```text
17e1d022476801b8381deca6d8e1f33315888750
```

If the reference branch has advanced, record the newer commit and review its diff before copying.

### 3. Copy the required files

```bash
git checkout ubi9-reference/feature/ubi9-ocm-migration -- \
  Makefile \
  Makefile.org \
  build/Dockerfile.registration \
  build/Dockerfile.registration.org \
  build/Dockerfile.work \
  build/Dockerfile.work.org \
  build/Dockerfile.placement \
  build/Dockerfile.placement.org \
  build/Dockerfile.registration-operator \
  build/Dockerfile.registration-operator.org \
  build/Dockerfile.addon \
  build/Dockerfile.addon.org \
  hack/verify-ubi9-dockerfiles.sh \
  hack/verify-ubi9-images.sh \
  pipeline/README.md
```

This copies file contents into the current IBM branch. It does not switch branches and does not replace the IBM repository history.

## Validate before committing

### Confirm the SPS target and required files

```bash
grep -n '^docker-build:' Makefile
test -f Makefile.org

for file in \
  build/Dockerfile.registration \
  build/Dockerfile.work \
  build/Dockerfile.placement \
  build/Dockerfile.registration-operator \
  build/Dockerfile.addon \
  hack/verify-ubi9-dockerfiles.sh \
  hack/verify-ubi9-images.sh
do
  test -f "$file" || { echo "Missing: $file"; exit 1; }
done
```

The `grep` command must return the root Makefile's `docker-build:` target.

### Run safe static checks

```bash
bash hack/verify-ubi9-dockerfiles.sh
make -n docker-build
git diff --check
git status --short
```

- `verify-ubi9-dockerfiles.sh` checks UBI9 runtime stages, the non-root user, and related Dockerfile requirements.
- `make -n docker-build` prints the five build commands without building.
- `git diff --check` detects whitespace errors.
- `git status --short` shows exactly what will be committed.

### Build and test when Docker or Podman is available

Docker:

```bash
make pre-build
make docker-build
make docker-test
```

Podman:

```bash
make pre-build CONTAINER_ENGINE=podman
make docker-build CONTAINER_ENGINE=podman
make docker-test CONTAINER_ENGINE=podman
```

`make pre-build` also requires Helm because it lints the existing upstream charts. The image tests verify UBI9 identity, `linux/amd64`, non-root UID `10001`, executable binaries, and safe `--help` startup.

## Commit and push to the IBM branch

Review the diff first:

```bash
git diff --stat
git diff -- Makefile build/ hack/ pipeline/README.md
```

Stage only the intended files:

```bash
git add \
  Makefile \
  Makefile.org \
  build/Dockerfile.registration \
  build/Dockerfile.registration.org \
  build/Dockerfile.work \
  build/Dockerfile.work.org \
  build/Dockerfile.placement \
  build/Dockerfile.placement.org \
  build/Dockerfile.registration-operator \
  build/Dockerfile.registration-operator.org \
  build/Dockerfile.addon \
  build/Dockerfile.addon.org \
  hack/verify-ubi9-dockerfiles.sh \
  hack/verify-ubi9-images.sh \
  pipeline/README.md

git commit -m "Add UBI9 SPS image build support"
git push -u origin feature/ubi9-ocm-migration
```

Do not press `Ctrl+C` while the push is running. Wait for Git to report success.

Confirm that the remote has the pushed commit:

```bash
git rev-parse HEAD
git ls-remote --heads origin feature/ubi9-ocm-migration
git status -sb
```

The local `HEAD` SHA and the SHA returned by `git ls-remote` must match.

## Confirm the next SPS run

At the beginning of the SPS log, verify:

1. Repository URL is `https://github.ibm.com/Sovereign-Core/ocm`.
2. Branch is `feature/ubi9-ocm-migration`.
3. Commit SHA matches `git rev-parse HEAD`.
4. SPS detects and calls `make docker-build`.
5. SPS does not fall back to `/workspace/app/ocm/Dockerfile`.

If SPS still says the target is missing, capture the new commit SHA and the target-detection log. Confirm from that exact commit:

```bash
git show <SPS_COMMIT_SHA>:Makefile | grep -n '^docker-build:'
```

If this prints the target, the remaining issue is the SPS target detector or pipeline configuration—not a missing file in Git.

## Important multi-image pipeline decision

OCM produces five images:

- registration
- work
- placement
- registration-operator
- addon

The supplied `docker-build` target builds all five. The sample SPS log, however, showed one pipeline image name: `ocm`. The SPS owners must confirm whether the pipeline supports multiple output images from one Makefile invocation or expects one component image per pipeline configuration.

Do not solve this by creating a generic root Dockerfile without agreeing on which component it represents. That could make the pipeline green while publishing the wrong artifact.

## Completion checklist

- [ ] Working in the IBM OCM checkout and correct feature branch.
- [ ] `origin` points to the IBM internal repository.
- [ ] Reference commit was recorded.
- [ ] Wrapper Makefile, original backups, five UBI9 Dockerfiles, and both verification scripts were copied.
- [ ] IBM `.secrets.baseline` was preserved.
- [ ] `grep -n '^docker-build:' Makefile` found the target.
- [ ] Static validation passed.
- [ ] Local image build and runtime tests passed, or limitations were documented.
- [ ] Commit was pushed successfully.
- [ ] Remote SHA matches local `HEAD`.
- [ ] SPS rerun used that same SHA.
- [ ] SPS image-output strategy for all five images was confirmed.

## Short handoff summary

The earlier SPS run used an IBM-repository commit that did not contain the `docker-build` wrapper. SPS therefore fell back to a nonexistent root Dockerfile. Copy the complete build set from `zoislam-p/ocm:feature/ubi9-ocm-migration`, validate it, push it to the IBM feature branch, and confirm that the next SPS log uses the new commit. The remaining pipeline-level question is how SPS will publish OCM's five distinct component images.
