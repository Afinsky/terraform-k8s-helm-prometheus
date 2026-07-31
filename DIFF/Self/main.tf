module "vpc" {
  source = "github.com/terraform-aws-modules/terraform-aws-vpc?ref=v5.1.1"

  name                          = local.VPC.csai.name
  create_database_subnet_group  = false
  manage_default_route_table    = false
  manage_default_security_group = false
  enable_dns_hostnames          = false
  map_public_ip_on_launch       = true
  #Note that the order of the list of availability zones is associated with the order of the list of subnets
  cidr             = local.VPC.csai.cidr
  azs              = local.VPC.csai.azs
  private_subnets  = local.VPC.csai.private_subnets
  public_subnets   = local.VPC.csai.public_subnets
  database_subnets = local.VPC.csai.database_subnets

  enable_nat_gateway = true

  manage_default_network_acl = true
  default_network_acl_name   = local.VPC.csai.default_network_acl_name

  default_network_acl_ingress = [
    {
      rule_no    = 100
      action     = "allow"
      from_port  = 0
      to_port    = 0
      protocol   = "-1"
      cidr_block = "0.0.0.0/0"
    }
  ]

  default_network_acl_egress = [
    {
      rule_no    = 100
      action     = "allow"
      from_port  = 0
      to_port    = 0
      protocol   = "-1"
      cidr_block = "0.0.0.0/0"
    }
  ]

  enable_flow_log                                 = local.VPC.csai.enable_flow_log
  create_flow_log_cloudwatch_log_group            = local.VPC.csai.enable_flow_log
  create_flow_log_cloudwatch_iam_role             = local.VPC.csai.enable_flow_log
  flow_log_cloudwatch_log_group_retention_in_days = local.VPC.csai.flow_log_cloudwatch_log_group_retention_in_days
  flow_log_traffic_type                           = "ALL"
  flow_log_cloudwatch_log_group_name_prefix       = local.VPC.csai.flow_log_cloudwatch_log_group_name_prefix

  vpc_flow_log_tags = merge({ Name = local.resource_name }, local.common_tags)
  tags              = merge(local.common_tags)
}

module "alb" {
  source = "github.com/terraform-aws-modules/terraform-aws-alb?ref=v8.7.0"

  enable_deletion_protection = var.environment == "prod" ? true : false
  name                       = local.ALB.csai.name
  load_balancer_type         = "application"
  vpc_id                     = module.vpc.vpc_id
  subnets                    = module.vpc.public_subnets
  security_groups            = [module.alb_sg.security_group_id]
  idle_timeout               = 60 #Seconds
  enable_xff_client_port     = false
  create_security_group      = false

