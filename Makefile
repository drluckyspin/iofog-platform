SHELL = /bin/bash
OS = $(shell uname -s | tr A-Z a-z)

# Project variables
PACKAGE = github.com/iofog/iofog-platform

# Build variables
VERSION ?= $(shell git rev-parse --abbrev-ref HEAD)
COMMIT_HASH ?= $(shell git rev-parse --short HEAD 2>/dev/null)
BUILD_DATE ?= $(shell date +%FT%T%z)
K8S_VERSION ?= 1.13.4
MINIKUBE_VERSION ?= 0.35.0
SVCS = agent connector controller kubelet operator scheduler

# Install targets
.PHONY: install-kubectl
install-kubectl:
	curl -Lo kubectl https://storage.googleapis.com/kubernetes-release/release/v$(K8S_VERSION)/bin/$(OS)/amd64/kubectl
	chmod +x kubectl
	sudo mv kubectl /usr/local/bin/

.PHONY: install-kind
install-kind:
	go get sigs.k8s.io/kind

.PHONY: install-ansible
install-ansible:
	python --version
	sudo easy_install pip
	sudo pip install ansible
	ANSIBLE_CONFIG=./deploy/ansible ansible --version

.PHONY: install-minikube
install-minikube:
	curl -Lo minikube https://storage.googleapis.com/minikube/releases/v$(MINIKUBE_VERSION)/minikube-$(OS)-amd64
	chmod +x minikube
	sudo mv minikube /usr/local/bin/

.PHONY: install-terraform
install-terraform:
	curl -fSL -o terraform.zip https://releases.hashicorp.com/terraform/0.11.13/terraform_0.11.13_$(OS)_amd64.zip
	sudo unzip -q terraform.zip -d /opt/terraform
	rm -f terraform.zip
	sudo ln -s /opt/terraform/terraform /usr/local/bin/terraform

.PHONY: install-gcloud
install-gcloud:
	curl -Lo gcloud.tar.gz https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-240.0.0-$(OS)-x86_64.tar.gz
	tar -xf gcloud.tar.gz
	rm gcloud.tar.gz
	google-cloud-sdk/install.sh -q

# Deploy targets
.PHONY: gen-creds-gcp
gen-creds-gcp:
	printenv GCP_SVC_ACC > creds/svcacc.json
	printenv IOF_PUB_KLT > creds/id_klt.pub
	printenv IOF_PUB_SRG > creds/id_srg.pub
	printenv IOF_PUB_RSH > creds/id_rsh.pub
	printenv IOF_PUB_TOD > creds/id_tod.pub

.PHONY: deploy-gcp
deploy-gcp: gen-creds-gcp
	gcloud auth activate-service-account --key-file=creds/svcacc.json
	gcloud config set project edgeworx
	terraform init deploy/gcp
	terraform apply -auto-approve deploy/gcp

.PHONY: deploy-kind
deploy-kind: install-kind
	kind create cluster
	$(eval export KUBECONFIG=$(shell kind get kubeconfig-path))
	kubectl cluster-info

#.PHONY: deploy-minikube
#deploy-minikube: install-minikube
#	sudo minikube start --kubernetes-version=v$(K8S_VERSION)
#	sudo minikube update-context

.PHONY: get-kube-creds
get-kube-creds:
	$(eval export CLUSTER_NAME=$(shell gcloud container clusters list | awk 'NR==2 {print $$1}'))
	gcloud container clusters get-credentials $(CLUSTER_NAME) --zone us-central1-a
	kubectl cluster-info

.PHONY: deploy-iofog-%
deploy-iofog-%: get-kube-creds deploy-%
	$(eval PORT=$(shell kubectl cluster-info | head -n 1 | cut -d ":" -f 3 | sed 's/[^0-9]*//g' | rev | cut -c 2- | rev))
	sed 's/<<PORT>>/"$(PORT)"/g' deploy/operator.yml.tmpl > deploy/operator.yml
	@for SVC in $(SVCS) ; do \
		kubectl create -f deploy/$$SVC.yml ; \
	done

.PHONY: append-agent-host
append-agent-host:
	terraform output ip >> ./deploy/ansible/hosts
	#echo "127.0.0.1" >> ./deploy/ansible/hosts

.PHONY: deploy-agent
deploy-agent: install-ansible append-agent-host
	ANSIBLE_CONFIG=./deploy/ansible ansible --version
	ANSIBLE_CONFIG=./deploy/ansible ansible-playbook -i deploy/ansible/hosts deploy/ansible/iofog-agent.yml


# Teardown targets
.PHONY: rm-gcp
rm-gcp: gen-creds-gcp
	terraform destroy -auto-approve deploy/gcp 

.PHONY: rm-kind
rm-kind:
	kind delete cluster

.PHONY: rm-minikube
rm-minikube:
	sudo minikube stop
	sudo minikube delete

.PHONY: rm-iofog
rm-iofog:
	@for SVC in $(SVCS) ; do \
		kubectl delete -f deploy/$$SVC.yml ; \
	done

# Util targets
.PHONY: test
test:
	@echo 'TODO: Write system tests :)'

.PHONY: push-imgs
push-imgs:
	@echo 'TODO :)'
#	@echo $(DOCKER_PASS) | docker login -u $(DOCKER_USER) --password-stdin
#	for IMG in $(IOFOG_IMGS) ; do \
#		docker push $(IMAGE):$(TAG) ; \
#	done

.PHONY: list help
.DEFAULT_GOAL := help
list: ## List all make targets
	@$(MAKE) -pRrn : -f $(MAKEFILE_LIST) 2>/dev/null | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | egrep -v -e '^[^[:alnum:]]' -e '^$@$$' | sort
help:
	@grep -h -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

# Variable outputting/exporting rules
var-%: ; @echo $($*)
varexport-%: ; @echo $*=$($*)
