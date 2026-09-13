resource "aws_ecr_repository" "this" {
  for_each             = toset([local.project_name])
  name                 = each.key
  image_tag_mutability = "MUTABLE"
  tags = {
    Name = "${local.project_name}-${var.environment}-ecr"
  }
}
