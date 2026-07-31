provider "aws" {
  region = "us-east-1"  # Change this to your desired region
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"  # Change this to the latest version if necessary

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]  # Two availability zones
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]
  database_subnets = ["10.0.5.0/24", "10.0.6.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = false  # Set to false to have a NAT Gateway per AZ

  public_subnet_tags = {
    Name = "public-subnet"
  }

  private_subnet_tags = {
    Name = "private-subnet"
  }

  database_subnet_tags = {
    Name = "database-subnet"
  }

  tags = {
    Name = "my-vpc"
  }
}


# Import ACM Certificate
resource "aws_acm_certificate" "my_cert" {
  domain_name       = "your-domain.com"  # Change to your domain name
  validation_method = "DNS"  # Or use EMAIL if appropriate

  lifecycle {
    create_before_destroy = true
  }
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "9.0.0"  # Replace with the latest version as needed

  name               = "my-alb"
  load_balancer_type = "application"
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets

  security_groups    = [aws_security_group.alb_sg.id]  # Security group ID

  http_tcp_listeners = [{
    port               = 80
    protocol           = "HTTP"
    default_action_type = "redirect"
    redirect = {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }]

  https_listeners = [{
    port               = 443
    protocol           = "HTTPS"
    ssl_policy         = "ELBSecurityPolicy-2016-08"
    certificate_arn    = aws_acm_certificate.my_cert.arn
    default_action_type = "fixed-response"
    default_action_fixed_response = {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }]

  target_groups = [
    {
      name_prefix = "tg1"
      backend_protocol = "HTTP"
      target_type = "instance"
      health_check = {
        path                = "/"
        matcher             = "200"
        interval            = 30
      }
      port = 80
    },
    {
      name_prefix = "tg2"
      backend_protocol = "HTTP"
      target_type = "instance"
      health_check = {
        path                = "/"
        matcher             = "200"
        interval            = 30
      }
      port = 80
    },
    {
      name_prefix = "tg3"
      backend_protocol = "HTTP"
      target_type = "instance"
      health_check = {
        path                = "/"
        matcher             = "200"
        interval            = 30
      }
      port = 80
    },
    {
      name_prefix = "tg4"
      backend_protocol = "HTTP"
      target_type = "instance"
      health_check = {
        path                = "/"
        matcher             = "200"
        interval            = 30
      }
      port = 80
    }
  ]

  https_listener_rules = [
    {
      action_type = "forward"
      priority    = 100
      host_header = {
        values = ["host1.your-domain.com"]
      }
      target_group_index = 0
    },
    {
      action_type = "forward"
      priority    = 101
      host_header = {
        values = ["host2.your-domain.com"]
      }
      target_group_index = 1
    },
    {
      action_type = "forward"
      priority    = 102
      host_header = {
        values = ["host3.your-domain.com"]
      }
      target_group_index = 2
    },
    {
      action_type = "forward"
      priority    = 103
      host_header = {
        values = ["host4.your-domain.com"]
      }
      target_group_index = 3
    }
  ]

  tags = {
    Name = "my-alb"
  }
}

# Security group for the ALB
resource "aws_security_group" "alb_sg" {
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
  }
}
