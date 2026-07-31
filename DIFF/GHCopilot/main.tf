provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.14.2"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.3.0/24", "10.0.4.0/24"]
  database_subnets = ["10.0.5.0/24", "10.0.6.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnets" {
  value = module.vpc.public_subnets
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "database_subnets" {
  value = module.vpc.database_subnets
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "8.0.0"

  name               = "my-alb"
  load_balancer_type = "application"
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets

  security_groups = [module.alb_sg.security_group_id]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      action_type        = "redirect"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  ]

  https_listeners = [
    {
      port               = 443
      protocol           = "HTTPS"
      ssl_policy         = "ELBSecurityPolicy-2016-08"
      certificate_arn    = data.aws_acm_certificate.example.arn
      default_action_type = "fixed-response"
      default_action_fixed_response = {
        content_type = "text/plain"
        message_body = "Not Found"
        status_code  = "404"
      }
    }
  ]

  target_groups = [
    {
      name_prefix      = "tg1"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
      health_check = {
        path                = "/"
        interval            = 30
        timeout             = 5
        healthy_threshold   = 2
        unhealthy_threshold = 2
      }
    },
    {
      name_prefix      = "tg2"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
      health_check = {
        path                = "/"
        interval            = 30
        timeout             = 5
        healthy_threshold   = 2
        unhealthy_threshold = 2
      }
    },
    {
      name_prefix      = "tg3"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
      health_check = {
        path                = "/"
        interval            = 30
        timeout             = 5
        healthy_threshold   = 2
        unhealthy_threshold = 2
      }
    },
    {
      name_prefix      = "tg4"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
      health_check = {
        path                = "/"
        interval            = 30
        timeout             = 5
        healthy_threshold   = 2
        unhealthy_threshold = 2
      }
    }
  ]

  https_listeners_rules = [
    {
      action = {
        type             = "forward"
        target_group_arn = module.alb.target_group_arn["tg1"]
      }
      condition = {
        host_header = {
          values = ["host1.example.com"]
        }
      }
    },
    {
      action = {
        type             = "forward"
        target_group_arn = module.alb.target_group_arn["tg2"]
      }
      condition = {
        host_header = {
          values = ["host2.example.com"]
        }
      }
    },
    {
      action = {
        type             = "forward"
        target_group_arn = module.alb.target_group_arn["tg3"]
      }
      condition = {
        host_header = {
          values = ["host3.example.com"]
        }
      }
    },
    {
      action = {
        type             = "forward"
        target_group_arn = module.alb.target_group_arn["tg4"]
      }
      condition = {
        host_header = {
          values = ["host4.example.com"]
        }
      }
    }
  ]

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

data "aws_acm_certificate" "example" {
  domain   = "example.com"
  statuses = ["ISSUED"]
}

module "alb_sg" {
  source = "terraform-aws-modules/security-group/aws//modules/http-https"
  version = "4.0.0"

  name        = "alb-sg"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for ALB"

  ingress_cidr_blocks = ["0.0.0.0/0"]
  egress_cidr_blocks  = ["0.0.0.0/0"]
}