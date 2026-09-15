# Named independently of local.project_name (still "eks-access-lab", used
# elsewhere for tags/descriptions) on purpose: an ECR repository name can't
# be changed in place - renaming it means Terraform destroys the old one and
# creates a new one under the new name. Scoping the "-lab-" cleanup to just
# this resource keeps that blast radius to the repository itself, instead of
# also touching every tag/description project_name feeds.
locals {
  ecr_repository_name = "eks-access"
}

resource "aws_ecr_repository" "this" {
  for_each             = toset([local.ecr_repository_name])
  name                 = each.key
  image_tag_mutability = "MUTABLE"
  tags = {
    Name = "${local.ecr_repository_name}-${var.environment}-ecr"
  }
}
