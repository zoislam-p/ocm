# OCM on Rancher/RKE2 — Installation and Validation Runbook

## How to use this document

This runbook explains what is being installed, why each stage is required,
what results to expect, and how to investigate failures.

It intentionally does not contain executable commands. Use
`docs/OCM-Rancher-CLI-Quickstart.md` as the single command source. Every stage
below identifies the corresponding CLI Quick Start step.

## 1. Objective

Install the UBI9-based Open Cluster Management (OCM) images from this
repository onto Kubernetes clusters managed by Rancher:

- one Rancher/RKE2 cluster acts as the OCM hub;
- one Rancher/RKE2 cluster acts as the managed cluster; and
- OCM registration, Placement, and ManifestWork delivery are validated.

For a quick smoke test, one cluster can act as both the hub and managed
cluster. For meaningful validation, use two clusters so that network
connectivity and hub/managed separation are exercised.

Rancher is the cluster-management interface. OCM is installed inside the
selected downstream Kubernetes clusters with Helm.

## 2. Branch and repository basis

This guide is based on `feature/ubi9-ocm-migration`, not clean `main`.

The feature branch contains:

- UBI9 runtime Dockerfiles;
- the wrapper Makefile;
- image validation scripts;
- the existing upstream Cluster Manager and Klusterlet Helm charts;
- local functional-test manifests; and
- Rancher installation documentation.

The branch started from `main` commit
`0ab9a37d104b61bee41373c1d669280f56c2414b`.

Run all CLI Quick Start commands from the repository root, which is the
directory containing `Makefile`, `build/`, `deploy/`, and `docs/`.

## 3. Files involved

### Files already changed

These files are already complete and should not be edited during installation:

| Files | Purpose |
|---|---|
| `build/Dockerfile.registration` | UBI9 runtime for Registration |
| `build/Dockerfile.work` | UBI9 runtime for Work |
| `build/Dockerfile.placement` | UBI9 runtime for Placement |
| `build/Dockerfile.registration-operator` | UBI9 runtime for the operator |
| `build/Dockerfile.addon` | UBI9 runtime for Add-on Manager |
| `build/Dockerfile.*.org` | Backups of the upstream Dockerfiles |
| `Makefile` | Wrapper build, test, package, and deploy interface |
| `Makefile.org` | Backup of the upstream Makefile |
| `hack/verify-ubi9-dockerfiles.sh` | Static Dockerfile validation |
| `hack/verify-ubi9-images.sh` | Built-image validation |
| `deploy/local/tests/placement.yaml` | Placement functional test |
| `deploy/local/tests/manifestwork.yaml` | ManifestWork functional test |

### Existing Helm charts

The installation reuses the upstream charts at:

- `deploy/cluster-manager/chart/cluster-manager`
- `deploy/klusterlet/chart/klusterlet`

No replacement chart or Rancher-specific operator is required.

### Minikube-only values

The following files must not be passed directly to Rancher:

- `deploy/local/cluster-manager-ubi9-values.yaml`
- `deploy/local/klusterlet-ubi9-values.yaml`

They reference workstation-local images and use `imagePullPolicy: Never`.
Rancher/RKE2 nodes instead need registry-based image names and normally use
`imagePullPolicy: IfNotPresent`.

For the first Rancher installation, the CLI Quick Start supplies the
environment-specific values directly to Helm. No new committed values file is
required.

## 4. Architecture

### Hub cluster

The hub stores the desired multicluster state and runs:

- Cluster Manager operator;
- Registration controller and webhook;
- Work controller and webhook;
- Placement controller; and
- Add-on Manager controller and webhook.

### Managed cluster

The managed cluster runs:

- Klusterlet operator;
- Registration agent; and
- Work agent.

### Installation flow

1. Helm installs the CRDs, operator Deployment, and initial custom resource.
2. The operator watches the custom resource.
3. The operator creates and maintains the OCM application workloads.
4. The managed agents request registration with the hub.
5. The hub administrator accepts the managed cluster.
6. OCM can then select the cluster and deliver Kubernetes resources to it.

