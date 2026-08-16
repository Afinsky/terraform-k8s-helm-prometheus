# Terraform Resources — What They Are and Why They Exist

This document explains **every resource** created by
`terraform plan -var-file=develop.tfvars` in this environment (all 75 resources in the
plan) — networking, the EKS cluster, IAM, encryption, add-ons, and worker nodes. EKS/K8s
resources get the deepest treatment since that's the heart of this environment; VPC and
supporting resources are covered too, in less depth, so this is a complete map of what
`terraform apply` would actually build.

For each resource you'll find two angles:

- **AWS perspective** — what AWS object this actually is, and what API/service owns it.
- **K8s perspective** — why Kubernetes, as a system, needs this to exist (or, for pure
  networking resources, how it enables Kubernetes to run at all).

Source: `module "vpc"` (`main.tf`) and `module "eks"` (`eks.tf`, community module
`terraform-aws-modules/eks/aws` v20.37.1), plus resources declared directly in `eks.tf`,
`ecr.tf`, and `data.tf`.

---

## 0. Networking foundation (VPC) — the ground everything else stands on

Kubernetes doesn't create its own network from scratch on AWS — it's laid on top of a
regular VPC. These resources exist before, and independently of, EKS; EKS just consumes
them (via `subnet_ids = module.vpc.private_subnets` in `eks.tf`).

### `module.vpc.aws_vpc.this[0]`
- **AWS perspective:** The Virtual Private Cloud itself — an isolated network space
  (`10.30.0.0/16` per `develop.tfvars`) in your AWS account.
- **K8s perspective:** This is the network your entire cluster — control plane ENIs,
  nodes, and pods — lives inside. Every IP address a pod gets is carved out of this
  space.

### `module.vpc.aws_subnet.private[0]`, `[1]`
- **AWS perspective:** Two private subnets (`10.30.10.0/24`, `10.30.11.0/24`), one per
  AZ (`us-east-1c`, `us-east-1f`), with no direct route to the internet.
- **K8s perspective:** This is where your **EKS nodes** actually live
  (`subnet_ids = module.vpc.private_subnets` in `eks.tf`). Keeping nodes private means
  no worker EC2 instance has a public IP — traffic in/out goes through the NAT gateway,
  reducing attack surface.

### `module.vpc.aws_subnet.public[0]`, `[1]`
- **AWS perspective:** Two public subnets (`10.30.20.0/24`, `10.30.21.0/24`) with a
  route to the internet gateway. Tagged `kubernetes.io/role/elb = 1`.
- **K8s perspective:** That tag is a signal AWS's Load Balancer Controller looks for —
  if you later create a Kubernetes `Service` of type `LoadBalancer` (or an Ingress), AWS
  knows to place the resulting internet-facing load balancer in *these* subnets.

### `module.vpc.aws_subnet.database[0]`, `[1]`
- **AWS perspective:** Two isolated subnets (`10.30.30.0/24`, `10.30.31.0/24`) meant for
  data stores like RDS — not currently used by anything else in this plan.
- **K8s perspective:** No direct tie to the cluster today; reserved so that if you add a
  managed database later, it can live network-adjacent to your pods without being
  publicly reachable.

### `module.vpc.aws_internet_gateway.this[0]`
- **AWS perspective:** Attaches the VPC to the public internet.
- **K8s perspective:** Indirect enabler — without this, nothing in the VPC (including
  the NAT gateways nodes rely on) could reach the internet at all.

### `module.vpc.aws_eip.nat[0]`, `[1]` + `module.vpc.aws_nat_gateway.this[0]`, `[1]`
- **AWS perspective:** A static public IP (Elastic IP) and a managed NAT Gateway in each
  AZ, letting resources in private subnets initiate outbound internet connections
  without being directly reachable from the internet.
- **K8s perspective:** This is how your **private worker nodes** pull container images,
  call the EKS/ECR/CloudWatch/SSM APIs, and reach the internet generally — despite
  having no public IP themselves. Without this, `kube-proxy`/`vpc-cni` add-ons couldn't
  even download their images, and nodes would fail to bootstrap.

