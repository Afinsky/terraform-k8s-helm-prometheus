#---------------------------
# Makefile
#---------------------------

SHELL := $(shell which bash) # set default shell

# ACCOUNT selects which accounts/<alias>/us-east-1 tree a layer target resolves against. Every layer
# is a unit generated from that account's terragrunt.stack.hcl (templates in units/): identity-center
# only in abotyan001 (the default), eks-cluster/eks-workloads only in workload accounts.
# eg make identity-center apply                -> accounts/abotyan001/us-east-1/.terragrunt-stack/identity-center
# eg make ACCOUNT=workloads-dev eks-cluster apply -> accounts/workloads-dev/us-east-1/.terragrunt-stack/eks-cluster
ACCOUNT ?= abotyan001
REGION := us-east-1
ACCOUNT_DIR := accounts/$(ACCOUNT)/$(REGION)

LOCK_ID :=

PORTAL_URL := https://abatsian.awsapps.com/start
SSO_REGION := us-east-1

.DEFAULT: help # Running Make will run the help target

.PHONY: help
help: ## Show Help
	@grep '^[a-zA-Z0-9]' $(MAKEFILE_LIST) | \
		sort | \
		awk -F ':.*?## ' 'NF==2 {printf "\033[36m  %-30s\033[0m %s\n", $$1, $$2}'

.PHONY: accounts
accounts: ## list ACCOUNT=<alias> values this repo knows, their AWS account ID, and their layers
	@for dir in accounts/*/; do \
		alias=$$(basename "$$dir"); \
		id=$$(grep -oE 'aws_account_id[[:space:]]*=[[:space:]]*"[^"]*"' "$$dir/account.hcl" 2>/dev/null | grep -oE '"[^"]*"' | tr -d '"'); \
		layers=$$(sed -nE 's/^unit "([^"]+)".*/\1/p' "$${dir}$(REGION)/terragrunt.stack.hcl" 2>/dev/null | sort | tr '\n' ' '); \
		printf "\033[36m  %-20s\033[0m %-20s %s\n" "$$alias" "$${id:-?}" "$$layers"; \
	done

# ----------------------------------------------------------------
# usage:
#
# make setup                    - install terraform/terragrunt/etc via mise
# make login                    - log into AWS via aws-sso-util
# make <layer> <command>        - run a Terragrunt command against one layer
# make eks-workloads bootstrap-crds - first apply of eks-workloads on a fresh account only:
#                                  installs external-secrets' CRDs before a normal plan/apply
#                                  can succeed (see the target's own comment below for why)
# make run-all-plan             - plan every layer
# make run-all-apply            - apply every layer (eks-cluster before eks-workloads)
# make run-all-destroy          - destroy every layer (eks-workloads before eks-cluster)
# make destroy-safe             - like run-all-destroy for the eks-* pair, but waits for
#                                  eks-workloads' load balancers to actually clear first
# ACCOUNT=<alias>               - target a member account instead of abotyan001 (default)
#
# eg make identity-center apply
# eg make ACCOUNT=workloads-dev eks-cluster plan
# eg make ACCOUNT=workloads-dev eks-workloads apply
# eg make ACCOUNT=workloads-dev destroy-safe
# eg make ACCOUNT=workloads-dev eks-workloads bootstrap-crds
# ----------------------------------------------------------------

# prek install bakes the absolute path of the prek binary (a versioned mise install dir) into
# .git/hooks/{pre-commit,commit-msg}, falling back to `prek` on PATH - so re-run it after every
# prek bump in mise.toml, or commits break once the old version is pruned.
setup: ## install terraform/terragrunt/tflint/etc pinned in mise.toml, then the prek Git hooks
	mise install
	mise exec -- prek install --force

#----------------------------------------------------------
# Linting
#----------------------------------------------------------
.PHONY: lint
lint: ## run all pre-commit hooks across the repo (via prek)
	mise exec -- prek run --all-files --show-diff-on-failure

# ----------------------------------------------------------------
# login
# Use aws-sso-util
# https://github.com/benkehoe/aws-sso-util
# ----------------------------------------------------------------
login: ## aws-sso-util login
	mise exec -- aws-sso-util login --sso-start-url $(PORTAL_URL) --sso-region $(SSO_REGION)