A CRD defines an OCM Kubernetes API type. A custom resource requests an
instance of that type. A custom resource is not a container and does not have
its own image.

## 5. Information required before installation

Confirm:

| Item | Required value |
|---|---|
| Rancher version | Current platform version |
| Kubernetes distribution and version | Expected to be RKE2 |
| Hub cluster/context | Rancher kubeconfig context |
| Managed cluster/context | Rancher kubeconfig context |
| Managed-cluster OCM name | Unique registration name |
| Architecture | AMD64 |
| Image registry | Registry/project reachable by RKE2 nodes |
| Image tag | Test or approved release tag |
| Hub API endpoint | Direct endpoint reachable from managed-cluster pods |
| Registry authentication | Existing secret or Docker login |
| Network requirements | Registry, hub API, DNS, proxy, and firewall rules |
| Topology | Same-cluster smoke test or two-cluster validation |

Do not install OCM on the Rancher management cluster unless the platform owner
explicitly approves third-party CRDs and cluster-wide RBAC there. A downstream
RKE2 cluster is the safer hub default.

## 6. Access and prerequisites

Required access:

- Rancher access to both selected clusters;
- cluster-admin permission on both clusters;
- permission to push the five images;
- registry pull access from every RKE2 node; and
- managed-cluster pod connectivity to the direct hub API endpoint.

Required workstation tools:

- Docker or Podman;
- kubectl;
- Helm 3; and
- Git.

Rancher's browser Kubectl Shell is useful for inspection, but the repository,
container engine, and Helm workflow are easier to run from a configured
workstation.

## 7. Installation and validation stages

### Stage 1 — Configure deployment values

Define the hub context, managed context, managed-cluster name, registry, image
tag, hub API endpoint, and temporary credential paths.

**Why:** These values identify exactly which clusters and images the
installation will use.

**Commands:** CLI Quick Start, Step 1.

### Stage 2 — Verify the Rancher clusters

Confirm that both kubeconfig contexts point to the intended clusters, both
clusters are healthy, cluster-admin is available, and nodes report AMD64.

**Why:** OCM installs cluster-wide resources and the current images target
Linux AMD64.

**Pass condition:** Both authorization checks return `yes`, nodes are Ready,
and architecture is `amd64`.

**Commands:** CLI Quick Start, Step 2.

### Stage 3 — Build and test the UBI9 images

Build Registration, Work, Placement, Registration Operator, and Add-on images.
Validate UBI9 identity, AMD64 architecture, non-root UID 10001, expected
binaries, and safe startup behavior.

**Why:** Installation should not begin until all runtime artifacts are proven.

**Pass condition:** All five image builds and image checks pass.

**Commands:** CLI Quick Start, Step 3.

### Stage 4 — Publish images

Push all five images to a registry reachable by both clusters.

**Why:** Rancher/RKE2 nodes cannot see images stored only in the workstation's
local Docker engine.

**Pass condition:** All five tags are visible in the shared registry.

**Commands:** CLI Quick Start, Step 4.

### Stage 5 — Configure registry credentials

If the registry is private, create the expected image pull secret on both
clusters.

**Why:** Operators and generated application workloads must authenticate when
pulling the UBI9 images.

**Pass condition:** The pull secret exists in the OCM release namespace on
both clusters.

**Commands:** CLI Quick Start, Step 5.

### Stage 6 — Validate Helm packaging

Lint and package the existing Cluster Manager and Klusterlet charts.

**Why:** This catches chart structure and rendering errors before resources are
submitted to Rancher/RKE2.

**Pass condition:** Both charts lint successfully and package without errors.

**Commands:** CLI Quick Start, Step 6.

### Stage 7 — Install the OCM hub

Install the Cluster Manager chart on the hub context.

Helm creates:

- OCM CRDs;
- Cluster Manager operator;
- required service accounts and RBAC;
- `ClusterManager` custom resource; and
- optional short-lived bootstrap service account.

