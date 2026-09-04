#------------------------------------------------------------------
# floci-aws-demo
#------------------------------------------------------------------
# The interface. Everything below drives Terragrunt across five stacks
# (bootstrap -> iam -> stateful -> standard) against a local floci emulator.
#------------------------------------------------------------------

.DEFAULT_GOAL := help
SHELL := /bin/bash

TG_DIR          ?= terragrunt/aws
STACKS          ?= bootstrap iam stateful standard
CLIENT_NAME     ?= msdemo
ENVIRONMENT_NAME?= dev
FLOCI_ENDPOINT  ?= http://localhost:4566

# Terragrunt 1.x defaults to OpenTofu; this project targets Terraform.
export TG_TF_PATH            ?= terraform
export AWS_ACCESS_KEY_ID     ?= test
export AWS_SECRET_ACCESS_KEY ?= test
export AWS_DEFAULT_REGION    ?= us-east-1
export CLIENT_NAME
export ENVIRONMENT_NAME
export TF_PLUGIN_CACHE_DIR   ?= $(HOME)/.terraform.d/plugin-cache

TG := terragrunt --non-interactive

##@ General

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} \
	/^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 } \
	/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
	@echo

check-floci: ## Fail fast if floci is not reachable
	@curl -s -m 5 "$(FLOCI_ENDPOINT)/_localstack/health" >/dev/null 2>&1 \
		|| { echo "floci is not reachable at $(FLOCI_ENDPOINT) -- run: docker compose up -d" >&2; exit 1; }
	@echo "floci is up at $(FLOCI_ENDPOINT)"

##@ Code Quality

fmt: ## Format all Terraform and Terragrunt files
	@terraform fmt -recursive terraform/
	@$(TG) hcl format --working-dir $(TG_DIR) 2>/dev/null || true
	@echo "formatted"

