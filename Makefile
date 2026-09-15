#---------------------------
# Makefile
#---------------------------

SHELL := $(shell which bash) # set default shell

# ACCOUNT selects which accounts/<alias>/us-east-1 tree a layer target resolves against.
# eg make eks-cluster apply                      -> accounts/abotyan001/us-east-1/eks-cluster
# eg make ACCOUNT=workloads-dev eks-cluster apply -> accounts/workloads-dev/us-east-1/eks-cluster
ACCOUNT ?= abotyan001
ACCOUNT_DIR := accounts/$(ACCOUNT)/us-east-1

# aws sso login profile. Only "01-identity-center" (and future consumer stacks) use it —
# see modules/identity-center/provider.tf for why "terraform"
# (a static IAM user) is used instead everywhere the lab-admin SSO role isn't safe to run under yet.
IAM_ROLE := lab-admin

LOCK_ID :=

.DEFAULT: help # Running Make will run the help target

.PHONY: help
help: ## Show Help
	@grep '^[a-zA-Z0-9]' $(MAKEFILE_LIST) | \
		sort | \
		awk -F ':.*?## ' 'NF==2 {printf "\033[36m  %-25s\033[0m %s\n", $$1, $$2}'

.PHONY: accounts
accounts: ## list ACCOUNT=<alias> values this repo knows, their AWS account ID, and their layers
	@for dir in accounts/*/; do \
		alias=$$(basename "$$dir"); \
		id=$$(grep -oE 'aws_account_id[[:space:]]*=[[:space:]]*"[^"]*"' "$$dir/account.hcl" 2>/dev/null | grep -oE '"[^"]*"' | tr -d '"'); \
		layers=$$(find "$$dir" -mindepth 3 -maxdepth 3 -name terragrunt.hcl | sed "s#$$dir##;s#us-east-1/##;s#/terragrunt.hcl##" | sort | tr '\n' ' '); \
		printf "\033[36m  %-16s\033[0m %-16s %s\n" "$$alias" "$${id:-?}" "$$layers"; \
	done

# ----------------------------------------------------------------
# usage:
#
# make setup                    - install terraform/terragrunt/etc via mise
# make login                    - log into AWS via AWS SSO (lab-admin profile)
# make <layer> <command>        - run a Terragrunt command against one layer
# make run-all-plan             - plan every layer
# make run-all-apply            - apply every layer (eks-cluster before eks-workloads)
# make run-all-destroy          - destroy every layer (eks-workloads before eks-cluster)
# make destroy-safe             - like run-all-destroy for the eks-* pair, but waits for
#                                  eks-workloads' load balancers to actually clear first
# ACCOUNT=<alias>               - target a member account instead of abotyan001 (default)
#
# eg make eks-cluster plan
# eg make eks-workloads apply
# eg make 01-identity-center apply
# eg make ACCOUNT=workloads-dev eks-cluster apply
# eg make ACCOUNT=workloads-dev destroy-safe
# ----------------------------------------------------------------

setup: ## install terraform/terragrunt/tflint/etc pinned in mise.toml
	mise install

#----------------------------------------------------------
# Linting
#----------------------------------------------------------
.PHONY: lint
lint: ## run all pre-commit checks across the repo
	pre-commit run --all-files

# ----------------------------------------------------------------
# login
# Use aws-sso-util
# https://github.com/benkehoe/aws-sso-util
# ----------------------------------------------------------------
login: ## aws sso login (lab-admin profile)
	aws sso login --profile $(IAM_ROLE)

# ----------------------------------------------------------------
# Terragrunt layers
#
# There's no bootstrap layer for the S3 state bucket — --backend-bootstrap below makes Terragrunt
# create it itself (versioned, encrypted, public access blocked) the first time it's missing.
# See root.hcl's remote_state block.
# ----------------------------------------------------------------
.PHONY: 01-identity-center eks-cluster eks-workloads

01-identity-center: ## AWS Organization, IAM Identity Center users/groups/permission sets
	$(eval LAYER = $(ACCOUNT_DIR)/01-identity-center)

eks-cluster: ## VPC, EKS control plane/node groups, ACM (pure AWS, no k8s resources)
	$(eval LAYER = $(ACCOUNT_DIR)/eks-cluster)

eks-workloads: ## ingress-nginx, external-dns/-secrets, lb-controller, sample apps - depends on eks-cluster
	$(eval LAYER = $(ACCOUNT_DIR)/eks-workloads)

# ----------------------------------------------------------------
# Terragrunt commands
# usage: make <layer> <command>, e.g. make eks-cluster plan
# ----------------------------------------------------------------
plan apply init output validate refresh import destroy force-unlock:
	terragrunt $@ \
		--working-dir ./$(LAYER) \
		--non-interactive \
		--backend-bootstrap

state-list: ## make <layer> state-list
	terragrunt state list \
		--working-dir ./$(LAYER) \
		--non-interactive \
		--backend-bootstrap

# console/providers/etc have no terragrunt shortcut — run them via `terragrunt run -- <cmd>`
# eg make eks-cluster cmd CMD=console
cmd: ## make <layer> cmd CMD="console"
	terragrunt run \
		--working-dir ./$(LAYER) \
		--non-interactive \
		--backend-bootstrap \
		-- $(CMD)

debug-plan: ## make <layer> debug-plan
	terragrunt plan \
		--working-dir ./$(LAYER) \
		--non-interactive \
		--backend-bootstrap \
		--log-level debug

debug-apply: ## make <layer> debug-apply
	terragrunt apply \
		--working-dir ./$(LAYER) \
		--non-interactive \
		--backend-bootstrap \
		--log-level debug

run-all-plan: ## plan every layer under $(ACCOUNT_DIR)
	terragrunt run --all plan \
		--working-dir ./$(ACCOUNT_DIR) \
		--non-interactive \
		--backend-bootstrap

run-all-apply: ## apply every layer under $(ACCOUNT_DIR)
	terragrunt run --all apply \
		--working-dir ./$(ACCOUNT_DIR) \
		--non-interactive \
		--backend-bootstrap

force-unlock: ## make <layer> force-unlock LOCK_ID=<id>
	terragrunt force-unlock \
		--working-dir ./$(LAYER) \
		--non-interactive \
		--backend-bootstrap \
		$(LOCK_ID)

# ----------------------------------------------------------------
# utils
# ----------------------------------------------------------------
clean: ## remove .terragrunt-cache and .terraform dirs
	find . -type d -name '.terragrunt-cache' | xargs rm -rf
	find . -type d -name '.terraform' | xargs rm -rf

force-provider-update: ## delete all .terraform.lock.hcl files (forces provider refresh)
	find . -name '.terraform.lock.hcl' | xargs rm -f
