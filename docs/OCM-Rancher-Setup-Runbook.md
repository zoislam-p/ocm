# OCM on Rancher/RKE2 — Meeting and Installation Runbook

## How to use this document

This is the detailed reference, not the primary meeting checklist. During the
setup, follow `docs/OCM-Rancher-CLI-Quickstart.md`. Return here when a step
needs more explanation, a command fails, or rollback and evidence guidance is
needed.

## 1. Objective

Install the UBI9-based Open Cluster Management (OCM) images from this
repository onto Kubernetes clusters managed by Rancher:

- one Rancher/RKE2 cluster acts as the **OCM hub**;
- one Rancher/RKE2 cluster acts as the **managed cluster**; and
- OCM registration, Placement, and ManifestWork delivery are validated.

For a quick smoke test, the hub can register itself as the managed cluster.
For a meaningful Rancher test, use two clusters so network connectivity and
the hub/managed separation are exercised.

Rancher is the cluster-management interface in this setup. OCM is installed
inside the selected downstream Kubernetes clusters with Helm.

## Important: which branch this guide uses

This guide is based on:

```text
feature/ubi9-ocm-migration
```

It is **not** based on the clean `main` branch. The feature branch contains the
UBI9 Dockerfile changes, the wrapper Makefile, image tests, local Helm values,
and functional test manifests that the commands in this guide reference.

The feature branch started from `main` commit:

```text
0ab9a37d104b61bee41373c1d669280f56c2414b
```

Running this guide from clean `main` would omit our UBI9 build targets and
Rancher test material. Always confirm the branch first:

```bash
git branch --show-current
```

Expected result:

```text
feature/ubi9-ocm-migration
```

## First-time Rancher setup — simplified flow

Use this section as the meeting checklist. The later sections contain the full
commands and troubleshooting details.

### Step 1 — Choose the Rancher clusters

Choose one downstream Rancher/RKE2 cluster as the OCM hub and, preferably, a
second downstream cluster as the managed cluster.

**Why:** The hub makes decisions and sends work. The managed cluster runs the
OCM agents and receives that work.

**First-time option:** If only one test cluster is available, it can act as
both hub and managed cluster for a smoke test.

### Step 2 — Download kubeconfigs

Download the kubeconfig for each selected cluster from Rancher and identify
their context names.

**Why:** `kubectl` and Helm need to know exactly which Rancher cluster each
command should change.

### Step 3 — Check access and architecture

Confirm both clusters are healthy, the user has `cluster-admin`, and all nodes
are `amd64`.

**Why:** OCM installs cluster-wide CRDs and RBAC, and the current UBI9 images
were built specifically for AMD64.

### Step 4 — Build and test the five images

Run `make pre-build`, `make docker-build`, and `make docker-test` from the
feature branch.

**Why:** This produces and validates Registration, Work, Placement,
Registration Operator, and Add-on UBI9 images before anything is installed.

### Step 5 — Push the images to a registry

Push all five images to a registry reachable from the Rancher/RKE2 nodes.

**Why:** Minikube can use images loaded directly from a laptop. Rancher nodes
cannot see those local images and must pull them from a shared registry.

### Step 6 — Install the OCM hub with Helm

Install the existing Cluster Manager chart on the selected hub cluster.

**Why:** Helm installs the OCM CRDs, the operator, and a `ClusterManager`
custom resource. The operator then creates the hub application components.

### Step 7 — Create temporary bootstrap access

Create a short-lived bootstrap kubeconfig that points to the hub Kubernetes
API.

**Why:** The managed-cluster registration agent needs temporary permission to
request its OCM identity from the hub.

### Step 8 — Install the Klusterlet with Helm

Install the existing Klusterlet chart on the managed cluster.

**Why:** The Klusterlet operator creates the Registration and Work agents that
connect the managed cluster to the hub.

### Step 9 — Accept the managed cluster

On the hub, set `hubAcceptsClient: true` for the new `ManagedCluster`.

**Why:** OCM uses double opt-in registration. Installing the agent alone does
not authorize the hub to manage the cluster.

### Step 10 — Test real OCM behavior

Run the Placement and ManifestWork tests.

**Why:** Ready pods only prove that installation succeeded. Placement proves
cluster selection, and ManifestWork proves that the hub can deliver a
Kubernetes resource and receive status from the managed cluster.

## Files involved

### Files already changed on the feature branch

These changes are already complete. They should be reviewed, not edited during
the Rancher meeting:

