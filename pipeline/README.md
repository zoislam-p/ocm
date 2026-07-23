# Pipeline contract

The Sovereign Core SPS pipeline must call the top-level wrapper Makefile rather
than reproducing build commands in pipeline YAML.

## Credential-free build sequence

```bash
make pre-build
make docker-build IMAGE_REGISTRY=<registry>/<namespace> IMAGE_TAG=<tag>
make docker-test IMAGE_REGISTRY=<registry>/<namespace> IMAGE_TAG=<tag>
make helm-package IMAGE_TAG=<tag> HELM_CHART_VERSION=0.3.0
```

For local execution, the same sequence is available as:

```bash
make pipeline-local
```

## Publication hooks

After authentication is injected by the pipeline, images can be published with:

```bash
make docker-push IMAGE_REGISTRY=<registry>/<namespace> IMAGE_TAG=<tag>
```

The pipeline—not this repository—owns credentials, the IBM Container Registry
namespace, security scanning, GaraSign signing, MCSP REPLACEMENTS, OCI chart
publication, and generated `oc-mirror` manifests. Exact IBM values remain
placeholders until access and conventions are provided.

## Required external acceptance gates

1. All images pass the SPS security scan.
2. SPS signs the images through GaraSign.
3. Images and Helm OCI artifacts publish to the approved ICR namespace.
4. The generated mirror manifest successfully mirrors both artifact types.
5. The `0.3.0` charts deploy successfully to RKE2.
6. Required CLIs execute successfully on Linux AMD64 in the Landing Zone.
