# Module entry point. Everything here talks to the Kubernetes API (directly
# via kubernetes_manifest, or indirectly via helm_release) - the cluster
# itself, the VPC, and ACM live in modules/eks-cluster instead, applied and
# destroyed as a separate Terragrunt layer. See this module's README for why.
