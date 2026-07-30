# Local OCM functional tests

These tests use the isolated `ocm-ubi9` Minikube context.

## Placement

```bash
kubectl --context ocm-ubi9 label managedcluster ocm-ubi9-local \
  environment=ocm-local-test --overwrite
kubectl --context ocm-ubi9 label managedcluster ocm-ubi9-local \
  cluster.open-cluster-management.io/clusterset=ocm-local-test --overwrite
kubectl --context ocm-ubi9 apply -f deploy/local/tests/placement.yaml
kubectl --context ocm-ubi9 -n ocm-functional-test get \
  placement,placementdecision -o wide
```

The `PlacementDecision` must select `ocm-ubi9-local`.

## ManifestWork

```bash
kubectl --context ocm-ubi9 apply -f deploy/local/tests/manifestwork.yaml
kubectl --context ocm-ubi9 -n ocm-ubi9-local get manifestwork \
  ocm-configmap-delivery
kubectl --context ocm-ubi9 -n ocm-functional-target get configmap \
  delivered-by-ocm -o yaml
```

The ManifestWork must report `Applied=True` and `Available=True`, and the
delivered ConfigMap must contain `OCM ManifestWork delivery succeeded`.
