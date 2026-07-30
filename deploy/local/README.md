# Local UBI9 Helm validation

The repository already provides Helm charts for the OCM Cluster Manager and
Klusterlet. These values select locally built `ocm-ubi9/*:phase1` images and
disable image pulls so Minikube uses the images loaded from Docker.

## Prerequisites

```bash
minikube start --profile ocm-ubi9 --driver=docker --cpus=4 --memory=6144
minikube image load --profile ocm-ubi9 ocm-ubi9/registration:phase1
minikube image load --profile ocm-ubi9 ocm-ubi9/work:phase1
minikube image load --profile ocm-ubi9 ocm-ubi9/placement:phase1
minikube image load --profile ocm-ubi9 ocm-ubi9/addon:phase1
minikube image load --profile ocm-ubi9 ocm-ubi9/registration-operator:phase1
```

The SPS-compatible wrapper Makefile provides the same local workflow:

```bash
make pre-build
make docker-build
make docker-test
make helm-package
make local-load-images
```

`make pipeline-local` runs the complete credential-free build sequence.
Publishing, signing, security scanning, and mirroring remain IBM pipeline
responsibilities and are intentionally not hardcoded here.

## Install the hub

```bash
helm upgrade --install cluster-manager \
  deploy/cluster-manager/chart/cluster-manager \
  --kube-context ocm-ubi9 \
  --namespace open-cluster-management \
  --create-namespace \
  --values deploy/local/cluster-manager-ubi9-values.yaml
```

The equivalent wrapper target is `make deploy`.

## Install the Klusterlet

The Klusterlet chart requires hub bootstrap credentials. Create a bootstrap
kubeconfig/token for the installed hub. For same-cluster testing, enable
`createBootstrapSA` in the hub values, issue a short-lived token for the
`agent-registration-bootstrap` service account, and use the
`kube-root-ca.crt` ConfigMap CA with the in-cluster API endpoint
`https://kubernetes.default.svc:443`. Keep that kubeconfig outside the
repository. Then install with:

```bash
helm upgrade --install klusterlet \
  deploy/klusterlet/chart/klusterlet \
  --kube-context ocm-ubi9 \
  --namespace open-cluster-management \
  --values deploy/local/klusterlet-ubi9-values.yaml \
  --set-file bootstrapHubKubeConfig=<bootstrap-kubeconfig-path>
```

The equivalent wrapper target is:

```bash
make deploy-managed BOOTSTRAP_HUB_KUBECONFIG=<bootstrap-kubeconfig-path>
```

Complete OCM's double opt-in registration after the `ManagedCluster` and CSR
appear:

```bash
kubectl --context ocm-ubi9 patch managedcluster ocm-ubi9-local \
  --type=merge -p '{"spec":{"hubAcceptsClient":true}}'
kubectl --context ocm-ubi9 certificate approve <bootstrap-csr-name>
```

Validate the local hub and managed cluster:

```bash
helm --kube-context ocm-ubi9 list --all-namespaces
kubectl --context ocm-ubi9 get managedclusters
kubectl --context ocm-ubi9 get deployments,pods --all-namespaces
```

Use explicit `--kube-context ocm-ubi9` on every command to avoid changing or
mutating another configured cluster.

## View the local hub

OCM core does not include an ACM-style product console. The Kubernetes
Dashboard can display the operators, application workloads, namespaces, and
logs in the isolated Minikube cluster:

```bash
minikube addons enable dashboard --profile ocm-ubi9
minikube addons enable metrics-server --profile ocm-ubi9
minikube dashboard --profile ocm-ubi9
```

Useful namespaces in the UI are:

- `open-cluster-management` — Cluster Manager and Klusterlet operators
- `open-cluster-management-hub` — hub application components
- `open-cluster-management-agent` — managed-cluster agents
- `ocm-functional-test` — Placement functional test
- `ocm-ubi9-local` — ManifestWork objects for the managed cluster

Run the reusable tests in `deploy/local/tests` to verify Placement selection
and ManifestWork delivery before inspecting their resources in the UI.