logout: ## aws-sso-util logout
	mise exec -- aws-sso-util logout
# ----------------------------------------------------------------
# Terragrunt layers
#
# There's no bootstrap layer for the S3 state bucket — --backend-bootstrap below makes Terragrunt
# create it itself (versioned, encrypted, public access blocked) the first time it's missing.
# See root.hcl's remote_state block.
# ----------------------------------------------------------------
.PHONY: stacks identity-center eks-cluster eks-workloads

# Every account's stack, not just $(ACCOUNT)'s: each workload account's eks-* units depend on
# abotyan001's generated .terragrunt-stack/identity-center. Regenerating before every run keeps
# edits to stack files or units/ from going stale, and costs nothing: generate leaves each unit's
# .terragrunt-cache alone, so nothing is re-downloaded.
# Generate never removes a unit the stack file no longer declares (renamed or dropped), and
# `run --all` would still run that leftover - against the same state key as its renamed twin -
# so prune any generated dir whose name isn't one of the stack file's unit `path`s.
stacks: ## generate every account's terragrunt.stack.hcl into its .terragrunt-stack/ (runs automatically)
	@for stack in accounts/*/*/terragrunt.stack.hcl; do \
		dir=$$(dirname "$$stack"); \
		terragrunt stack generate --working-dir "$$dir" --non-interactive --log-level warn || exit 1; \
		declared=$$(sed -nE 's/^  path[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$$stack"); \
		for unit in "$$dir"/.terragrunt-stack/*/; do \
			[ -d "$$unit" ] || continue; \
			printf '%s\n' "$$declared" | grep -qxF "$$(basename "$$unit")" || { echo "removing stale $$unit (not declared in $$stack)"; rm -rf "$$unit"; }; \
		done; \
	done

# $(call stack-unit,<unit>) - point LAYER at <unit> generated from $(ACCOUNT_DIR)/terragrunt.stack.hcl
define stack-unit
$(eval LAYER = $(ACCOUNT_DIR)/.terragrunt-stack/$(1))
$(eval STACK_UNIT_DIR = $(ACCOUNT_DIR)/.terragrunt-stack/$(1))
@test -d $(LAYER) || { echo "$(ACCOUNT_DIR)/terragrunt.stack.hcl declares no $(1) unit - pass the ACCOUNT=<alias> that has it, see make accounts"; exit 1; }
endef

# $(call sync-locks,<generated unit dirs>) - Terragrunt writes a unit's lock file back into its working
# dir after init, which for a stack unit is the gitignored .terragrunt-stack/<unit>/ - and the next
# generate overwrites it there from units/<unit>/. Copy whatever init changed (provider upgrade, new
# platform hashes) on to units/<unit>/, the copy that's committed and shared by every account.
define sync-locks
@for dir in $(1); do \
	lock="$$dir/.terraform.lock.hcl"; dest="units/$$(basename "$$dir")/.terraform.lock.hcl"; \
	[ ! -f "$$lock" ] || cmp -s "$$lock" "$$dest" || { cp "$$lock" "$$dest"; echo "synced $$lock -> $$dest"; }; \
done
endef

identity-center: stacks ## AWS Organization, IAM Identity Center users/groups/permission sets - management account (default ACCOUNT)
	$(call stack-unit,identity-center)

eks-cluster: stacks ## VPC, EKS control plane/node groups, ACM (pure AWS, no k8s resources) - needs ACCOUNT=<workload account>
	$(call stack-unit,eks-cluster)

eks-workloads: stacks ## ingress-nginx, external-dns/-secrets, lb-controller, sample apps - depends on eks-cluster, needs ACCOUNT=<workload account>
	$(call stack-unit,eks-workloads)

# ----------------------------------------------------------------
# Terragrunt commands
# usage: make <layer> <command>, e.g. make ACCOUNT=workloads-dev eks-cluster plan
# ----------------------------------------------------------------
plan apply init output validate refresh import destroy:
	terragrunt $@ \
		--working-dir ./$(LAYER) \
		--non-interactive \
		--backend-bootstrap
	$(call sync-locks,$(STACK_UNIT_DIR))

state-list: ## make <layer> state-list
	terragrunt state list \
		--working-dir ./$(LAYER) \
		--non-interactive \
		--backend-bootstrap
	$(call sync-locks,$(STACK_UNIT_DIR))

# console/providers/etc have no terragrunt shortcut — run them via `terragrunt run -- <cmd>`
# eg make ACCOUNT=workloads-dev eks-cluster cmd CMD=console
cmd: ## make <layer> cmd CMD="console"
	terragrunt run \
		--working-dir ./$(LAYER) \
		--non-interactive \
		--backend-bootstrap \
		-- $(CMD)
	$(call sync-locks,$(STACK_UNIT_DIR))

debug-plan: ## make <layer> debug-plan
	terragrunt plan \
		--working-dir ./$(LAYER) \
		--non-interactive \
		--backend-bootstrap \
		--log-level debug
	$(call sync-locks,$(STACK_UNIT_DIR))

debug-apply: ## make <layer> debug-apply
	terragrunt apply \
		--working-dir ./$(LAYER) \
		--non-interactive \
		--backend-bootstrap \
		--log-level debug
	$(call sync-locks,$(STACK_UNIT_DIR))

# kubernetes_manifest (hashicorp/kubernetes provider) queries the live API
# server for a resource's GroupVersionKind at PLAN time, not apply time -
# depends_on can't help here. On a brand-new cluster, external-secrets.tf's
# ClusterSecretStore and app.tf's ExternalSecret (both external-secrets CRDs)
# fail every plan/apply with "no matches for kind ... (CRD may not be
# installed)" until the chart that owns those CRDs is actually installed.
# Run this once, targeting only the helm_release that installs the CRDs,
# before the first `plan`/`apply` of eks-workloads on a fresh account -
# after that, CRDs exist and normal plan/apply works unmodified.
bootstrap-crds: ## make eks-workloads bootstrap-crds ACCOUNT=<alias> - first-apply only, installs external-secrets' CRDs
	terragrunt apply \
		--working-dir ./$(LAYER) \
		--non-interactive \
		--backend-bootstrap \
		-target=helm_release.external_secrets
	$(call sync-locks,$(STACK_UNIT_DIR))

# `run --all` regenerates $(ACCOUNT_DIR)'s own stack itself, but not abotyan001's, which the eks-*
# units depend on from outside $(ACCOUNT_DIR) - hence the stacks prerequisite
run-all-plan: stacks ## plan every layer under $(ACCOUNT_DIR)
	terragrunt run --all plan \
		--working-dir ./$(ACCOUNT_DIR) \
		--non-interactive \
		--backend-bootstrap
	$(call sync-locks,$(ACCOUNT_DIR)/.terragrunt-stack/*)

run-all-apply: stacks ## apply every layer under $(ACCOUNT_DIR)
	terragrunt run --all apply \
		--working-dir ./$(ACCOUNT_DIR) \
		--non-interactive \
		--backend-bootstrap
	$(call sync-locks,$(ACCOUNT_DIR)/.terragrunt-stack/*)

force-unlock: ## make <layer> force-unlock LOCK_ID=<id>
	terragrunt force-unlock \
		--working-dir ./$(LAYER) \
		--non-interactive \
		--backend-bootstrap \
		$(LOCK_ID)

aws-sso-configure-populate: ## aws-sso-util configure populate (creates ~/.aws/config entries for all accounts)
	mise exec -- aws-sso-util configure populate \
  		--sso-start-url $(PORTAL_URL) \
  		--sso-region $(SSO_REGION) \
  		--region $(REGION) \
  		--components account_name,role_name \
  		--separator '.'


# ----------------------------------------------------------------
# utils
# ----------------------------------------------------------------
clean: ## remove .terragrunt-cache, .terraform and generated .terragrunt-stack dirs
	find . -type d -name '.terragrunt-cache' | xargs rm -rf
	find . -type d -name '.terraform' | xargs rm -rf
	find . -type d -name '.terragrunt-stack' -prune | xargs rm -rf
	find . -type d -name '.pre-commit-trivy-cache' | xargs rm -rf

force-provider-update: ## delete all .terraform.lock.hcl files (forces provider refresh)
	find . -name '.terraform.lock.hcl' | xargs rm -f

list: ## list mise-installed tools and their versions
	mise ls --current