| Files | Purpose |
|---|---|
| `build/Dockerfile.registration` | UBI9 runtime for Registration |
| `build/Dockerfile.work` | UBI9 runtime for Work |
| `build/Dockerfile.placement` | UBI9 runtime for Placement |
| `build/Dockerfile.registration-operator` | UBI9 runtime for the operator |
| `build/Dockerfile.addon` | UBI9 runtime for Add-on Manager |
| `build/Dockerfile.*.org` | Backup copies of the original Dockerfiles |
| `Makefile` | New wrapper build, test, package, and deploy targets |
| `Makefile.org` | Backup of the original upstream Makefile |
| `hack/verify-ubi9-dockerfiles.sh` | Static Dockerfile validation |
| `hack/verify-ubi9-images.sh` | Built-image runtime validation |
| `deploy/local/tests/placement.yaml` | Reusable Placement test |
| `deploy/local/tests/manifestwork.yaml` | Reusable ManifestWork test |

### Existing upstream Helm charts used without replacement

```text
deploy/cluster-manager/chart/cluster-manager
deploy/klusterlet/chart/klusterlet
```

The charts already install the CRDs, operators, and initial custom resources.
We do not need to create a new Rancher operator or a new Helm chart.

### Local-only files that must not be used directly on Rancher

```text
deploy/local/cluster-manager-ubi9-values.yaml
deploy/local/klusterlet-ubi9-values.yaml
```

These files use local Minikube image names and `imagePullPolicy: Never`.
Rancher/RKE2 requires registry-based image names and normally
`imagePullPolicy: IfNotPresent`.

### Rancher-specific values that must be supplied

For the first setup, the guide supplies these values with Helm `--set` options:

- image registry and tag;
- five complete image names;
- `imagePullPolicy=IfNotPresent`;
- managed-cluster name;
- short-lived hub bootstrap kubeconfig; and
- optional registry pull credentials.

This means no additional committed source file is required for the first
Rancher test. After the values are confirmed, we can create sanitized,
credential-free files such as:

```text
deploy/rancher/cluster-manager-ubi9-values.yaml
deploy/rancher/klusterlet-ubi9-values.yaml
```

Passwords, registry tokens, bootstrap tokens, and kubeconfigs must never be
committed. Store them as Kubernetes secrets or inject them during deployment.

## 2. Decisions to confirm at the start of the meeting

Record these before running commands:

| Item | Value needed |
|---|---|
| Rancher version | `<version>` |
| Kubernetes distribution and version | Expected: RKE2 `<version>` |
| Hub cluster/context | `<hub-context>` |
| Managed cluster/context | `<managed-context>` |
| Managed-cluster OCM name | Example: `rancher-managed-01` |
| CPU architecture | Must be `amd64` for the current images |
| Image registry | `<registry>/<project>/ocm` |
| Image tag | Example: `phase1` or approved release tag |
| Hub API endpoint reachable from managed cluster | `https://<hub-api-host>:6443` |
| Private registry authentication | Existing pull secret or Docker config |
| Proxy/firewall requirements | Registry, hub API, DNS, and Rancher URLs |
| Test topology | Same-cluster smoke test or two-cluster validation |

Do not use the Rancher management cluster as the OCM hub unless the platform
owner explicitly approves installing third-party CRDs and cluster-wide RBAC
there. A Rancher-managed downstream RKE2 cluster is the safer default.

## 3. Required access and tools

### Access

- Rancher access that can open each target cluster.
- `cluster-admin` permission on the hub and managed clusters.
- Permission to push the five images to a registry.
- Direct network reachability from managed-cluster pods to the hub Kubernetes
  API endpoint.
- Registry reachability from every RKE2 node.

### Workstation tools

```bash
docker --version
kubectl version --client
helm version
git --version
```

Use Helm 3. The repository wrapper also expects Docker by default; Podman can
be selected with `CONTAINER_ENGINE=podman`.

### Repository

```bash
git clone <repository-url>
cd ocm
git checkout feature/ubi9-ocm-migration
git status
```

The working tree should be clean before the installation begins.

## 4. Obtain and verify Rancher kubeconfig access

In Rancher, open **Cluster Management**, select the downstream cluster, choose
**Explore**, and download its kubeconfig. Rancher also provides a browser-based
Kubectl Shell, but a workstation is recommended because this workflow needs
the repository, Docker, and Helm.