The operator then creates Registration, Work, Placement, and Add-on workloads.

**Pass condition:** The Helm release is deployed, the operator is Ready, the
`ClusterManager` reports success, and all hub application workloads are Ready.

**Commands:** CLI Quick Start, Step 7.

Do not use `make deploy` for Rancher. That wrapper currently selects the
Minikube-only values file.

### Stage 8 — Create bootstrap access

Create a short-lived kubeconfig that uses a direct hub API endpoint and the
hub's CA.

**Why:** The managed Registration agent needs temporary permission to create
its certificate-signing request and ManagedCluster registration.

For separate clusters, the endpoint must be reachable from managed-cluster
pods. The in-cluster address `kubernetes.default.svc` is valid only for a
same-cluster smoke test.

**Pass condition:** The bootstrap identity can create certificate-signing
requests.

**Commands:** CLI Quick Start, Step 8.

### Stage 9 — Install the managed Klusterlet

Install the Klusterlet chart on the managed context using the temporary hub
bootstrap kubeconfig.

Helm creates:

- Klusterlet CRD;
- Klusterlet operator;
- required service accounts and RBAC;
- bootstrap kubeconfig secret; and
- `Klusterlet` custom resource.

The operator then creates Registration and Work agents.

**Pass condition:** The Helm release is deployed, the Klusterlet operator is
Ready, and both managed agents are running.

**Commands:** CLI Quick Start, Step 9.

### Stage 10 — Accept the managed cluster

Accept only the expected `ManagedCluster` object on the hub.

**Why:** OCM uses double opt-in registration. The managed side requests access,
and the hub administrator explicitly approves management.

**Pass condition:** The managed cluster reports `Joined=True` and
`Available=True`.

**Commands:** CLI Quick Start, Step 10.

### Stage 11 — Test Placement

Label the managed cluster, assign it to a cluster set, and apply the Placement
test.

**Why:** Ready pods prove installation. Placement proves the hub can evaluate
cluster eligibility and publish a scheduling decision.

**Pass condition:** `PlacementDecision` selects the expected Rancher managed
cluster.

**Commands:** CLI Quick Start, Step 11.

### Stage 12 — Test ManifestWork

Create a ManifestWork on the hub that requests a namespace and ConfigMap on the
managed cluster.

**Why:** This validates the complete work-delivery and feedback path.

**Pass condition:** ManifestWork reports `Applied=True` and `Available=True`,
and the expected ConfigMap exists on the managed cluster.

**Commands:** CLI Quick Start, Step 12.

### Stage 13 — Capture evidence

Record Helm releases, custom-resource status, pod health, Placement decisions,
ManifestWork feedback, image information, versions, timestamps, and blockers.

**Why:** This separates observed evidence from assumptions and supports the
manager report and release review.

**Commands:** CLI Quick Start, Step 13.

### Stage 14 — Remove temporary credentials

Delete the temporary bootstrap kubeconfig and CA file and clear the token
variable.

**Why:** Bootstrap access is short-lived setup material and should not remain
on the workstation or enter source control.

**Commands:** CLI Quick Start, Step 14.

## 8. Rancher UI inspection

For each downstream cluster, use Rancher's **Explore** view.

Inspect:

- **Workloads:** operator, controller, webhook, and agent Deployments/Pods;
- **Namespaces:** OCM operator, hub, agent, test, and managed-cluster
  namespaces;
- **Custom Resources:** ClusterManager, Klusterlet, ManagedCluster, Placement,
  PlacementDecision, ManifestWork, and AppliedManifestWork;
- **Events:** image pulls, admission failures, RBAC errors, and scheduling;
- **Logs:** operator reconciliation, registration, and work delivery.

Rancher's cluster dashboard is an infrastructure UI. OCM core does not include
the Red Hat ACM product console.

## 9. Troubleshooting guide

### ImagePullBackOff

Check:

- exact registry path and tag;
- registry DNS and TLS trust;
- pull-secret name and namespace;
- node egress to the registry;
- AMD64 image availability; and
- pod event messages.

Related commands: CLI Quick Start, Steps 4 and 5, plus the evidence commands in
Step 13.

### Operator is Ready but application workloads are missing

Check:

- ClusterManager or Klusterlet conditions;
- operator logs;
- cluster events;
- image pull specifications;
- admission-policy rejections; and
- service-account permissions.

Related commands: CLI Quick Start, Steps 7, 9, and 13.

### Managed cluster never joins

Check:

- direct reachability to the hub API;
- hub CA correctness;
- bootstrap-token expiration;
- proxy and `NO_PROXY` configuration;
- DNS;
- pending certificate-signing requests;
- Registration agent logs; and
- whether hub acceptance was completed.

Related commands: CLI Quick Start, Steps 8 through 10.

### CRDs or RBAC are rejected

Confirm that:

- the Rancher user has cluster-admin;
- organizational policy permits OCM CRDs;
- ClusterRoles and ClusterRoleBindings are allowed;
- admission webhooks are permitted; and
- required namespaces can be created.

Related commands: CLI Quick Start, Step 2 and the inspection commands in Steps
7 and 9.

### Pod Security or admission-policy rejection

Capture the exact policy name and event message before changing security
settings. The UBI9 images are configured to run as non-root UID 10001.

Related commands: CLI Quick Start, Step 13.

## 10. Rollback

Rollback order:

1. Delete temporary functional-test resources.
2. Uninstall the Klusterlet Helm release from the managed cluster.
3. Delete the expected ManagedCluster registration from the hub.
4. Uninstall the Cluster Manager Helm release from the hub.
5. Remove temporary bootstrap credentials.

Do not delete OCM CRDs until all OCM custom resources are removed and the
platform owner confirms no other installation uses them. Deleting a CRD also
deletes stored custom resources of that type.

Rollback commands are maintained in the CLI Quick Start under **Rollback —
only when removal is authorized**. Review the sequence against platform policy
before execution.

## 11. Installation completion criteria

The installation and validation are successful when:

1. the topology and target clusters are agreed;
2. both kubeconfig contexts and cluster-admin access work;
3. the shared registry and direct hub API endpoint are confirmed;
4. the five UBI9 images are available to RKE2 nodes;
5. the hub operator and OCM application controllers are Ready;
6. the Klusterlet and managed agents are Ready;
7. the managed cluster reports `Joined=True` and `Available=True`;
8. Placement selects the managed cluster;
9. ManifestWork delivers a resource and reports feedback;
10. evidence is saved; and
11. remaining blockers are documented.

## 12. What this proves

Successful completion proves:

- the UBI9 images run on the selected Rancher/RKE2 environment;
- the existing Helm/operator installation model works;
- managed-cluster registration succeeds;
- Placement selects a qualifying cluster; and
- ManifestWork delivers resources and returns feedback.

It does not yet prove:

- production-scale or high-availability behavior;
- upgrade and disaster-recovery behavior;
- every ACM capability;
- IBM SPS/ICR publication and signing;
- approved production-base lineage;
- security-scan acceptance; or
- Sovereign Core production approval.

## 13. Official references

- Rancher cluster registration:
  <https://ranchermanager.docs.rancher.com/v2.12/how-to-guides/new-user-guides/kubernetes-clusters-in-rancher-setup/register-existing-clusters>
- Rancher kubectl and kubeconfig access:
  <https://ranchermanager.docs.rancher.com/v2.11/how-to-guides/new-user-guides/manage-clusters/access-clusters/use-kubectl-and-kubeconfig>
- RKE2 cluster access:
  <https://docs.rke2.io/cluster_access>
- RKE2 requirements:
  <https://docs.rke2.io/install/requirements>
- OCM installation:
  <https://open-cluster-management.io/docs/getting-started/installation/>
- OCM architecture:
  <https://open-cluster-management.io/docs/concepts/architecture/>
