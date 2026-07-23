# OCM UBI9 Migration

This document is the technical entry point for the OCM UBI9 migration. It
explains what changed, why each change exists, where the files are located,
how the implementation was tested, and which Sovereign Core release gates
remain outside the local environment.

## Current status

Local engineering validation is complete:

- five OCM runtime images build on Red Hat UBI9
- all images are `linux/amd64` and run as non-root UID `10001`
- six expected binaries pass runtime smoke tests
- both existing Helm charts lint, render, package, and deploy locally
- both OCM operators and their generated workloads become Ready
- the local managed cluster reaches `Joined=True` and `Available=True`
- Placement selects the managed cluster
- ManifestWork delivers a resource and reports `Applied=True` and
  `Available=True`

This does not represent final IBM/Sovereign Core release approval. IBM
pipeline, publication, security, signing, mirroring, and RKE2 acceptance gates
remain pending.

## Change map

### Upstream preservation

| File | Purpose |
| --- | --- |
| `Makefile.org` | Exact backup of the original upstream Makefile. |
| `build/Dockerfile.addon.org` | Exact backup of the upstream Add-on Dockerfile. |
| `build/Dockerfile.placement.org` | Exact backup of the upstream Placement Dockerfile. |
| `build/Dockerfile.registration.org` | Exact backup of the upstream Registration Dockerfile. |
| `build/Dockerfile.registration-operator.org` | Exact backup of the upstream operator Dockerfile. |
| `build/Dockerfile.work.org` | Exact backup of the upstream Work Dockerfile. |

The `.org` files allow the wrapper to preserve upstream logic and make future
release upgrades easier to compare or cherry-pick.

### UBI9 runtime Dockerfiles

| File | Image built | Expected binaries |
| --- | --- | --- |
| `build/Dockerfile.registration` | `registration` | `/registration`, `/server` |
| `build/Dockerfile.work` | `work` | `/work` |
| `build/Dockerfile.placement` | `placement` | `/placement` |
| `build/Dockerfile.registration-operator` | `registration-operator` | `/registration-operator` |
| `build/Dockerfile.addon` | `addon` | `/addon` |

