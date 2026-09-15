# Same formula as modules/eks-cluster/locals.tf, duplicated rather than
# shared - these two modules are separate Terraform configurations (no
# module-to-module reference is possible across a Terragrunt dependency
# boundary), and the formula is one line, not worth a third shared module
# just to avoid repeating it. Only project_name/prefix are actually used
# here (the AWS resources that used common_tags/resource_name - module.eks,
# module.vpc, the ACM module - stayed in modules/eks-cluster).
locals {
  project_name = "me"
  prefix       = "${local.project_name}-${var.environment}-${var.region}"
}