### `module.vpc.aws_route_table.public[0]`, `module.vpc.aws_route.public_internet_gateway[0]`, `module.vpc.aws_route_table_association.public[0]`, `[1]`
- **AWS perspective:** The routing rule set that sends public-subnet traffic destined
  for `0.0.0.0/0` out through the internet gateway, and associates it with both public
  subnets.
- **K8s perspective:** Governs how traffic from a future internet-facing load balancer
  (§ public subnets above) actually reaches the internet.

### `module.vpc.aws_route_table.private[0]`, `[1]`, `module.vpc.aws_route.private_nat_gateway[0]`, `[1]`, `module.vpc.aws_route_table_association.private[0]`, `[1]`
- **AWS perspective:** One route table per AZ, each sending private-subnet outbound
  traffic through that AZ's own NAT gateway (not a shared one — this keeps traffic
  within the AZ, avoiding cross-AZ data transfer costs), associated with the matching
  private subnet.
- **K8s perspective:** This is the actual path node/pod outbound traffic takes to reach
  the internet — it's what makes the NAT gateways above usable.

### `module.vpc.aws_route_table_association.database[0]`, `[1]`
- **AWS perspective:** Associates the database subnets with the private route tables
  (no dedicated database route table is created here).
- **K8s perspective:** No direct tie to Kubernetes.

### `module.vpc.aws_default_network_acl.this[0]`
- **AWS perspective:** Manages the VPC's auto-created default Network ACL, explicitly
  set here to allow all traffic in/out (a stateless, subnet-level firewall layered
  *underneath* security groups).
- **K8s perspective:** Kubernetes relies entirely on security groups (§4 below) for its
  network policy at the AWS layer; this NACL is deliberately left wide open so it
  doesn't add a second, harder-to-debug layer of restrictions on top.

---

## 1. Control plane — the Kubernetes "brain"

### `module.eks.aws_eks_cluster.this[0]`
- **AWS perspective:** The core EKS API object. AWS provisions and fully manages the
  Kubernetes control plane (API server, etcd, scheduler, controller-manager) across
  multiple AWS-owned instances in your VPC's subnets. You never see or patch these
  machines — that's the entire point of "managed" Kubernetes.
- **K8s perspective:** This *is* "the cluster." Every `kubectl` command, every
  Deployment, every Service — all of it talks to the API server this resource stands
  up. Without it, nothing else in this document has anything to attach to.

### `module.eks.aws_cloudwatch_log_group.this[0]`
- **AWS perspective:** A CloudWatch Logs group, retention 30 days, that the EKS control
  plane streams logs into.
- **K8s perspective:** Only the `audit` log type is enabled here (`cluster_enabled_log_types
  = ["audit"]`). Kubernetes audit logs record every request made to the API server —
  who did what, when. This is your forensic trail for "who deleted that deployment,"
  independent of anything happening inside the cluster.

### `module.eks.time_sleep.this[0]`
- **AWS perspective:** Not a real AWS resource — a Terraform-only construct that pauses
  the apply for a fixed duration.
- **K8s perspective:** IAM permission changes in AWS are eventually consistent (they can
  take a few seconds to propagate globally). This sleep exists purely so the module
  doesn't race ahead and try to use IAM permissions before AWS has finished propagating
  them. No Kubernetes concept involved — pure plumbing.

---

## 2. Encryption at rest for Kubernetes Secrets (KMS)

### `module.eks.module.kms.aws_kms_key.this[0]`
- **AWS perspective:** A customer-managed KMS encryption key, with rotation enabled.
- **K8s perspective:** Kubernetes `Secret` objects (API tokens, passwords, TLS certs
  your apps use) are stored as plain records inside etcd by default. EKS lets you layer
  **envelope encryption** on top so secrets are encrypted with your own key before
  ever touching disk. This is that key.