Merge or reference the downloaded kubeconfigs, then identify the context names:

```bash
kubectl config get-contexts

export HUB_CONTEXT="<hub-context>"
export MANAGED_CONTEXT="<managed-context>"
export MANAGED_CLUSTER_NAME="rancher-managed-01"

kubectl --context "$HUB_CONTEXT" cluster-info
kubectl --context "$HUB_CONTEXT" get nodes -o wide
kubectl --context "$MANAGED_CONTEXT" cluster-info
kubectl --context "$MANAGED_CONTEXT" get nodes -o wide
```

Confirm administrative access and architecture:

```bash
kubectl --context "$HUB_CONTEXT" auth can-i '*' '*' --all-namespaces
kubectl --context "$MANAGED_CONTEXT" auth can-i '*' '*' --all-namespaces

kubectl --context "$HUB_CONTEXT" get nodes \
  -o custom-columns=NAME:.metadata.name,ARCH:.status.nodeInfo.architecture,OS:.status.nodeInfo.osImage
kubectl --context "$MANAGED_CONTEXT" get nodes \
  -o custom-columns=NAME:.metadata.name,ARCH:.status.nodeInfo.architecture,OS:.status.nodeInfo.osImage
```

Expected results:

- both authorization checks return `yes`;
- all target nodes report `amd64`; and
- both clusters are healthy before OCM is installed.

## 5. Configure image names

Use a registry that both RKE2 clusters can pull from. Do not use the local
Minikube prefix `ocm-ubi9` for Rancher unless that is an actual reachable
registry.

```bash
export IMAGE_REGISTRY="<registry>/<project>/ocm"
export IMAGE_TAG="phase1"
export OCM_NAMESPACE="open-cluster-management"

export REGISTRATION_IMAGE="$IMAGE_REGISTRY/registration:$IMAGE_TAG"
export WORK_IMAGE="$IMAGE_REGISTRY/work:$IMAGE_TAG"
export PLACEMENT_IMAGE="$IMAGE_REGISTRY/placement:$IMAGE_TAG"
export OPERATOR_IMAGE="$IMAGE_REGISTRY/registration-operator:$IMAGE_TAG"
export ADDON_IMAGE="$IMAGE_REGISTRY/addon:$IMAGE_TAG"
```

The repository builds these five existing OCM components:

| Image | Purpose |
|---|---|
| `registration` | Hub registration controller and managed-cluster agent |
| `work` | ManifestWork hub controller/webhook and managed-cluster agent |
| `placement` | Selects eligible managed clusters |
| `registration-operator` | Reconciles ClusterManager and Klusterlet resources |
| `addon` | Manages OCM add-on lifecycle |

## 6. Build and validate the UBI9 images

```bash
make pre-build

make docker-build \
  IMAGE_REGISTRY="$IMAGE_REGISTRY" \
  IMAGE_TAG="$IMAGE_TAG" \
  PLATFORM=linux/amd64

make docker-test \
  IMAGE_REGISTRY="$IMAGE_REGISTRY" \
  IMAGE_TAG="$IMAGE_TAG" \
  PLATFORM=linux/amd64
```

Expected result: all five builds complete and the tests confirm UBI9,
`linux/amd64`, non-root UID `10001`, executable binaries, and safe startup.

Optional evidence:

```bash
docker image inspect "$REGISTRATION_IMAGE" \
  --format 'image={{.Id}} platform={{.Os}}/{{.Architecture}} user={{.Config.User}}'

docker run --rm --platform linux/amd64 "$REGISTRATION_IMAGE" \
  /bin/bash -c 'cat /etc/redhat-release; id; test -x /registration'
```

## 7. Push images to the shared registry

Authenticate without putting credentials in the repository:

```bash
docker login "<registry>"

make docker-push \
  IMAGE_REGISTRY="$IMAGE_REGISTRY" \
  IMAGE_TAG="$IMAGE_TAG"
```

Confirm that all five tags are visible in the registry before continuing.
Production use should replace floating tags with an approved immutable tag or
digest.

## 8. Prepare private-registry pull credentials

Skip this section if the registry permits anonymous pulls.

The following creates the chart's expected pull-secret name from the existing
Docker client configuration. It does not place credentials in a values file:

