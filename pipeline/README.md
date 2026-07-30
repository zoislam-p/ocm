# Pipeline contract

The Sovereign Core SPS pipeline must call the top-level wrapper Makefile rather
than reproducing build commands in pipeline YAML.

## Wrapper target origin and purpose

These targets are additions in the top-level wrapper; they are not original
targets copied from `Makefile.org`.

| Target | Why the wrapper adds it | Existing project content reused |
| --- | --- | --- |
| `pre-build` | Fail early on missing tools/backups, invalid UBI9 runtime settings, or Helm lint errors. | Five upstream Dockerfiles and two upstream Helm charts. |
| `docker-build` | Give SPS one aggregate command to build every required OCM image for `linux/amd64`. | The same five component Dockerfile paths declared by the original upstream Makefile. |
| `docker-test` | Verify the packaged images are UBI9, AMD64, non-root, executable, and able to start safely. | The binaries produced by the existing upstream build logic. |
| `helm-package` | Package both charts at the required `0.3.0` version before pipeline-managed OCI publication. | Existing Cluster Manager and Klusterlet charts. |
| `deploy` | Provide a standard Helm command for installing/upgrading the hub with UBI9 image overrides. | Existing Cluster Manager chart; `deploy-managed` separately installs Klusterlet. |

OCM produces several images from one repository. The upstream project therefore
uses the existing `build/Dockerfile.<component>` convention, such as
`Dockerfile.addon`, `Dockerfile.work`, and `Dockerfile.registration`. The
original `Makefile.org` already declares these five component-specific paths.
The wrapper does not introduce or rename that convention.

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
