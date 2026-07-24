# OCM on Rancher — CLI Quick Start

This is the short, command-focused companion to
`docs/OCM-Rancher-Setup-Runbook.md`.

## How to use this document

This is the document to keep open during the meeting.

1. Start at Step 1.
2. Run one command block at a time.
3. Read the expected result immediately below it.
4. Stop if the result is different.
5. Use the full runbook only for explanation or troubleshooting.

Text inside `<angle-brackets>` is a placeholder and must be replaced before
the command is run. All other commands can be copied after the variables are
set.

## Do any repository files need to be changed?

No existing source file needs to be modified for the first Rancher test.

The commands use:

- the UBI9 Dockerfiles already changed on `feature/ubi9-ocm-migration`;
- the wrapper `Makefile` already added on that branch;
- the existing Cluster Manager and Klusterlet Helm charts; and
- temporary test and bootstrap files created under `/tmp`.

Do **not** use these Minikube-only files directly on Rancher:

```text
deploy/local/cluster-manager-ubi9-values.yaml
deploy/local/klusterlet-ubi9-values.yaml
```

They use local image names and `imagePullPolicy: Never`. The commands below
provide Rancher registry values directly to Helm.

## Which directory should be used?

Run the commands from the repository root:

```bash
cd "/Users/zohirul/Documents/Repo's/Persistent/ocm"
pwd
git branch --show-current
test -f Makefile
test -d build
test -d deploy
```

Expected branch:

```text
feature/ubi9-ocm-migration
```

Stay in this directory for the entire procedure. Commands that reference
`Makefile`, `build/`, or `deploy/` require the repository root. Pure `kubectl`
commands can technically run anywhere, but staying here avoids path mistakes.

## Before starting

Replace every value enclosed in `<...>` in the variable block below.

Required information:

1. Hub kubeconfig context from Rancher.
2. Managed-cluster kubeconfig context from Rancher.
3. Direct hub Kubernetes API URL reachable from the managed cluster.
4. Registry address/project.
5. Registry login.
6. OCM managed-cluster name.

Use two Rancher clusters for a realistic test. For a one-cluster smoke test,
set `HUB_CONTEXT` and `MANAGED_CONTEXT` to the same context.

## Step 1 — Set the deployment variables

```bash
cd "/Users/zohirul/Documents/Repo's/Persistent/ocm"

export HUB_CONTEXT="<rancher-hub-kube-context>"
export MANAGED_CONTEXT="<rancher-managed-kube-context>"
export MANAGED_CLUSTER_NAME="rancher-managed-01"

export REGISTRY_HOST="<registry-host>"
export IMAGE_REGISTRY="$REGISTRY_HOST/<registry-project>/ocm"
export IMAGE_TAG="phase1"

export HUB_API="https://<hub-api-hostname>:6443"
export OCM_NAMESPACE="open-cluster-management"

export REGISTRATION_IMAGE="$IMAGE_REGISTRY/registration:$IMAGE_TAG"
export WORK_IMAGE="$IMAGE_REGISTRY/work:$IMAGE_TAG"
export PLACEMENT_IMAGE="$IMAGE_REGISTRY/placement:$IMAGE_TAG"
export OPERATOR_IMAGE="$IMAGE_REGISTRY/registration-operator:$IMAGE_TAG"
export ADDON_IMAGE="$IMAGE_REGISTRY/addon:$IMAGE_TAG"

export HUB_CA_FILE="/tmp/ocm-hub-ca.crt"
export BOOTSTRAP_KUBECONFIG="/tmp/ocm-hub-bootstrap.kubeconfig"
```

For a same-cluster smoke test only, use:

```bash
export MANAGED_CONTEXT="$HUB_CONTEXT"
export HUB_API="https://kubernetes.default.svc:443"
```

Do not use `kubernetes.default.svc` when the managed cluster is separate from
the hub.

## Step 2 — Verify the selected Rancher clusters

```bash
kubectl config get-contexts

kubectl --context "$HUB_CONTEXT" cluster-info
kubectl --context "$HUB_CONTEXT" get nodes -o wide
kubectl --context "$HUB_CONTEXT" auth can-i '*' '*' --all-namespaces

kubectl --context "$MANAGED_CONTEXT" cluster-info
kubectl --context "$MANAGED_CONTEXT" get nodes -o wide
kubectl --context "$MANAGED_CONTEXT" auth can-i '*' '*' --all-namespaces
```

Both authorization commands must return:

```text
yes
```

Confirm AMD64:

```bash
kubectl --context "$HUB_CONTEXT" get nodes \
  -o custom-columns=NAME:.metadata.name,ARCH:.status.nodeInfo.architecture

kubectl --context "$MANAGED_CONTEXT" get nodes \
  -o custom-columns=NAME:.metadata.name,ARCH:.status.nodeInfo.architecture
```

Every node used by OCM must report `amd64`.

## Step 3 — Build and test all UBI9 images

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

Expected: five successful image builds and all image validation checks pass.

Show build evidence:

```bash
for IMAGE in \
  "$REGISTRATION_IMAGE" \
  "$WORK_IMAGE" \
  "$PLACEMENT_IMAGE" \
  "$OPERATOR_IMAGE" \
  "$ADDON_IMAGE"
do
  docker image inspect "$IMAGE" \
    --format 'image={{.RepoTags}} id={{.Id}} platform={{.Os}}/{{.Architecture}} user={{.Config.User}}'
done
```

## Step 4 — Log in and push the images

```bash
docker login "$REGISTRY_HOST"

make docker-push \
  IMAGE_REGISTRY="$IMAGE_REGISTRY" \
  IMAGE_TAG="$IMAGE_TAG"
```

Confirm all five image tags exist in the registry before continuing.

## Step 5 — Create registry pull secrets

Skip this step if the registry allows anonymous image pulls.

The Docker login in Step 4 creates or updates
`$HOME/.docker/config.json`. Use it to create the expected Kubernetes secret
on both clusters:

```bash
for CONTEXT in "$HUB_CONTEXT" "$MANAGED_CONTEXT"
do
  kubectl --context "$CONTEXT" create namespace "$OCM_NAMESPACE" \
    --dry-run=client -o yaml \
    | kubectl --context "$CONTEXT" apply -f -

  kubectl --context "$CONTEXT" -n "$OCM_NAMESPACE" \
    create secret generic \
    open-cluster-management-image-pull-credentials \
    --from-file=.dockerconfigjson="$HOME/.docker/config.json" \
    --type=kubernetes.io/dockerconfigjson \
    --dry-run=client -o yaml \
    | kubectl --context "$CONTEXT" apply -f -
done
```

## Step 6 — Validate the Helm charts

```bash
make helm-lint
make helm-package HELM_CHART_VERSION=0.3.0 IMAGE_TAG="$IMAGE_TAG"
```

## Step 7 — Install the OCM hub

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
  --wait \
  --timeout 10m
```

Check the hub:

```bash
helm --kube-context "$HUB_CONTEXT" \
  -n "$OCM_NAMESPACE" status cluster-manager

kubectl --context "$HUB_CONTEXT" get clustermanager
kubectl --context "$HUB_CONTEXT" get deployments,pods -A
```

## Step 8 — Create the short-lived bootstrap kubeconfig

Get the hub CA:

```bash
kubectl --context "$HUB_CONTEXT" \
  -n kube-public get configmap kube-root-ca.crt \
  -o jsonpath='{.data.ca\.crt}' \
  > "$HUB_CA_FILE"
```

Create a one-hour bootstrap token:

```bash
export BOOTSTRAP_TOKEN="$(
  kubectl --context "$HUB_CONTEXT" \
    -n "$OCM_NAMESPACE" create token \
    agent-registration-bootstrap \
    --duration=1h
)"
```

Create the temporary kubeconfig:

```bash
rm -f "$BOOTSTRAP_KUBECONFIG"

kubectl config --kubeconfig "$BOOTSTRAP_KUBECONFIG" \
  set-cluster ocm-hub \
  --server="$HUB_API" \
  --certificate-authority="$HUB_CA_FILE" \
  --embed-certs=true

kubectl config --kubeconfig "$BOOTSTRAP_KUBECONFIG" \
  set-credentials ocm-bootstrap \
  --token="$BOOTSTRAP_TOKEN"

kubectl config --kubeconfig "$BOOTSTRAP_KUBECONFIG" \
  set-context ocm-bootstrap \
  --cluster=ocm-hub \
  --user=ocm-bootstrap

kubectl config --kubeconfig "$BOOTSTRAP_KUBECONFIG" \
  use-context ocm-bootstrap

chmod 600 "$BOOTSTRAP_KUBECONFIG"
```

Test the hub API endpoint and bootstrap permission:

```bash
kubectl --kubeconfig "$BOOTSTRAP_KUBECONFIG" auth can-i \
  create certificatesigningrequests.certificates.k8s.io
```

Do not continue until this returns `yes`.

## Step 9 — Install the Klusterlet on the managed cluster

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
  --wait \
  --timeout 10m
```

Check the managed side:

```bash
helm --kube-context "$MANAGED_CONTEXT" \
  -n "$OCM_NAMESPACE" status klusterlet

kubectl --context "$MANAGED_CONTEXT" get klusterlet
kubectl --context "$MANAGED_CONTEXT" get deployments,pods -A
```

