1. terraform apply -var-file=develop.tfvars
2. aws eks update-kubeconfig --name dev-me-k8s-cluster --region us-east-1 --profile terraform
3. kubectl get nodes -A
4. kubectl get pods -A
6. kubectl get services -A
7. kubectl apply -f app.yaml
8. kubectl get pods
9. kubectl get ingress