  target_groups = [
    {
      name = local.TARGET_GROUP.csai.site_crawler.name
      health_check = {
        path                = "/"
        healthy_threshold   = 3
        unhealthy_threshold = 5
        matcher             = "200"
        interval            = local.TARGET_GROUP.csai.site_crawler.interval
        timeout             = local.TARGET_GROUP.csai.site_crawler.timeout
        slow_start          = local.TARGET_GROUP.csai.site_crawler.slow_start
      }
      backend_protocol     = "HTTP"
      backend_port         = 80
      target_type          = "ip"
      deregistration_delay = 300 #60
      slow_start           = 60
    },
    {
      name = local.TARGET_GROUP.csai.office365_integration.name
      health_check = {
        path                = "/"
        healthy_threshold   = 3
        unhealthy_threshold = 5
        matcher             = "200"
        interval            = local.TARGET_GROUP.csai.office365_integration.interval
        timeout             = local.TARGET_GROUP.csai.office365_integration.timeout
        slow_start          = local.TARGET_GROUP.csai.office365_integration.slow_start
      }
      backend_protocol     = "HTTP"
      backend_port         = 80
      target_type          = "ip"
      deregistration_delay = 300 #60
      slow_start           = 60
    },
    {
      name = local.TARGET_GROUP.csai.workplace_integration.name
      health_check = {
        path                = "/"
        healthy_threshold   = 3
        unhealthy_threshold = 5
        matcher             = "200"
        interval            = local.TARGET_GROUP.csai.workplace_integration.interval
        timeout             = local.TARGET_GROUP.csai.workplace_integration.timeout
        slow_start          = local.TARGET_GROUP.csai.workplace_integration.slow_start
      }
      backend_protocol     = "HTTP"
      backend_port         = 80
      target_type          = "ip"
      deregistration_delay = 300 #60
      slow_start           = 60
    },
    {
      name = local.TARGET_GROUP.csai.inbound_core.name
      health_check = {
        path                = "/"
        healthy_threshold   = 3
        unhealthy_threshold = 5
        matcher             = "404" #"200"
        interval            = local.TARGET_GROUP.csai.inbound_core.interval
        timeout             = local.TARGET_GROUP.csai.inbound_core.timeout
        slow_start          = local.TARGET_GROUP.csai.inbound_core.slow_start
      }
      backend_protocol     = "HTTP"
      backend_port         = 80
      target_type          = "ip"
      deregistration_delay = 300 #60
      slow_start           = 60
    },
    {
      name = local.TARGET_GROUP.csai.outbound_core.name
      health_check = {
        path                = "/"
        healthy_threshold   = 3
        unhealthy_threshold = 5
        matcher             = "404" #"200"
        interval            = local.TARGET_GROUP.csai.outbound_core.interval
        timeout             = local.TARGET_GROUP.csai.outbound_core.timeout
        slow_start          = local.TARGET_GROUP.csai.outbound_core.slow_start
      }
      backend_protocol     = "HTTP"
      backend_port         = 80
      target_type          = "ip"
      deregistration_delay = 300 #60
      slow_start           = 60
    }
  ]

  https_listeners = [
    {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = data.aws_acm_certificate.this.arn
      action_type     = "fixed-response"
      fixed_response = {
        content_type = "text/plain"
        status_code  = "555"
      }
    }
  ]

  http_tcp_listeners = [
    {
      port        = 80
      protocol    = "HTTP"
      action_type = "redirect"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  ]

  https_listener_rules = [
    {
      https_listener_index = 0
      priority             = 1
      actions = [{
        type               = "forward"
        target_group_index = index(module.alb.target_group_names, local.TARGET_GROUP.csai.site_crawler.name)
      }]

      conditions = [{ host_headers = [local.site_crawler_domain_name] }]
    },
    {
      https_listener_index = 0
      priority             = 2
      actions = [{
        type               = "forward"
        target_group_index = index(module.alb.target_group_names, local.TARGET_GROUP.csai.office365_integration.name)
      }]

      conditions = [{ host_headers = [local.office365_integration_domain_name] }]
    },
    {
      https_listener_index = 0
      priority             = 3
      actions = [{
        type               = "forward"
        target_group_index = index(module.alb.target_group_names, local.TARGET_GROUP.csai.workplace_integration.name)
      }]

      conditions = [{ host_headers = [local.workplace_integration_domain_name] }]
    },
    {
      https_listener_index = 0
      priority             = 4
      actions = [{
        type               = "forward"
        target_group_index = index(module.alb.target_group_names, local.TARGET_GROUP.csai.inbound_core.name)
      }]

      conditions = [{ host_headers = [local.inbound_core_domain_name] }]
    },
    {
      https_listener_index = 0
      priority             = 5
      actions = [{
        type               = "forward"
        target_group_index = index(module.alb.target_group_names, local.TARGET_GROUP.csai.outbound_core.name)
      }]

      conditions = [{ host_headers = [local.outbound_core_domain_name] }]
    }
  ]

  #access_logs = { bucket = module.alb_logs_s3.s3_bucket_id }
  tags = merge({ Terraform = "true" }, local.common_tags)
}