### `module.eks.module.kms.aws_kms_alias.this["cluster"]`
- **AWS perspective:** A human-friendly alias (`alias/eks/dev-me-k8s-cluster`) pointing
  at the key above, so you don't have to reference it by opaque key ID.
- **K8s perspective:** No direct Kubernetes concept — purely an AWS usability layer for
  the key that backs Secret encryption.

### `module.eks.module.kms.data.aws_iam_policy_document.this[0]`
- **AWS perspective:** A read-only Terraform data source that renders the JSON key
  policy (who can administer vs. use the key) — not itself a created resource.
- **K8s perspective:** N/A — this governs AWS-level access to the encryption key, not
  anything inside Kubernetes.

### `module.eks.aws_iam_policy.cluster_encryption[0]` + `module.eks.aws_iam_role_policy_attachment.cluster_encryption[0]`
- **AWS perspective:** An IAM policy granting `kms:Encrypt`/`Decrypt`/etc. on the key
  above, attached to the cluster's IAM role.
- **K8s perspective:** This is what actually lets the EKS control plane use your KMS key
  to encrypt/decrypt Secret data as it's written to and read from etcd. Without this
  attachment, the cluster couldn't use the key even though the key exists.

---

## 3. IAM role for the control plane itself

### `module.eks.aws_iam_role.this[0]` (cluster role)
- **AWS perspective:** The IAM role EKS assumes to manage AWS resources on your behalf
  — e.g., creating/attaching elastic network interfaces (ENIs) into your subnets so the
  control plane can reach your nodes.
- **K8s perspective:** Kubernetes itself has no concept of AWS IAM — this is purely the
  "service account" AWS uses so the managed control plane can act inside your AWS
  account. Every managed Kubernetes offering needs an equivalent.

### `module.eks.aws_iam_role_policy_attachment.this["AmazonEKSClusterPolicy"]`
- **AWS perspective:** AWS-managed policy giving the cluster role baseline permissions
  to manage EKS-related AWS resources (ENIs, security groups, etc.).
- **K8s perspective:** Required baseline for the control plane to function at all —
  without it, EKS can't wire the control plane into your VPC.

### `module.eks.aws_iam_role_policy_attachment.this["AmazonEKSVPCResourceController"]`
- **AWS perspective:** Grants permissions for the VPC resource controller, which manages
  ENI trunking (multiple network interfaces per EC2 instance).
- **K8s perspective:** This is what enables **security groups for pods** — a Kubernetes
  feature where individual pods can get their own AWS security group instead of
  inheriting the node's. Not exercised heavily by this config today, but required
  plumbing if you ever use that feature.

### `module.eks.aws_iam_policy.custom[0]` + `module.eks.aws_iam_role_policy_attachment.custom[0]`
- **AWS perspective:** An additional inline policy the `terraform-aws-modules/eks`
  module attaches to the cluster role to cover a few permissions AWS's managed policies
  don't include (module implementation detail, e.g. certain logging/describe calls).
- **K8s perspective:** No direct Kubernetes-facing behavior — housekeeping so the
  control plane has every AWS permission it needs to operate cleanly.

---

## 4. Security groups — the network firewall between control plane and nodes

### `module.eks.aws_security_group.cluster[0]`
- **AWS perspective:** A security group attached to the network interfaces the EKS
  control plane uses inside your VPC.
- **K8s perspective:** Defines what's allowed to reach the Kubernetes API server /
  control plane over the network.

### `module.eks.aws_security_group.node[0]`
- **AWS perspective:** A security group attached to every worker EC2 instance.
- **K8s perspective:** Defines what's allowed to reach your worker nodes — from the
  control plane, from other nodes, and from the internet/VPC.

### `module.eks.aws_security_group_rule.cluster["ingress_nodes_443"]`
- **AWS perspective:** Allows inbound HTTPS (443) from the node security group to the
  cluster security group.
- **K8s perspective:** Lets kubelet (the agent on each node) and other node-side
  processes talk to the Kubernetes API server.

