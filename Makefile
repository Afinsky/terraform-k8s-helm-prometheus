#---------------------------
# Makefile
#---------------------------

SHELL := $(shell which bash) # set a default shell

# TODO: Implement `install` command via mise/asdf for all tools (terraform, terraform-docs, pre-commit, helm, kubectl, etc)

help: ## Show Help
	@grep '^[a-zA-Z]' $(MAKEFILE_LIST) | \
		sort | \
		awk -F ':.*?## ' 'NF==2 {printf "\033[36m  %-25s\033[0m %s\n", $$1, $$2}'

update-context: ## Update kubeconfig context for the cluster
	aws eks update-kubeconfig --name dev-me-k8s-cluster --region us-east-1 --profile terraform

# ----------------------------------------------------------------
# Terraform commands
# ----------------------------------------------------------------

plan apply output validate providers console refresh destroy: ## Run terraform commands
	terraform -chdir=./environments/develop/ $@ \
		-var-file=develop.tfvars

# ----------------------------------------------------------------
# Utils
# ----------------------------------------------------------------

pre-commit: ## Run pre-commit hooks
	pre-commit run --all-files

clean: ## Clean up cache directories
	find . -type d -name '.terraform' | xargs rm -rf

rm-lock-file: ## Force provider update by removing the lock file
	find .  -name '.terraform.lock.hcl' | xargs rm -rf