validate: ## Validate every module and composite
	@mkdir -p $(TF_PLUGIN_CACHE_DIR)
	@for d in terraform/modules/*/; do \
		printf '  %-24s ' "$$(basename $$d)"; \
		( cd $$d && terraform init -backend=false -input=false >/dev/null 2>&1 \
			&& terraform validate 2>&1 | grep -oE "Success!|Error" | head -1 ); \
	done

##@ Selected Stacks
#
#   make plan  STACK=stateful               one stack
#   make plan  STACK="stateful standard"    several, in the order given
#   make plan-all                           all four, in dependency order
#
# Valid names: bootstrap  iam  stateful  standard

STACK ?= bootstrap

# Guard against `STACK=a,b` and `STACK=a|b` -- both are easy to reach for and
# neither is valid, so say so rather than failing on a missing directory.
define check_stack
	@for s in $(STACK); do \
		case "$$s" in *,*|*\|*) \
			echo "STACK names are space-separated: STACK=\"stateful standard\"" >&2; exit 1 ;; \
		esac; \
		[ -f "$(TG_DIR)/$$s/terragrunt.hcl" ] || { \
			echo "unknown stack '$$s' -- expected one of: $(STACKS)" >&2; exit 1; }; \
	done
endef

plan: check-floci ## Plan the selected stack(s) — STACK="stateful standard"
	$(check_stack)
	@for s in $(STACK); do echo "=== plan $$s ==="; $(TG) plan --working-dir $(TG_DIR)/$$s; done

apply: check-floci ## Apply the selected stack(s)
	$(check_stack)
	@for s in $(STACK); do echo "=== apply $$s ==="; $(TG) apply --working-dir $(TG_DIR)/$$s; done

destroy: check-floci ## Destroy the selected stack(s)
	$(check_stack)
	@for s in $(STACK); do echo "=== destroy $$s ==="; $(TG) destroy --working-dir $(TG_DIR)/$$s; done

output: ## Show the selected stack's outputs
	$(check_stack)
	@for s in $(STACK); do $(TG) output --working-dir $(TG_DIR)/$$s; done

##@ All Stacks

plan-all: check-floci ## Plan every stack in dependency order
	@$(TG) run --all plan --working-dir $(TG_DIR) --provider-cache

apply-all: check-floci ## Apply every stack in dependency order
	@$(TG) run --all apply --working-dir $(TG_DIR) --provider-cache

destroy-all: check-floci ## Destroy every stack in reverse order
	@$(TG) run --all destroy --working-dir $(TG_DIR) --provider-cache

outputs: ## Merge all stack outputs into .outputs.json for the scripts
	@./scripts/lib/outputs.sh --refresh
	@echo "wrote .outputs.json"

##@ Application

images: ## Build the four service images and push to floci ECR
	@./scripts/build-and-push.sh

deploy: ## Render config, apply manifests, roll out to the emulated EKS
	@./scripts/deploy.sh

targets: ## Register the gateway NodePort with the ALB target group
	@./scripts/register-alb-targets.sh

frontend: ## Inject the ALB DNS into the frontend and sync to S3
	@./scripts/deploy-frontend.sh

verify: ## Run the functional verification suite
	@./verify.sh

##@ Platform

kubeconfig: ## Point kubectl at the emulated EKS cluster (needed before the Helm releases)
	@aws eks update-kubeconfig --name $(CLIENT_NAME)-cluster \
		--region $(AWS_DEFAULT_REGION) --endpoint-url $(FLOCI_ENDPOINT)
	@./scripts/fix-kubeconfig.sh $(CLIENT_NAME)-cluster 2>/dev/null || true

vault-status: ## Show Vault's seal status
	@pod=$$(kubectl get pod -n vault -l app.kubernetes.io/name=vault \
		-o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$pod" ]; then echo "  no vault pod found"; else \
		kubectl exec -n vault "$$pod" -- vault status || true; fi

vault-token: ## Print the Vault root token from Secrets Manager
	@aws --endpoint-url $(FLOCI_ENDPOINT) secretsmanager get-secret-value \
		--secret-id msdemo-vault-root-token --query SecretString --output text

vault-ui: ## Port-forward the Vault UI to localhost:8200
	@svc=$$(kubectl get svc -n vault -l app.kubernetes.io/name=vault \
		-o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$svc" ]; then echo "  no vault service found"; exit 1; fi; \
	echo "http://localhost:8200"; kubectl port-forward -n vault "svc/$$svc" 8200:8200

argocd-sync: ## Show the ArgoCD application status
	@kubectl get application -n argocd msdemo \
		-o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision \
		2>/dev/null || echo "  no Application yet -- has 'make apply STACK=standard' run?"

argocd-refresh: ## Force ArgoCD to re-read git and reconcile now
	@kubectl -n argocd annotate application msdemo \
		argocd.argoproj.io/refresh=hard --overwrite >/dev/null
	@echo "refresh requested; watch with: make argocd-sync"

argocd-password: ## Print the ArgoCD admin password from Secrets Manager
	@aws --endpoint-url $(FLOCI_ENDPOINT) secretsmanager get-secret-value \
		--secret-id msdemo/argocd-admin --query SecretString --output text

argocd-ui: ## Port-forward the ArgoCD UI to localhost:8080
	@svc=$$(kubectl get svc -n argocd -l app.kubernetes.io/name=argocd-server \
		-o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$svc" ]; then echo "  no argocd-server service found"; exit 1; fi; \
	echo "http://localhost:8080  (user: admin)"; kubectl port-forward -n argocd "svc/$$svc" 8080:80

##@ Lifecycle

# On a cold start the cluster does not exist when `standard` first runs, so its
# Helm releases fail. kubeconfig + a second apply-all settles it.
up: apply-all kubeconfig apply-all outputs images deploy targets frontend ## Full build from nothing
	@echo ""
	@echo "Stack is up. Exercise it end to end:"
	@echo "  ALB=\$$(./scripts/lib/outputs.sh alb_dns_name)"
	@echo "  curl -s -X POST \"http://\$$ALB/api/orders\" -H 'Content-Type: application/json' \\"
	@echo "    -d '{\"user_id\":1,\"item\":\"widget\",\"amount_cents\":4200}'"

down: destroy-all ## Tear everything down
	@echo "destroyed"

clean: ## Remove generated files and caches (not state)
	@find $(TG_DIR) -name '.terragrunt-cache' -type d -prune -exec rm -rf {} + 2>/dev/null || true
	@find $(TG_DIR) -name '.tfplan' -type d -prune -exec rm -rf {} + 2>/dev/null || true
	@rm -f .outputs.json k8s/01-config.yaml
	@echo "cleaned"

.PHONY: help check-floci fmt validate plan apply destroy output \
        plan-all apply-all destroy-all outputs images deploy targets \
        frontend verify up down clean vault-status vault-token vault-ui \
        argocd-sync argocd-refresh argocd-password argocd-ui kubeconfig
