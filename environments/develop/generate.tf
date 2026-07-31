  #$ terraform plan -generate-config-out=generate.tf

import {
  id = "AmazonEKSLoadBalancerControllerRole" #arn:aws:iam::242906888793:role/
  to = aws_iam_role.controller_role
}