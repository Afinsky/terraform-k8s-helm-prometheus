# Named independently of local.project_name on purpose: an ECR repository
# name can't be changed in place - renaming it means Terraform destroys the
# old one and creates a new one under the new name. Kept as its own local so
# a future project_name change (a tags/descriptions-only, in-place update)
# never risks dropping this repository's images as a side effect.
locals {
  ecr_repository_name = "eks-access"
}

resource "aws_ecr_repository" "this" {
  for_each             = toset([local.ecr_repository_name])
  name                 = each.key
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    Name = "${local.ecr_repository_name}-${var.environment}-ecr"
  }
}
