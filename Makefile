# Vela version
VELA_VERSION ?= 0.1.0
# Repo info
GIT_COMMIT ?= git-$(shell git rev-parse --short HEAD)
VELA_VERSION_VAR := github.com/cloud-native-application/rudrx/version.VelaVersion
VELA_GITVERSION_VAR := github.com/cloud-native-application/rudrx/version.GitRevision
LDFLAGS ?= "-X $(VELA_VERSION_VAR)=$(VELA_VERSION) -X $(VELA_GITVERSION_VAR)=$(GIT_COMMIT)"

GOX      = go run github.com/mitchellh/gox
TARGETS  := darwin/amd64 linux/amd64 windows/amd64

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

all: build

# Run tests
test: fmt vet lint
	go test ./pkg/... -coverprofile cover.out

# Build manager binary
build: fmt vet lint
	go build -o bin/vela -ldflags ${LDFLAGS} cmd/vela/main.go

npm-build:
	cd dashboard && npm run build && cd ./..

npm-install:
	cd dashboard && npm install && cd ./..

generate-source:
	go run hack/frontend/source.go

cross-build:
# TODO: build vela core chart into vela binary
	GO111MODULE=on CGO_ENABLED=0 $(GOX) -ldflags $(LDFLAGS) -parallel=3 -output="bin/vela-{{.OS}}-{{.Arch}}" -osarch='$(TARGETS)' ./cmd/vela/

# Run against the configured Kubernetes cluster in ~/.kube/config
run: fmt vet
	go run ./cmd/core/main.go

# Run go fmt against code
fmt:
	go fmt ./...

# Run go vet against code
vet:
	go vet ./...

lint: golangci
	$(GOLANGCILINT) run -E golint,goimports  ./...

# Build the docker image
docker-build: test
	docker build . -t ${IMG}

# Push the docker image
docker-push:
	docker push ${IMG}

e2e-setup:
	ginkgo version
	ginkgo -v -r e2e/setup
	bin/vela dashboard &

e2e-test:
	# Run e2e test
	ginkgo -v -skipPackage setup,apiserver -r e2e

e2e-api-test:
	# Run e2e test
	ginkgo -v -r e2e/apiserver

e2e-cleanup:
	# Clean up


# Image URL to use all building/pushing image targets
IMG ?= vela-core:latest
# Produce CRDs that work back to Kubernetes 1.11 (no version conversion)
CRD_OPTIONS ?= "crd:crdVersions=v1"

# Run tests
core-test: generate fmt vet manifests
	go test ./pkg/... -coverprofile cover.out

# Build manager binary
manager: generate fmt vet
	go build -o bin/manager ./cmd/core/main.go

# Run against the configured Kubernetes cluster in ~/.kube/config
core-run: generate fmt vet manifests
	go run ./cmd/core/main.go

# Install CRDs into a cluster
core-install: manifests
	kustomize build config/crd | kubectl apply -f -

# Uninstall CRDs from a cluster
core-uninstall: manifests
	kustomize build config/crd | kubectl delete -f -

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
core-deploy: manifests
	cd config/manager && kustomize edit set image controller=${IMG}
	kustomize build config/default | kubectl apply -f -

# Generate manifests e.g. CRD, RBAC etc.
manifests: controller-gen
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=charts/vela/crds

# Generate code
generate: controller-gen
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

# find or download controller-gen
# download controller-gen if necessary
controller-gen:
ifeq (, $(shell which controller-gen))
	@{ \
	set -e ;\
	CONTROLLER_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$CONTROLLER_GEN_TMP_DIR ;\
	go mod init tmp ;\
	go get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.2.5 ;\
	rm -rf $$CONTROLLER_GEN_TMP_DIR ;\
	}
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif

GOLANGCILINT_VERSION ?= v1.29.0
HOSTOS := $(shell uname -s | tr '[:upper:]' '[:lower:]')
HOSTARCH := $(shell uname -m)
ifeq ($(HOSTARCH),x86_64)
HOSTARCH := amd64
endif

golangci:
ifeq (, $(shell which golangci-lint))
	@{ \
	set -e ;\
	echo 'installing golangci-lint-$(GOLANGCILINT_VERSION)' ;\
	curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(GOBIN) $(GOLANGCILINT_VERSION) ;\
	echo 'Install succeed' ;\
	}
GOLANGCILINT=$(GOBIN)/golangci-lint
else
GOLANGCILINT=$(shell which golangci-lint)
endif