### `module.eks.aws_security_group_rule.node["ingress_cluster_443"]`
- **AWS perspective:** Allows inbound HTTPS from the cluster SG to the node SG.
- **K8s perspective:** Lets the API server reach services running on nodes over HTTPS
  (e.g., some webhook or metrics endpoints).

### `module.eks.aws_security_group_rule.node["ingress_cluster_kubelet"]`
- **AWS perspective:** Allows the control plane to reach the kubelet port (10250) on
  nodes.
- **K8s perspective:** This is how the API server streams logs, execs into containers
  (`kubectl exec`/`logs`), and gets metrics directly from each node's kubelet agent. If
  this rule is missing, `kubectl logs`/`exec` fail even though the cluster looks healthy.

### `module.eks.aws_security_group_rule.node["ingress_cluster_4443_webhook"]`, `["ingress_cluster_6443_webhook"]`, `["ingress_cluster_8443_webhook"]`, `["ingress_cluster_9443_webhook"]`
- **AWS perspective:** Four rules opening specific ports from the control plane to
  nodes.
- **K8s perspective:** Kubernetes **admission webhooks** (used by things like the metrics
  server, cert-manager, or policy engines) run as pods on your nodes but get called
  *by* the API server before it accepts certain objects. These ports are the common
  defaults such webhook servers listen on. Pre-opened so that if/when you install such
  tooling later, it works without a firewall change.

### `module.eks.aws_security_group_rule.node["ingress_nodes_ephemeral"]`
- **AWS perspective:** Allows nodes to talk to each other on the OS ephemeral port
  range.