## Step 10 — Accept the managed cluster

Check that the registration request appeared:

```bash
kubectl --context "$HUB_CONTEXT" get managedclusters
```

Accept only the expected cluster:

```bash
kubectl --context "$HUB_CONTEXT" patch managedcluster \
  "$MANAGED_CLUSTER_NAME" \
  --type=merge \
  -p '{"spec":{"hubAcceptsClient":true}}'
```

Wait and inspect:

```bash
kubectl --context "$HUB_CONTEXT" get managedcluster \
  "$MANAGED_CLUSTER_NAME" \
  -w
```

Stop the watch with `Ctrl+C` when the cluster reports `Joined=True` and
`Available=True`, then run:

```bash
kubectl --context "$HUB_CONTEXT" describe managedcluster \
  "$MANAGED_CLUSTER_NAME"
```

## Step 11 — Run the Placement test

Create a temporary Rancher-specific test manifest:

```bash
sed \
  -e "s/ocm-local-test/ocm-rancher-test/g" \
  deploy/local/tests/placement.yaml \
  > /tmp/ocm-rancher-placement.yaml
```

Label and assign the managed cluster:

```bash
kubectl --context "$HUB_CONTEXT" label managedcluster \
  "$MANAGED_CLUSTER_NAME" \
  environment=ocm-rancher-test \
  --overwrite

kubectl --context "$HUB_CONTEXT" label managedcluster \
  "$MANAGED_CLUSTER_NAME" \
  cluster.open-cluster-management.io/clusterset=ocm-rancher-test \
  --overwrite
```

Apply and check:

```bash
kubectl --context "$HUB_CONTEXT" apply \
  -f /tmp/ocm-rancher-placement.yaml

kubectl --context "$HUB_CONTEXT" \
  -n ocm-functional-test \
  get placement,placementdecision -o wide
```

Pass: the PlacementDecision selects `$MANAGED_CLUSTER_NAME`.

## Step 12 — Run the ManifestWork test

Create a temporary Rancher-specific manifest:

```bash
sed \
  -e "s/ocm-ubi9-local/$MANAGED_CLUSTER_NAME/g" \
  deploy/local/tests/manifestwork.yaml \
  > /tmp/ocm-rancher-manifestwork.yaml
```

Apply and wait:

```bash
kubectl --context "$HUB_CONTEXT" apply \
  -f /tmp/ocm-rancher-manifestwork.yaml

kubectl --context "$HUB_CONTEXT" \
  -n "$MANAGED_CLUSTER_NAME" wait \
  --for=condition=Applied \
  manifestwork/ocm-configmap-delivery \
  --timeout=120s

kubectl --context "$HUB_CONTEXT" \
  -n "$MANAGED_CLUSTER_NAME" wait \
  --for=condition=Available \
  manifestwork/ocm-configmap-delivery \
  --timeout=120s
```

Confirm the delivered object on the managed cluster:

```bash
kubectl --context "$MANAGED_CONTEXT" \
  -n ocm-functional-target \
  get configmap delivered-by-ocm -o yaml
```

Pass: the ConfigMap exists and contains:

```text
OCM ManifestWork delivery succeeded
```

## Step 13 — Capture final evidence

```bash
helm --kube-context "$HUB_CONTEXT" list -A
helm --kube-context "$MANAGED_CONTEXT" list -A

kubectl --context "$HUB_CONTEXT" get clustermanager,managedcluster
kubectl --context "$MANAGED_CONTEXT" get klusterlet

kubectl --context "$HUB_CONTEXT" get deployments,pods -A
kubectl --context "$MANAGED_CONTEXT" get deployments,pods -A

kubectl --context "$HUB_CONTEXT" \
  -n ocm-functional-test \
  get placement,placementdecision -o yaml

kubectl --context "$HUB_CONTEXT" \
  -n "$MANAGED_CLUSTER_NAME" \
  get manifestwork -o yaml
```

## Step 14 — Remove temporary credentials

```bash
rm -f "$BOOTSTRAP_KUBECONFIG"
rm -f "$HUB_CA_FILE"
unset BOOTSTRAP_TOKEN
```

## Stop points

Do not continue if any of these occur:

- a context points to the wrong Rancher cluster;
- `cluster-admin` returns `no`;
- a node is not AMD64;
- any UBI9 image test fails;
- one of the five images is unavailable in the registry;
- the hub API is unreachable from the managed-cluster network;
- the bootstrap kubeconfig test fails;
- an unexpected admission or security policy rejects the deployment; or
- the managed-cluster name already belongs to another active registration.