All final runtime stages use:

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi:latest
```

The existing builder stages remain unchanged, as allowed by the migration
guidance. Runtime UID `10001`, binary paths, permissions, and Kubernetes
invocation behavior are preserved. The runtime stages do not install operating
system packages, so no `apt`, `apk`, `dnf`, or package-name translation was
required.

### Dockerfile naming convention

OCM produces several images from one repository. The upstream project already
uses the convention:

```text
build/Dockerfile.<component>
```

Examples are `Dockerfile.addon`, `Dockerfile.work`, and
`Dockerfile.registration`. These names already existed in the original
`Makefile.org` `build-image` declarations. This migration reuses the upstream
naming convention; it does not introduce or rename it.

### SPS-style wrapper Makefile

| File | Purpose |
| --- | --- |
| `Makefile` | New top-level Sovereign Core/SPS wrapper interface. |
| `Makefile.org` | Preserved upstream build implementation. |
| `pipeline/README.md` | Credential-free pipeline contract and external acceptance gates. |

The following targets are new wrapper targets. They are not original targets
copied from `Makefile.org`.

#### `make pre-build`

Fails early if required tools or backups are missing, a runtime Dockerfile is
not UBI9/non-root, or an existing Helm chart fails lint.

It does not compile binaries or build images.

#### `make docker-build`

Provides one SPS-facing command that builds all five existing OCM component
images for `linux/amd64`.

It reuses the same component-specific Dockerfile paths already declared by the
upstream project.

#### `make docker-test`

Validates the packaged images:

- operating system is Linux
- architecture is AMD64
- configured user is UID `10001`
- runtime reports UBI/RHEL major version 9
- expected binaries are executable
- binaries return safe, non-empty `--help` output

This is packaging/runtime validation. It does not replace upstream Go unit or
integration tests.

#### `make helm-package`

Lints and packages the two existing upstream charts at the required version
`0.3.0`.

It creates local `.tgz` artifacts only. OCI publication, signing, and mirroring
remain IBM pipeline responsibilities.

#### `make deploy`

Installs or upgrades the hub using the existing Cluster Manager Helm chart and
the local UBI9 image overrides.

This target deploys the Cluster Manager operator and `ClusterManager` resource.
The separate `make deploy-managed` target installs the Klusterlet
managed-cluster side.

### Automated verification

| File | Purpose |
| --- | --- |
| `hack/verify-ubi9-dockerfiles.sh` | Confirms all five final stages use UBI9 and UID `10001`. |
| `hack/verify-ubi9-images.sh` | Confirms image platform, user, UBI9 identity, binaries, and help startup. |

### Local Helm deployment

| File | Purpose |
| --- | --- |
| `deploy/local/README.md` | Complete Minikube, Helm, registration, and UI instructions. |
| `deploy/local/cluster-manager-ubi9-values.yaml` | Overrides hub/operator images with the local UBI9 builds. |
| `deploy/local/klusterlet-ubi9-values.yaml` | Overrides managed-cluster images with the local UBI9 builds. |
| `deploy/local/bootstrap-placeholder.kubeconfig` | Non-secret placeholder used only for Helm template validation. |

The existing charts are located at:

```text
deploy/cluster-manager/chart/cluster-manager
deploy/klusterlet/chart/klusterlet
```

The local values use `imagePullPolicy: Never` so Minikube runs the images
loaded from the local container engine.

### Functional tests

| File | Purpose |
| --- | --- |
| `deploy/local/tests/README.md` | Functional-test instructions and expected results. |
| `deploy/local/tests/placement.yaml` | Tests ManagedClusterSet binding and Placement selection. |
| `deploy/local/tests/manifestwork.yaml` | Tests hub-to-agent resource delivery and status feedback. |

Observed results:

```text
PlacementSatisfied=True
selectedCluster=ocm-ubi9-local
Applied=True
Available=True
ConfigMap value=OCM ManifestWork delivery succeeded
```

### Project documentation

| File | Audience and purpose |
| --- | --- |
| `docs/OCM-UBI9-Migration-Worklog.docx` | Detailed engineering worklog, decisions, evidence, and daily updates. |
| `docs/OCM-UBI9-Migration-Manager-Report.docx` | Manager-facing implementation and validation report. |
| `docs/OCM-UBI9-Manager-Walkthrough-Speaker-Guide.docx` | Section-by-section speaking guide and likely questions. |
| `docs/README-UBI9-MIGRATION.md` | Central technical map of all migration changes. |

## Reproduce the local validation

### Build and test

```bash
make pre-build
make docker-build IMAGE_REGISTRY=ocm-ubi9 IMAGE_TAG=phase1
make docker-test IMAGE_REGISTRY=ocm-ubi9 IMAGE_TAG=phase1
make helm-template
make helm-package HELM_CHART_VERSION=0.3.0
```

### Load and deploy

```bash
make local-load-images MINIKUBE_PROFILE=ocm-ubi9
make deploy KUBE_CONTEXT=ocm-ubi9
make deploy-managed \
  KUBE_CONTEXT=ocm-ubi9 \
  BOOTSTRAP_HUB_KUBECONFIG=<short-lived-bootstrap-kubeconfig>
```

Do not commit a real bootstrap kubeconfig. Keep short-lived credentials outside
the repository.

### Inspect status

```bash
make local-status KUBE_CONTEXT=ocm-ubi9
```

### Run functional tests

```bash
kubectl --context ocm-ubi9 apply -f deploy/local/tests/placement.yaml
kubectl --context ocm-ubi9 apply -f deploy/local/tests/manifestwork.yaml
```

## What is proven

- UBI9 runtime packaging works locally
- all five images build for `linux/amd64`
- all six expected binaries execute as non-root
- the existing Helm charts install both operators
- the operators create the expected OCM components
- the managed cluster registers successfully
- Placement produces a scheduling decision
- ManifestWork delivers resources and returns feedback

## What remains

- confirm the approved IBM production base image
- select the approved upstream release tag
- mirror the repository to IBM GitHub
- create the required `internal/<release-tag>` branch
- review the wrapper against the authoritative SPS contract
- publish images to the approved IBM Container Registry namespace
- run security scanning and GaraSign signing
- publish Helm charts as OCI artifacts
- apply MCSP `REPLACEMENTS`
- generate and validate the image-mirroring manifest with `oc-mirror`
- deliver charts through the Sovereign Core deployment monorepo
- deploy and validate on RKE2
- test required CLIs on the Linux AMD64 Landing Zone
- inventory current ACM use cases and map each to OCM or another OSS component

## Safe status statement

Core OCM functionality is working locally on the UBI9 AMD64 images. Final
Sovereign Core release readiness still depends on IBM repository, pipeline,
security, publication, signing, mirroring, deployment-monorepo, and RKE2
acceptance gates.
