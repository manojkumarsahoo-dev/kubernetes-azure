# Prometheus & Grafana on AKS

Installs kube-prometheus-stack with Helm. Run from Azure Cloud Shell or any machine where
`kubectl` already points at the AKS cluster (`az aks get-credentials ...`).

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace prometheus

# AKS manages the control plane, so etcd / scheduler / controller-manager / kube-proxy
# metrics are not reachable. Disable those scrapers to avoid permanently "down" alerts.
helm install stable prometheus-community/kube-prometheus-stack -n prometheus \
  --set kubeEtcd.enabled=false \
  --set kubeScheduler.enabled=false \
  --set kubeControllerManager.enabled=false \
  --set kubeProxy.enabled=false

# Expose Grafana through an Azure Load Balancer public IP
kubectl patch svc stable-grafana -n prometheus -p '{"spec":{"type":"LoadBalancer"}}'
```

Grafana admin password:

```bash
kubectl get secret -n prometheus stable-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d
```

Prometheus UI (kept private, use a port-forward instead of exposing it):

```bash
kubectl port-forward -n prometheus svc/stable-kube-prometheus-sta-prometheus 9090:9090
```

Check status:

```bash
kubectl get pods -n prometheus
kubectl get svc -n prometheus
```

> Azure-native alternative: AKS also offers *Azure Monitor managed service for Prometheus* and
> *Azure Managed Grafana* (no in-cluster Prometheus to run). This repo keeps the in-cluster stack
> so the rest of the project works the same way as before.