```bash
for CONTEXT in "$HUB_CONTEXT" "$MANAGED_CONTEXT"; do
  kubectl --context "$CONTEXT" create namespace "$OCM_NAMESPACE" \
    --dry-run=client -o yaml | kubectl --context "$CONTEXT" apply -f -

  kubectl --context "$CONTEXT" -n "$OCM_NAMESPACE" create secret generic \
    open-cluster-management-image-pull-credentials \
    --from-file=.dockerconfigjson="$HOME/.docker/config.json" \
    --type=kubernetes.io/dockerconfigjson \
    --dry-run=client -o yaml | kubectl --context "$CONTEXT" apply -f -
done
```

If organizational policy provides a centrally managed pull secret, use that
instead and confirm the chart/service accounts reference the approved name.

## 9. Pre-render and lint the existing Helm charts

```bash
make helm-lint
make helm-package HELM_CHART_VERSION=0.3.0 IMAGE_TAG="$IMAGE_TAG"
```

Render the hub chart with the exact Rancher image settings:

```bash
helm template cluster-manager \
  deploy/cluster-manager/chart/cluster-manager \
  --namespace "$OCM_NAMESPACE" \
  --set replicaCount=1 \
  --set createBootstrapSA=true \
  --set images.imagePullPolicy=IfNotPresent \
  --set-string images.overrides.registrationImage="$REGISTRATION_IMAGE" \
  --set-string images.overrides.workImage="$WORK_IMAGE" \
  --set-string images.overrides.placementImage="$PLACEMENT_IMAGE" \
  --set-string images.overrides.operatorImage="$OPERATOR_IMAGE" \
  --set-string images.overrides.addOnManagerImage="$ADDON_IMAGE" \
  > /tmp/ocm-cluster-manager-rendered.yaml
```

Review `/tmp/ocm-cluster-manager-rendered.yaml` before installing. The
`replicaCount=1` setting is suitable for a small non-production test cluster;
use the approved replica count for production or HA validation.

## 10. Install the OCM hub

```bash
helm upgrade --install cluster-manager \
  deploy/cluster-manager/chart/cluster-manager \
  --kube-context "$HUB_CONTEXT" \
  --namespace "$OCM_NAMESPACE" \
  --create-namespace \
  --set replicaCount=1 \
  --set createBootstrapSA=true \
  --set images.imagePullPolicy=IfNotPresent \
  --set-string images.overrides.registrationImage="$REGISTRATION_IMAGE" \
  --set-string images.overrides.workImage="$WORK_IMAGE" \
  --set-string images.overrides.placementImage="$PLACEMENT_IMAGE" \
  --set-string images.overrides.operatorImage="$OPERATOR_IMAGE" \
  --set-string images.overrides.addOnManagerImage="$ADDON_IMAGE" \
  --wait --timeout 10m
```

Validate the operator, CR, and hub workloads:

```bash
helm --kube-context "$HUB_CONTEXT" -n "$OCM_NAMESPACE" status cluster-manager

kubectl --context "$HUB_CONTEXT" get crd | grep open-cluster-management
kubectl --context "$HUB_CONTEXT" get clustermanager cluster-manager -o yaml
kubectl --context "$HUB_CONTEXT" get deployments,pods -A
```

Expected:

- Helm release is `deployed`;
- `cluster-manager` operator is Ready;
- the `ClusterManager` condition reports success; and
- registration, work, placement, and add-on hub workloads are Ready.

Useful focused check:

```bash
kubectl --context "$HUB_CONTEXT" get deployments -A \
  -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[*].image \
  | grep -E 'cluster-manager|registration|work|placement|addon'
```

## 11. Create a short-lived hub bootstrap kubeconfig

The managed cluster's OCM agents must reach the hub Kubernetes API directly.
Do not assume a Rancher proxy-based kubeconfig URL will work for agents.

Set the API endpoint to a DNS name or load balancer reachable from the managed
cluster:

```bash
export HUB_API="https://<hub-api-host>:6443"
export HUB_CA_FILE="/tmp/ocm-hub-ca.crt"
export BOOTSTRAP_KUBECONFIG="/tmp/ocm-hub-bootstrap.kubeconfig"

kubectl --context "$HUB_CONTEXT" -n kube-public get configmap kube-root-ca.crt \
  -o jsonpath='{.data.ca\.crt}' > "$HUB_CA_FILE"

export BOOTSTRAP_TOKEN="$(
  kubectl --context "$HUB_CONTEXT" -n "$OCM_NAMESPACE" create token \
    agent-registration-bootstrap --duration=1h
)"

kubectl config --kubeconfig "$BOOTSTRAP_KUBECONFIG" set-cluster ocm-hub \
  --server="$HUB_API" \
  --certificate-authority="$HUB_CA_FILE" \
  --embed-certs=true

kubectl config --kubeconfig "$BOOTSTRAP_KUBECONFIG" set-credentials \
  ocm-bootstrap --token="$BOOTSTRAP_TOKEN"

kubectl config --kubeconfig "$BOOTSTRAP_KUBECONFIG" set-context ocm-bootstrap \
  --cluster=ocm-hub --user=ocm-bootstrap

kubectl config --kubeconfig "$BOOTSTRAP_KUBECONFIG" use-context ocm-bootstrap
```