- **K8s perspective:** General pod-to-pod / node-to-node traffic (e.g., a client
  connection's return traffic) needs high ephemeral ports open between nodes.

### `module.eks.aws_security_group_rule.node["ingress_self_coredns_tcp"]` / `["ingress_self_coredns_udp"]`
- **AWS perspective:** Allows nodes to reach each other on port 53 (DNS), both TCP and
  UDP.
- **K8s perspective:** CoreDNS pods (see §6) can land on any node. This rule ensures any
  pod on any node can reach CoreDNS pods on any *other* node for DNS lookups — without
  it, in-cluster service discovery breaks intermittently depending on pod placement.

### `module.eks.aws_security_group_rule.node["egress_all"]`
- **AWS perspective:** Unrestricted outbound traffic from nodes.
- **K8s perspective:** Nodes need to reach the internet/VPC broadly — pulling container
  images, calling AWS APIs, reaching the control plane, DNS resolution, etc.

### `module.eks.aws_ec2_tag.cluster_primary_security_group["environment"|"managed_by"|"project"]`
- **AWS perspective:** EKS auto-creates one additional "primary" security group per
  cluster that Terraform doesn't directly manage; these three resources just apply your
  standard tags (`environment`, `managed_by`, `project`) onto it after the fact.
- **K8s perspective:** No Kubernetes behavior — pure AWS cost/ownership tagging hygiene.

---

## 5. Identity — who/what can act as whom

### `module.eks.data.tls_certificate.this[0]`
- **AWS perspective:** A read-only data lookup that fetches the TLS certificate
  thumbprint of your cluster's OIDC issuer URL (not a resource that gets created).
- **K8s perspective:** Needed as input to register the trust relationship below —
  AWS needs to cryptographically verify it's really EKS's OIDC endpoint.

### `module.eks.aws_iam_openid_connect_provider.oidc_provider[0]`
- **AWS perspective:** Registers your cluster's OIDC (OpenID Connect) issuer as a
  trusted identity provider in AWS IAM.
- **K8s perspective:** This is the foundation of **IRSA** (IAM Roles for Service
  Accounts) — the mechanism that lets an individual Kubernetes Service Account (not the
  whole node) assume a specific, narrowly-scoped IAM role. Without this, pods can only
  get AWS permissions via the node's IAM role, which means *every* pod on a node shares
  the *same* broad AWS permissions — a security anti-pattern this avoids. See §7 for the
  roles that actually use this trust.

### `module.eks.aws_eks_access_entry.this["arn:aws:iam::417886991962:root"]`
- **AWS perspective:** Registers an AWS IAM principal (here, the account's root user)
  as a known identity the EKS cluster will accept authentication from.
- **K8s perspective:** In Kubernetes, "who can log in" and "what they can do" are
  separate questions. This resource answers the first: this IAM identity is now allowed
  to authenticate to the cluster at all (via `aws eks get-token`, which is what
  `kubectl` uses under the hood).

### `module.eks.aws_eks_access_policy_association.this["arn:aws:iam::417886991962:root_single"]`
- **AWS perspective:** Attaches an EKS access policy (`AmazonEKSClusterAdminPolicy`,
  per `develop.tfvars`) to the access entry above, scoped to the whole cluster.
- **K8s perspective:** This answers the second question: what that identity can *do*
  once authenticated. `AmazonEKSClusterAdminPolicy` maps to full `cluster-admin` RBAC
  rights inside Kubernetes — i.e., that IAM principal can create/delete/modify anything
  in the cluster via `kubectl`. (Note: `develop.tfvars` also defines a `viewer` group
  with an empty `user_arn` list, so no read-only users are actually granted access yet.)

---

## 6. Add-ons — managed software running inside the cluster

Declared under `cluster_addons` in `eks.tf`. Each has a matching read-only
`module.eks.data.aws_eks_addon_version.this[...]` data source that just looks up the
latest compatible version string — not a real resource, so not detailed separately
below.

### `module.eks.aws_eks_addon.this["coredns"]`
- **AWS perspective:** An EKS-managed add-on — AWS deploys and keeps this software
  patched inside your cluster, so you don't manage its manifests by hand.
- **K8s perspective:** CoreDNS is the cluster's internal DNS server. It's what lets a
  pod resolve `my-service.my-namespace.svc.cluster.local` (or just `my-service` from
  within the same namespace) to the right internal IP. Virtually every app that talks
  to another in-cluster service depends on this. Configured here with `replicaCount =
  1` — fine for a dev cluster, but a single point of failure (no redundancy) if it
  crashes or its node goes down.

### `module.eks.aws_eks_addon.this["kube-proxy"]`
- **AWS perspective:** Another EKS-managed add-on, deployed as a DaemonSet (one copy per
  node).
- **K8s perspective:** Implements Kubernetes **Services** — the stable virtual IP +
  load-balancing abstraction that lets you address "the group of pods behind this
  Service" without caring which specific pod or node handles the request. It does this
  by programming each node's routing rules (iptables/IPVS).

### `module.eks.aws_eks_addon.this["vpc-cni"]`
- **AWS perspective:** AWS's own CNI (Container Network Interface) implementation,
  managed as an add-on. Configured here with `service_account_role_arn =
  aws_iam_role.vpc_cni.arn` — it uses IRSA (§5, §7) to get its AWS permissions.
- **K8s perspective:** This is the plugin that actually assigns IP addresses to pods.
  Unlike many Kubernetes distros that use an overlay network, EKS's default CNI gives
  each pod a *real, routable IP address from your VPC's subnet* — which is why the
  node's `vpc_cni` IAM role needs permission to attach/detach secondary IPs to/from EC2
  network interfaces. No pod networking works without this.

---

## 7. IRSA roles declared directly in `eks.tf` (outside the module)

These both depend on the OIDC provider trust from §5.

### `aws_iam_role.vpc_cni` + `aws_iam_role_policy_attachment.vpc_cni` (`AmazonEKS_CNI_Policy`)
- **AWS perspective:** An IAM role whose trust policy allows *only* the Kubernetes
  service account `system:serviceaccount:kube-system:aws-node` (via the OIDC provider)
  to assume it — not the whole node, not other pods.
- **K8s perspective:** This is what the `vpc-cni` add-on's pods (named `aws-node`) use
  to get permission to manage ENIs/IP addresses. It's a concrete example of the
  principle of least privilege: only the specific pods that need this power can get it,
  scoped by Kubernetes identity rather than by node.

### `aws_iam_role.ebs_csi_driver` + `aws_iam_role_policy_attachment.ebs_csi_driver` (`AmazonEBSCSIDriverPolicy`)
- **AWS perspective:** Same IRSA pattern, trust-scoped to
  `system:serviceaccount:kube-system:ebs-csi-controller-sa`.
- **K8s perspective:** This role would back the **EBS CSI driver** — the component that
  lets Kubernetes dynamically create/attach/detach AWS EBS volumes when a pod requests
  persistent storage via a `PersistentVolumeClaim`.
  > **Note:** the `aws-ebs-csi-driver` add-on itself is *not* currently listed in the
  > `cluster_addons` block in `eks.tf`. This role and policy are being created but
  > nothing in this config uses them yet — likely prepared for future use. If you don't
  > plan to add the EBS CSI add-on soon, this is currently unused infrastructure.

---

## 8. Worker nodes — where your containers actually run

All under `module.eks.module.eks_managed_node_group["generalworkload-v4"]`.

### `aws_eks_node_group.this[0]`
- **AWS perspective:** An EKS-managed node group — AWS wraps an EC2 Auto Scaling Group
  and handles bootstrapping the instances to join the cluster automatically. Configured
  here: 1 `m5a.xlarge` SPOT instance (min=max=desired=1 — fixed size, no scaling range
  today), 60GB disk.
- **K8s perspective:** These EC2 instances become **Kubernetes Nodes** — the machines
  the scheduler places your pods onto. Without at least one node, you have a working
  control plane but nowhere to actually run a container. Using SPOT capacity means this
  instance is cheaper but can be reclaimed by AWS with ~2 minutes' notice — acceptable
  for dev, risky for anything you can't tolerate restarting unexpectedly.

### `aws_launch_template.this[0]`
- **AWS perspective:** The EC2-level template (AMI, disk size, monitoring, instance
  metadata options) the node group's Auto Scaling Group uses to launch each instance.
  Notably enforces `http_tokens = "required"` — **IMDSv2**, a hardening setting that
  prevents a common SSRF-based credential-theft technique against the EC2 metadata
  service.
- **K8s perspective:** Indirect — this determines the underlying VM each Kubernetes Node
  runs on, but Kubernetes itself doesn't know or care about launch templates.

### `aws_iam_role.this[0]` (node role) + its policy attachments:
  - `aws_iam_role_policy_attachment.this["AmazonEKSWorkerNodePolicy"]`
  - `aws_iam_role_policy_attachment.this["AmazonEKS_CNI_Policy"]`
  - `aws_iam_role_policy_attachment.this["AmazonEC2ContainerRegistryReadOnly"]`
  - `aws_iam_role_policy_attachment.additional["ssm_access"]` (`AmazonSSMManagedInstanceCore`)
  - `aws_iam_role_policy_attachment.additional["cloudwatch_access"]` (`CloudWatchAgentServerPolicy`)
  - `aws_iam_role_policy_attachment.additional["service_role_ssm"]` (`AmazonEC2RoleforSSM`)
  - `aws_iam_role_policy_attachment.additional["default_policy"]` (`AmazonSSMManagedEC2InstanceDefaultPolicy`)
- **AWS perspective:** The IAM role every EC2 instance in this node group runs as (its
  "instance profile"). The four `additional` attachments are your custom additions on
  top of the module's defaults — mainly to enable AWS Systems Manager (SSM) access,
  which lets you get a shell on a node without SSH keys or open port 22, plus ship
  metrics to CloudWatch.
- **K8s perspective:** `AmazonEKSWorkerNodePolicy` and `AmazonEKS_CNI_Policy` are what
  let the instance actually register itself as a Kubernetes Node and participate in pod
  networking. `AmazonEC2ContainerRegistryReadOnly` is what lets the node pull container
  images (including from the ECR repo in §9) so pods scheduled on it can actually start.
  Without these, kubelet would start but fail to fully join the cluster or fail to pull
  any images.

### `module.eks.module.eks_managed_node_group["generalworkload-v4"].module.user_data.null_resource.validate_cluster_service_cidr`
- **AWS perspective:** Not a real resource — a Terraform `null_resource` the module uses
  purely to run a validation check at plan/apply time.
- **K8s perspective:** Sanity-checks that the node's bootstrap user-data won't conflict
  with the cluster's service CIDR range. Pure safety check, creates nothing.

---

## 9. Supporting resource: container registry

### `aws_ecr_repository.foo["codedevops"]` (`ecr.tf`)
- **AWS perspective:** A private Docker/OCI image registry (Elastic Container Registry)
  named `codedevops`, with mutable image tags (pushing the same tag twice overwrites
  it rather than erroring).
- **K8s perspective:** This is where the container images your Deployments/Pods
  reference would live. It connects directly to §8's node IAM role
  (`AmazonEC2ContainerRegistryReadOnly`) — nodes are explicitly permitted to pull from
  registries like this one in your account. No Kubernetes object depends on this
  existing per se, but your actual application workloads will.

---

## 10. Read-only data sources (not created, just looked up)

These don't appear in the "will be created" list — Terraform reads existing AWS state
at plan/apply time — but they feed values into the resources above, so they're worth
knowing about.

### `data.aws_availability_zones.available` (`main.tf`)
- **AWS perspective:** Looks up which AZs are available in the target region. Currently
  unused in `locals.tf` (the actual AZ list comes from `var.VPC.csai.azs` in
  `develop.tfvars` instead) — dead code left over from an earlier version of the config.
- **K8s perspective:** N/A.

### `data.aws_caller_identity.current` (`data.tf`)
- **AWS perspective:** Returns the AWS account ID of whoever is running Terraform.
- **K8s perspective:** Used to build `local.account_id`, referenced in KMS key policy
  statements (§2) so the key's IAM policy can name your account explicitly.

### `data.aws_eks_cluster_auth.eks` (`data.tf`)
- **AWS perspective:** Generates a short-lived authentication token for the EKS cluster
  by calling STS, the same way the AWS CLI does for `aws eks get-token`.
- **K8s perspective:** This is what lets the `kubernetes` and `helm` Terraform providers
  (`provider.tf`) authenticate to the cluster's API server directly from Terraform —
  e.g., if you later add `kubernetes_*` or `helm_release` resources to install
  applications, this token is how they'd talk to the cluster.

---

## Summary: the dependency chain in plain language

1. **VPC + subnets + NAT gateways** exist first — private subnets for nodes, public
   subnets for future load balancers, and NAT so private resources can still reach the
   internet.
2. **KMS key** exists so the **cluster's control plane** can encrypt Secrets.
3. **Cluster IAM role** lets AWS stand up the **EKS cluster** (control plane) inside
   your VPC's private subnets.
4. **Security groups** open exactly the ports the control plane and nodes need to talk
   to each other.
5. **OIDC provider** is registered so that, later, specific **pods** (not whole nodes)
   can assume specific IAM roles (**IRSA**) — used immediately by the `vpc-cni` add-on's
   role, and prepared (but currently unused) for an EBS CSI driver role.
6. **Access entries** map your AWS IAM identity to Kubernetes RBAC permissions, so you
   can actually `kubectl` into the thing you just built.
7. **Add-ons** (CoreDNS, kube-proxy, vpc-cni) install the minimum software every
   Kubernetes cluster needs to do DNS, Service routing, and pod networking.
8. **Node group** launches the actual EC2 instances that become Kubernetes Nodes —
   the place your workloads run — with an IAM role that lets them join the cluster and
   pull images (from ECR, §9, among other places).

Everything above exists to answer one question: *"How do I get a pod running securely,
with the right permissions, network access, DNS, and storage, on infrastructure I don't
have to hand-patch?"*
