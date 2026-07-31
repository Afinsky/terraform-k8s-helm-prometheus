# Prerequisites:

$ aws --version
aws-cli/2.13.1 Python/3.11.4 Linux/6.11.4-201.fc40.x86_64 exe/x86_64.fedora.40 prompt/off
$ terraform -version
Terraform v1.9.8
on linux_amd64
$ kubectl version
Client Version: v1.31.2
Kustomize Version: v5.4.2
Server Version: v1.31.1-eks-ce1d5eb
$ helm version 
version.BuildInfo{Version:"3.16.2", GitCommit:"5a5449dc42be07001fd5771d56429132984ab3ab", GitTreeState:"clean", GoVersion:"go1.22.7"}

aws eks --region us-east-1 update-kubeconfig --name dev-abotyan-al2023 --profile sandbox

https://kubernetes.io/docs/tutorials/stateless-application/guestbook/#viewing-the-frontend-service-via-loadbalancer

terraform state list | grep 'module.eks_al2023' | rev | cut -d'.' -f 1,2 | rev | sort -u -t. -k1,1
kubectl get pod -o=custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName --all-namespaces | sort -k2

helm version
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/prometheus
kubectl get pods
kubectl get pods --namespace default -l "app.kubernetes.io/name=prometheus,app.kubernetes.io/instance=prometheus" -o jsonpath="{.items[0].metadata.name}"
export POD_NAME=$(kubectl get pods --namespace default -l "app.kubernetes.io/name=prometheus,app.kubernetes.io/instance=prometheus" -o jsonpath="{.items[0].metadata.name}")
  
helm upgrade --install prometheus prometheus-community/prometheus   --set server.persistentVolume.storageClass="gp2"   --set alertmanager.persistentVolume.storageClass="gp2"

# Check targets from prometheus server using curl
kubectl port-forward prometheus-deployment-6869656f4f-88h82 8080:9090 -n monitoring
curl localhost:8080/api/v1/targets | jq

# What k8s object will be created by helm
helm install prometheus prometheus-community/prometheus --dry-run --debug
# or 
helm template my-release prometheus-community/prometheus

# Get already created k8s objects
helm get all prometheus > prometheus-manifest.yaml

cd $HOME/.cache/helm/repository
tar -tzf prometheus-25.28.0.tgz | grep 'prometheus/charts'


# Get all but not all
https://github.com/kubernetes/kubernetes/issues/64814

# Display which Pods have the PVC in use
https://github.com/kubernetes/kubernetes/issues/65233
# or 
https://patroware.medium.com/how-to-get-the-relationship-between-the-persistent-volumes-and-the-pods-in-kubernetes-73b4d740ee53

# How to Check Pod Ports with kubectl
https://signoz.io/guides/how-to-check-what-port-a-pod-is-listening-on-with-kubectl-and-not-looking-at-the-dockerfile/

https://devopscube.com/prometheus-architecture/
https://devopscube.com/setup-prometheus-monitoring-on-kubernetes/
https://devopscube.com/node-exporter-kubernetes/
https://devopscube.com/best-opensource-monitoring-tools/






# $HOME/.aws/credentials

[profile sandbox]
sso_session = AWS_Sandbox
sso_account_id = ************
sso_role_name = AWSPowerUserAccess
region = us-east-1
output = json

[sso-session AWS_Sandbox]
sso_start_url = https://******************.awsapps.com/start#/
sso_region = us-east-1
sso_registration_scopes = sso:account:access