Protect and test the API endpoint and bootstrap permission:

```bash
chmod 600 "$BOOTSTRAP_KUBECONFIG"
kubectl --kubeconfig "$BOOTSTRAP_KUBECONFIG" auth can-i \
  create certificatesigningrequests.certificates.k8s.io
```

Expected result: `yes`.

The token is deliberately short-lived. Do not commit the kubeconfig, token, CA
bundle, or registry credentials.

For a same-cluster smoke test only, `HUB_API` can be
`https://kubernetes.default.svc:443`. That address will not work from a
different cluster.

## 12. Install the Klusterlet on the managed Rancher cluster

Render first:

```bash
helm template klusterlet \
  deploy/klusterlet/chart/klusterlet \
  --namespace "$OCM_NAMESPACE" \
  --set klusterlet.name=klusterlet \
  --set-string klusterlet.clusterName="$MANAGED_CLUSTER_NAME" \
  --set images.imagePullPolicy=IfNotPresent \
  --set-string images.overrides.registrationImage="$REGISTRATION_IMAGE" \
  --set-string images.overrides.workImage="$WORK_IMAGE" \
  --set-string images.overrides.operatorImage="$OPERATOR_IMAGE" \
  --set-file bootstrapHubKubeConfig="$BOOTSTRAP_KUBECONFIG" \
  > /tmp/ocm-klusterlet-rendered.yaml
```

Install:

```bash
helm upgrade --install klusterlet \
  deploy/klusterlet/chart/klusterlet \
  --kube-context "$MANAGED_CONTEXT" \
  --namespace "$OCM_NAMESPACE" \
  --create-namespace \
  --set klusterlet.name=klusterlet \
  --set-string klusterlet.clusterName="$MANAGED_CLUSTER_NAME" \
  --set images.imagePullPolicy=IfNotPresent \
  --set-string images.overrides.registrationImage="$REGISTRATION_IMAGE" \
  --set-string images.overrides.workImage="$WORK_IMAGE" \
  --set-string images.overrides.operatorImage="$OPERATOR_IMAGE" \
  --set-file bootstrapHubKubeConfig="$BOOTSTRAP_KUBECONFIG" \
  --wait --timeout 10m
```

Check the managed-cluster side:

```bash
helm --kube-context "$MANAGED_CONTEXT" -n "$OCM_NAMESPACE" status klusterlet
kubectl --context "$MANAGED_CONTEXT" get klusterlet klusterlet -o yaml
kubectl --context "$MANAGED_CONTEXT" get deployments,pods -A \
  | grep -E 'klusterlet|registration-agent|work-agent'
```

## 13. Accept the managed cluster on the hub

OCM uses a double opt-in registration model. The managed cluster requests
registration and the hub administrator explicitly accepts it:

```bash
kubectl --context "$HUB_CONTEXT" get managedclusters

kubectl --context "$HUB_CONTEXT" patch managedcluster \
  "$MANAGED_CLUSTER_NAME" \
  --type=merge \
  -p '{"spec":{"hubAcceptsClient":true}}'

kubectl --context "$HUB_CONTEXT" get managedcluster \
  "$MANAGED_CLUSTER_NAME" \
  -o custom-columns=NAME:.metadata.name,JOINED:.status.conditions[?\\(@.type==\"ManagedClusterJoined\"\\)].status,AVAILABLE:.status.conditions[?\\(@.type==\"ManagedClusterConditionAvailable\"\\)].status
```

Because the chart configured the short-lived service-account identity under
`autoApproveUsers`, bootstrap CSRs should be approved automatically. If the
cluster does not join, inspect rather than blindly approving every CSR:

```bash
kubectl --context "$HUB_CONTEXT" get csr
kubectl --context "$HUB_CONTEXT" describe managedcluster "$MANAGED_CLUSTER_NAME"
kubectl --context "$MANAGED_CONTEXT" -n open-cluster-management-agent get pods
```

