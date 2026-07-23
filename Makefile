SHELL := /bin/bash
.DEFAULT_GOAL := help

# Sovereign Core / SPS wrapper Makefile.
# Upstream targets remain unchanged in Makefile.org and can be called through
# the upstream-* targets below.

CONTAINER_ENGINE ?= docker
PLATFORM ?= linux/amd64
IMAGE_REGISTRY ?= ocm-ubi9
IMAGE_TAG ?= phase1

REGISTRATION_IMAGE ?= $(IMAGE_REGISTRY)/registration:$(IMAGE_TAG)
WORK_IMAGE ?= $(IMAGE_REGISTRY)/work:$(IMAGE_TAG)
PLACEMENT_IMAGE ?= $(IMAGE_REGISTRY)/placement:$(IMAGE_TAG)
OPERATOR_IMAGE ?= $(IMAGE_REGISTRY)/registration-operator:$(IMAGE_TAG)
ADDON_IMAGE ?= $(IMAGE_REGISTRY)/addon:$(IMAGE_TAG)

KUBE_CONTEXT ?= ocm-ubi9
MINIKUBE_PROFILE ?= ocm-ubi9
HELM_NAMESPACE ?= open-cluster-management
HELM_CHART_VERSION ?= 0.3.0
HELM_OUTPUT_DIR ?= dist/charts
BOOTSTRAP_HUB_KUBECONFIG ?=

IMAGES := \
	$(REGISTRATION_IMAGE) \
	$(WORK_IMAGE) \
	$(PLACEMENT_IMAGE) \
	$(OPERATOR_IMAGE) \
	$(ADDON_IMAGE)

.PHONY: help pre-build docker-build docker-test docker-push pipeline-local deploy deploy-managed \
	helm-lint helm-template helm-package local-load-images local-status \
	build test-unit verify update lint upstream-build upstream-test-unit upstream-verify

help: ## Show the supported local and SPS pipeline targets.
	@awk 'BEGIN {FS = ":.*## "; printf "Usage: make <target> [VARIABLE=value]\n\nTargets:\n"} /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

pre-build: ## Validate prerequisites, backups, Dockerfiles, and Helm charts.
	@command -v $(CONTAINER_ENGINE) >/dev/null || { echo "Missing container engine: $(CONTAINER_ENGINE)"; exit 1; }
	@command -v helm >/dev/null || { echo "Missing required command: helm"; exit 1; }
	@test -f Makefile.org || { echo "Makefile.org is required"; exit 1; }
	@bash hack/verify-ubi9-dockerfiles.sh
	@$(MAKE) --no-print-directory helm-lint

docker-build: ## Build every OCM runtime image for linux/amd64.
	$(CONTAINER_ENGINE) build --platform $(PLATFORM) -f build/Dockerfile.registration -t $(REGISTRATION_IMAGE) .
	$(CONTAINER_ENGINE) build --platform $(PLATFORM) -f build/Dockerfile.work -t $(WORK_IMAGE) .
	$(CONTAINER_ENGINE) build --platform $(PLATFORM) -f build/Dockerfile.placement -t $(PLACEMENT_IMAGE) .
	$(CONTAINER_ENGINE) build --platform $(PLATFORM) -f build/Dockerfile.registration-operator -t $(OPERATOR_IMAGE) .
	$(CONTAINER_ENGINE) build --platform $(PLATFORM) -f build/Dockerfile.addon -t $(ADDON_IMAGE) .

docker-test: ## Verify UBI9, amd64, non-root execution, binaries, and help startup.
	IMAGE_REGISTRY=$(IMAGE_REGISTRY) IMAGE_TAG=$(IMAGE_TAG) PLATFORM=$(PLATFORM) \
		CONTAINER_ENGINE=$(CONTAINER_ENGINE) bash hack/verify-ubi9-images.sh

docker-push: ## Push all images; set IMAGE_REGISTRY to an authenticated registry.
	@for image in $(IMAGES); do $(CONTAINER_ENGINE) push "$$image"; done

pipeline-local: pre-build docker-build docker-test helm-package ## Run the credential-free local CI sequence.

helm-lint: ## Lint both upstream OCM Helm charts.
	helm lint deploy/cluster-manager/chart/cluster-manager
	helm lint deploy/klusterlet/chart/klusterlet

helm-template: ## Render both charts with the local UBI9 image values.
	helm template cluster-manager deploy/cluster-manager/chart/cluster-manager \
		--namespace $(HELM_NAMESPACE) \
		--values deploy/local/cluster-manager-ubi9-values.yaml >/dev/null
	helm template klusterlet deploy/klusterlet/chart/klusterlet \
		--namespace $(HELM_NAMESPACE) \
		--values deploy/local/klusterlet-ubi9-values.yaml \
		--set-file bootstrapHubKubeConfig=deploy/local/bootstrap-placeholder.kubeconfig >/dev/null

helm-package: helm-lint ## Package both charts as version 0.3.0 for OCI publication.
	@mkdir -p $(HELM_OUTPUT_DIR)
	helm package deploy/cluster-manager/chart/cluster-manager \
		--version $(HELM_CHART_VERSION) --app-version $(IMAGE_TAG) \
		--destination $(HELM_OUTPUT_DIR)
	helm package deploy/klusterlet/chart/klusterlet \
		--version $(HELM_CHART_VERSION) --app-version $(IMAGE_TAG) \
		--destination $(HELM_OUTPUT_DIR)

local-load-images: ## Load all locally built images into the isolated Minikube profile.
	@for image in $(IMAGES); do minikube image load --profile $(MINIKUBE_PROFILE) "$$image"; done

deploy: ## Install/upgrade the hub operator and ClusterManager application with Helm.
	helm upgrade --install cluster-manager deploy/cluster-manager/chart/cluster-manager \
		--kube-context $(KUBE_CONTEXT) \
		--namespace $(HELM_NAMESPACE) --create-namespace \
		--values deploy/local/cluster-manager-ubi9-values.yaml

deploy-managed: ## Install/upgrade Klusterlet; requires BOOTSTRAP_HUB_KUBECONFIG.
	@test -n "$(BOOTSTRAP_HUB_KUBECONFIG)" || { echo "Set BOOTSTRAP_HUB_KUBECONFIG to a short-lived bootstrap kubeconfig"; exit 1; }
	helm upgrade --install klusterlet deploy/klusterlet/chart/klusterlet \
		--kube-context $(KUBE_CONTEXT) \
		--namespace $(HELM_NAMESPACE) \
		--values deploy/local/klusterlet-ubi9-values.yaml \
		--set-file bootstrapHubKubeConfig=$(BOOTSTRAP_HUB_KUBECONFIG)

local-status: ## Show the local Helm releases, workloads, and OCM resources.
	helm --kube-context $(KUBE_CONTEXT) list --all-namespaces
	kubectl --context $(KUBE_CONTEXT) get deployments,pods --all-namespaces
	kubectl --context $(KUBE_CONTEXT) get clustermanager,klusterlet,managedcluster

upstream-build: ## Delegate the original build target to Makefile.org.
	$(MAKE) -f Makefile.org build

upstream-test-unit: ## Delegate the original unit-test target to Makefile.org.
	$(MAKE) -f Makefile.org test-unit

upstream-verify: ## Delegate the original verification target to Makefile.org.
	$(MAKE) -f Makefile.org verify

# Compatibility entry points used by upstream development and the Dockerfile
# builder stages. The original implementation remains in Makefile.org.
build: upstream-build

test-unit: upstream-test-unit

verify: upstream-verify

update lint:
	$(MAKE) -f Makefile.org $@