Expected: the managed cluster reaches `Joined=True` and `Available=True`.

## 14. Functional validation

The repository's existing test manifests use the local cluster name
`ocm-ubi9-local`. Generate Rancher-specific temporary copies without changing
the committed local evidence files:

```bash
sed \
  -e "s/ocm-local-test/ocm-rancher-test/g" \
  deploy/local/tests/placement.yaml \
  > /tmp/ocm-rancher-placement.yaml

sed \
  -e "s/ocm-ubi9-local/$MANAGED_CLUSTER_NAME/g" \
  deploy/local/tests/manifestwork.yaml \
  > /tmp/ocm-rancher-manifestwork.yaml
```

### Placement

```bash
kubectl --context "$HUB_CONTEXT" label managedcluster \
  "$MANAGED_CLUSTER_NAME" environment=ocm-rancher-test --overwrite

kubectl --context "$HUB_CONTEXT" label managedcluster \
  "$MANAGED_CLUSTER_NAME" \
  cluster.open-cluster-management.io/clusterset=ocm-rancher-test \
  --overwrite
```

Apply the Rancher-specific Placement manifest, then check:

```bash
kubectl --context "$HUB_CONTEXT" apply \
  -f /tmp/ocm-rancher-placement.yaml

kubectl --context "$HUB_CONTEXT" -n ocm-functional-test \
  get placement,placementdecision -o wide
```

Pass condition: the `PlacementDecision` selects `$MANAGED_CLUSTER_NAME`.

### ManifestWork

Apply the Rancher-specific ManifestWork and wait for feedback:

```bash
kubectl --context "$HUB_CONTEXT" apply \
  -f /tmp/ocm-rancher-manifestwork.yaml

kubectl --context "$HUB_CONTEXT" -n "$MANAGED_CLUSTER_NAME" wait \
  --for=condition=Applied \
  manifestwork/ocm-configmap-delivery \
  --timeout=120s

kubectl --context "$HUB_CONTEXT" -n "$MANAGED_CLUSTER_NAME" wait \
  --for=condition=Available \
  manifestwork/ocm-configmap-delivery \
  --timeout=120s

kubectl --context "$HUB_CONTEXT" -n "$MANAGED_CLUSTER_NAME" \
  get manifestwork

kubectl --context "$MANAGED_CONTEXT" -n ocm-functional-target \
  get configmap delivered-by-ocm -o yaml
```

Pass conditions:

- ManifestWork reports `Applied=True`;
- ManifestWork reports `Available=True`; and
- `delivered-by-ocm` exists on the managed cluster.

## 15. What to inspect in the Rancher UI

For each downstream cluster, select **Explore**:

- **Workloads > Deployments/Pods**
  - hub: cluster-manager operator and registration/work/placement/add-on;
  - managed: klusterlet operator, registration agent, and work agent.
- **More Resources > Custom Resources**
  - hub: ClusterManager, ManagedCluster, Placement, PlacementDecision,
    ManifestWork;
  - managed: Klusterlet and AppliedManifestWork.
- **Namespaces**
  - `open-cluster-management`;
  - `open-cluster-management-hub`;
  - `open-cluster-management-agent`;
  - namespace named after the managed cluster.
- **Events and logs**
  - image-pull failures;
  - RBAC errors;
  - certificate/bootstrap errors;
  - inability to reach the hub API.

Rancher's cluster dashboard is an infrastructure UI. OCM core does not include
the Red Hat ACM product console.

## 16. Troubleshooting

### `ImagePullBackOff`

```bash
kubectl --context "<affected-context>" -n "<namespace>" describe pod "<pod>"
kubectl --context "<affected-context>" -n "$OCM_NAMESPACE" get secret \
  open-cluster-management-image-pull-credentials
```

Confirm registry DNS/TLS trust, the exact image name/tag, registry
authentication, node egress, and `amd64` availability.

### Operator is Ready but application workloads are missing

```bash
kubectl --context "$HUB_CONTEXT" describe clustermanager cluster-manager
kubectl --context "$HUB_CONTEXT" -n "$OCM_NAMESPACE" logs \
  deployment/cluster-manager
kubectl --context "$HUB_CONTEXT" get events -A --sort-by=.lastTimestamp
```

### Managed cluster never joins

```bash
kubectl --context "$HUB_CONTEXT" get managedcluster "$MANAGED_CLUSTER_NAME" -o yaml
kubectl --context "$HUB_CONTEXT" get csr
kubectl --context "$MANAGED_CONTEXT" -n open-cluster-management-agent get pods
kubectl --context "$MANAGED_CONTEXT" -n open-cluster-management-agent logs \
  deployment/klusterlet-registration-agent
```

Common causes are an unreachable `HUB_API`, incorrect CA, expired bootstrap
token, proxy/`NO_PROXY` configuration, DNS, or hub acceptance not completed.

### CRDs or cluster-wide RBAC are blocked

Confirm that the Rancher role grants cluster-admin and that organizational
admission policies allow OCM CRDs, ClusterRoles, webhooks, and namespaces.

### Pod Security or admission-policy rejection

```bash
kubectl --context "<affected-context>" get events -A --sort-by=.lastTimestamp
kubectl --context "<affected-context>" describe pod -n "<namespace>" "<pod>"
```

Capture the exact policy name and rejection message before changing security
settings. The UBI9 images are already configured to run as non-root UID 10001.

## 17. Rollback

Remove test resources first, then the managed side, then the hub:

```bash
helm --kube-context "$MANAGED_CONTEXT" -n "$OCM_NAMESPACE" uninstall klusterlet

kubectl --context "$HUB_CONTEXT" delete managedcluster \
  "$MANAGED_CLUSTER_NAME" --ignore-not-found

helm --kube-context "$HUB_CONTEXT" -n "$OCM_NAMESPACE" uninstall cluster-manager
```

Do not delete OCM CRDs until all OCM custom resources are removed and the
platform owner confirms no other installation uses them. CRD deletion also
deletes the stored custom resources of that type.

Delete local credential material:

```bash
rm -f "$BOOTSTRAP_KUBECONFIG" "$HUB_CA_FILE"
unset BOOTSTRAP_TOKEN
```

## 18. Evidence to save

Capture these for the manager report and project evidence:

```bash
helm --kube-context "$HUB_CONTEXT" list -A
helm --kube-context "$MANAGED_CONTEXT" list -A
kubectl --context "$HUB_CONTEXT" get clustermanager,managedcluster
kubectl --context "$MANAGED_CONTEXT" get klusterlet
kubectl --context "$HUB_CONTEXT" get deployments,pods -A
kubectl --context "$MANAGED_CONTEXT" get deployments,pods -A
kubectl --context "$HUB_CONTEXT" -n ocm-functional-test \
  get placement,placementdecision -o yaml
kubectl --context "$HUB_CONTEXT" -n "$MANAGED_CLUSTER_NAME" \
  get manifestwork -o yaml
```

Also record:

- Rancher and RKE2 versions;
- Git commit and branch;
- image names, tags, digests, and architecture;
- Helm chart version;
- timestamps;
- pass/fail result for each validation;
- screenshots of Rancher workload health; and
- blockers, policy exceptions, or networking changes.

## 19. Meeting completion criteria

The meeting is successful when:

1. the topology and target clusters are agreed;
2. both kubeconfig contexts and cluster-admin access work;
3. the shared registry and direct hub API endpoint are confirmed;
4. the five UBI9 images are available to RKE2 nodes;
5. the hub operator and OCM application controllers are Ready;
6. the Klusterlet and managed agents are Ready;
7. the managed cluster reports `Joined=True` and `Available=True`;
8. Placement selects the managed cluster;
9. ManifestWork delivers a resource and reports feedback; and
10. evidence and remaining blockers are recorded.

## 20. Official references

- Rancher: Register an existing cluster  
  <https://ranchermanager.docs.rancher.com/v2.12/how-to-guides/new-user-guides/kubernetes-clusters-in-rancher-setup/register-existing-clusters>
- Rancher: Access a cluster with kubectl and kubeconfig  
  <https://ranchermanager.docs.rancher.com/v2.11/how-to-guides/new-user-guides/manage-clusters/access-clusters/use-kubectl-and-kubeconfig>
- RKE2: Cluster access and kubeconfig  
  <https://docs.rke2.io/cluster_access>
- RKE2: Requirements  
  <https://docs.rke2.io/install/requirements>
- OCM: Installation  
  <https://open-cluster-management.io/docs/getting-started/installation/>
- OCM: Architecture and double opt-in registration  
  <https://open-cluster-management.io/docs/concepts/architecture/>
