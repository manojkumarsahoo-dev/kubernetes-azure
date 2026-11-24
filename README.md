# kubernetes-veeraops-ecommerce-microservices-app (Azure / AKS edition)

The original project ran on AWS (EKS + ECR + RDS + S3 state). This version runs on **Azure**:
AKS, Azure Container Registry, Azure Database for MySQL Flexible Server, and Azure Storage for
Terraform state. The application code, Dockerfiles, ArgoCD GitOps flow, EFK logging and
Prometheus/Grafana monitoring are kept.

## What changed

| AWS (before) | Azure (now) |
|---|---|
| EKS + managed node group + IAM roles + addons | **AKS** (`azurerm_kubernetes_cluster`, autoscaling node pool, Azure CNI overlay) |
| ECR | **ACR** (admin-backed Kubernetes `imagePullSecret` for restricted sandbox RBAC) |
| RDS MySQL (public, `allow_all` security group) | **Azure Database for MySQL Flexible Server 8.4**, private (VNet-integrated), TLS on |
| VPC, subnets, NAT gateway | VNet with an AKS subnet and a delegated MySQL subnet |
| S3 bucket for Terraform state | **Azure Storage** blob container (`azurerm` backend) |
| EC2 "client" server with kubectl/eksctl | Not needed: use `az aks get-credentials` from Cloud Shell or your machine |
| EBS CSI StorageClass (`ebs.csi.aws.com`) | **Azure Disk CSI** StorageClass (`disk.csi.azure.com`) |
| AWS access keys in GitHub secrets | Administrator-provisioned Azure service principal (`azure/login`), client secret stored as a GitHub secret |
| ingress-nginx | **Traefik** (see note below) |

Other changes you should know about:

- **Secrets moved out of Git.** `backend-cm.yml` no longer contains DB or mail credentials. They live in a
  Kubernetes Secret (`backend-secret`) created by `scripts/create-backend-secret.sh`.
- **Backend TLS support.** `backend/app.py` has a small change: with `DB_SSL=true` it connects to MySQL over TLS
  (Azure MySQL refuses unencrypted connections). The default is off, so nothing else changes.
- **Fluent Bit parser** switched from Docker-JSON to CRI, because AKS nodes use containerd.
- **MySQL admin user** is `shopadmin`: Azure reserves `admin`, so the old name would be rejected.
- **ArgoCD `efk-stack` app** pointed at a different GitHub repo (`CloudTechDevOps/...`). It now points at your repo.
- Image references in the `deployment.yml` files are placeholders (`youracrname.azurecr.io/...:latest`); the build
  workflow rewrites them with the real registry and commit SHA, exactly like the ECR version did.

### About the ingress controller

The community **ingress-nginx** project ended maintenance in March 2026, and Microsoft's managed NGINX add-on
for AKS only receives security patches until 30 November 2026. So this version uses **Traefik**, which is
maintained and reads the same standard `Ingress` resource (`frontend/main/ingress.yml`, now with
`ingressClassName: traefik`). Other Azure options: Application Gateway for Containers, or the AKS
application-routing Gateway API implementation (both mean migrating the Ingress to new resources).

## Prerequisites

- An Azure sandbox resource group in an allowed region, with enough quota for up to 3 x `Standard_D2s_v3` AKS nodes (6 vCPUs total)
- Azure CLI, `kubectl`, `helm` (Azure Cloud Shell has all of them)
- This repo pushed to your own GitHub repository

## Deployment workflow

### 1. Check Azure sandbox prerequisites

The sandbox blocks role-definition/role-assignment changes and does not support Microsoft Entra ID administration.
Do not try to create an app registration, service principal, or role assignment from the sandbox. Ask the
sandbox/lab administrator for a pre-provisioned identity and the required permissions. The required Azure
resource providers must also be registered by the administrator if your identity cannot register them.

The existing sandbox resource group must be in an allowed region (for example `westus2`, `centralindia`, `southindia`,
or `westindia`). The workflow checks the resource group's actual region before creating resources.

### 2. Obtain an Azure identity

For GitHub Actions, use a service principal supplied by your administrator (or configured outside the
restricted sandbox). The same service principal is used by Terraform and as the AKS control-plane service
principal. It must already have sufficient permissions on the existing sandbox resource group and VNet.
The sandbox does not allow you to create the service principal or grant it role assignments.

For local practice, sign in with the account provided by the lab:

```bash
az login
az account set --subscription <your-subscription-id>
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
az account show
```

### 3. Configure GitHub

- Repository **secrets** (for GitHub Actions): `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`,
  `AZURE_SUBSCRIPTION_ID`, `GIT_PAT`, and `MYSQL_ADMIN_PASSWORD` (use administrator-provided Azure identity
  credentials; do not try to create role assignments in the sandbox; choose a strong password:
  8-128 characters, mixed case, digits and symbols; avoid quotes and `$`).
- Repository **Actions variables** (Settings → Secrets and variables → Actions → Variables):
  `AZURE_RESOURCE_GROUP` = your already-existing sandbox resource group;
  `AZURE_LOCATION` = an allowed region for Terraform state storage and all deployed Azure resources
  (default: `westus2`). The existing sandbox resource group's metadata location may be different
  (for example, `westus`); that does not prevent resources inside it from being deployed in `westus2`.
  `TFSTATE_STORAGE_ACCOUNT` = a globally unique 3-24 character lowercase name.
  The workflow will not create a resource group. The supplied identity must already be authorized on this
  existing resource group and must be able to create/read a Storage Account and its keys. If your
  sandbox blocks Storage Account creation, create the account and `tfstate` container in the Azure
  portal first, then rerun the workflow with that account name. Do not try to create `rg-tfstate`.
- Create a GitHub **environment** named `production` (optionally add yourself as a required reviewer for an
  approval gate).
- Edit `.github/workflows/infra-aks.yml` and set `TFSTATE_STORAGE_ACCOUNT` to a **globally unique** name
  (3-24 lowercase letters/digits).

### 4. Create the infrastructure

Run the **infra Terraform (AKS)** workflow from the Actions tab. Check the plan in the log, then approve the
apply job. It uses the existing sandbox resource group and creates a VNet, ACR, AKS and MySQL inside it.
It does not create another resource group. The AKS service creates its own managed node resource group;
the sandbox restriction means you cannot view or manage that secondary group directly.

The default AKS node pool starts with 2 nodes and can autoscale up to 3 nodes, within the sandbox limit.
The Terraform state storage account, AKS, ACR, VNet and MySQL use `AZURE_LOCATION` (default
`westus2`). The workflow deliberately does not reject the existing resource group based on its
metadata location; it only validates the actual deployment region against the sandbox allow-list.
The default `Standard_D2s_v3` SKU is on the sandbox's allowed VM SKU list. If the sandbox policy `allowed-vm-scale-set-skus` rejects it (`RequestDisallowedByPolicy`), set the Actions variable `AKS_NODE_VM_SIZE` to another allowed size (for example `Standard_DS2_v2`). Confirm your subscription quota
before applying.

Local alternative:

```bash
cd AKS-Terraform
export TF_VAR_mysql_admin_password='<your password>'
export TF_VAR_aks_service_principal_client_id='<administrator-provided client id>'
export TF_VAR_aks_service_principal_client_secret='<administrator-provided client secret>'
terraform init -backend-config="resource_group_name=<your-existing-sandbox-resource-group>" \
  -backend-config="storage_account_name=<your-storage-account>" \
  -backend-config="container_name=tfstate" -backend-config="key=veeraops-shop.tfstate"
terraform apply
```

### 5. Connect to the cluster and finish GitHub setup

```bash
RG="<your-existing-sandbox-resource-group>"
AKS_NAME=$(terraform -chdir=AKS-Terraform output -raw aks_cluster_name)
ACR_NAME=$(terraform -chdir=AKS-Terraform output -raw acr_name)
az aks get-credentials --resource-group "$RG" --name "$AKS_NAME"
kubectl get nodes

# Create a GitHub repository VARIABLE named ACR_NAME with the value printed below.
echo "$ACR_NAME"

# Save this ACR name as the GitHub Actions variable ACR_NAME.
# The infra workflow configures the AKS imagePullSecret automatically.
# The build workflow uses the ACR admin credentials enabled by Terraform to push images,
# avoiding the need to create an AcrPush role assignment in the restricted sandbox.
```

**Using Azure Cloud Shell instead of your laptop?** Cloud Shell is ephemeral, so nothing persists between
sessions. Each time you open a new one, reconnect to the cluster and re-clone the repo (there is no local
Terraform state there, so use the default cluster name directly):

```bash
az aks get-credentials -g <your-existing-sandbox-resource-group> -n aks-veeraops-shop --overwrite-existing
kubectl get nodes                          # both nodes should be Ready

git clone https://github.com/<your-github-user>/kuberenetes-azure.git
cd kuberenetes-azure
git log --oneline -3                       # confirm you have the commit with the real image tags
```

### 6. Install the ingress controller (Traefik)

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik -n traefik --create-namespace
kubectl get svc -n traefik        # wait for an EXTERNAL-IP (Azure Load Balancer)
```

### 7. Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply --server-side --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl get pods -n argocd                # wait until every pod is 1/1 Running (about 3-4 minutes)
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
kubectl get svc -n argocd
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

> **Use `--server-side`.** A plain `kubectl apply` fails on the `applicationsets.argoproj.io` CRD with
> `metadata.annotations: Too long: may not be more than 262144 bytes`. Everything else installs, but the
> ApplicationSet CRD is missing and `argocd-applicationset-controller` keeps restarting. If you already hit
> this, just re-run the command above with `--server-side --force-conflicts`.

### 8. Create the backend Secret and initialise the database

```bash
RESOURCE_GROUP='<your-existing-sandbox-resource-group>' \
DB_PASSWORD='<same as MYSQL_ADMIN_PASSWORD>' \
MAIL_USERNAME='<your gmail address>' MAIL_PASSWORD='<your gmail app password>' \
  ./scripts/create-backend-secret.sh

./scripts/init-db.sh      # runs backend/test.sql inside the cluster (it DROPs and recreates the tables)
kubectl rollout restart deployment backend-deployment -n microservices
```

The MySQL server is private, so the SQL is loaded by a Job running inside AKS rather than from your laptop.

Things that matter here:

- **Do this before (or right after) step 10.** The backend pods read `backend-secret` through `envFrom`. If the
  Secret does not exist yet they sit in `CreateContainerConfigError` until it does.
- **Pods only read environment variables when they start**, so after creating or changing the Secret always run
  `kubectl rollout restart deployment backend-deployment -n microservices`.
- **The Gmail app password must be the bare 16 characters**: no spaces, and no `<` `>` around it. Gmail shows it
  in four groups of four; remove the spaces. Wrapping it in `<...>` makes it 18 characters and Gmail rejects the login.
- **Never paste real passwords into a shared file or chat.** Cloud Shell records the commands and output of your
  session in container logs.

### 9. Build and push images

Run the **CI/CD for app (Azure ACR)** workflow. It builds all 19 images, pushes them to ACR and commits the
new image tags back to `main`.

### 10. Deploy with ArgoCD

```bash
git pull                                  # get the commit containing the real image tags
kubectl apply -f k8s-argocd/backend/
kubectl apply -f k8s-argocd/frontend/
kubectl apply -f k8s-argocd/efk-stack/
kubectl get pods -n microservices
```

The 2 backend pods will show `CreateContainerConfigError` until `backend-secret` exists (step 8). That is
expected on a first run; it clears after the Secret is created and the deployment is restarted.

### 11. Monitoring (optional)

Follow `grafana-prometheous/README.md`.

### 12. Open the app

```bash
kubectl get ingress -n microservices
kubectl get svc -n traefik                # the EXTERNAL-IP is your site: http://<EXTERNAL-IP>
```

Kibana (`kubectl get svc kibana -n kube-logging`) is exposed publicly without a login, as in the original.
Restrict or remove that LoadBalancer before using this for anything real.

## Verify the deployment

Run these from Cloud Shell once everything is up.

```bash
# 1. Secret and ConfigMap exist
kubectl get secret backend-secret -n microservices
kubectl get configmap backend-config -n microservices

# 2. Everything is Running (db-init shows Completed, which is correct)
kubectl get pods -n microservices
kubectl get pods -n argocd

# 3. Database tables exist (the MySQL server is private, so query from a pod inside the cluster).
#    Look up the host OUTSIDE the pod: the mysql image has no kubectl.
DBHOST=$(kubectl get secret backend-secret -n microservices -o jsonpath='{.data.DB_HOST}' | base64 -d)
kubectl run mysql-check --rm -it --restart=Never --image=mysql:8.4 -n microservices \
  --env="MYSQL_PWD=<your MySQL admin password>" -- \
  mysql -h "$DBHOST" -u shopadmin --ssl-mode=REQUIRED cloud -e "SHOW TABLES;"
# Expected tables: cart_items, order_items, orders, payments, pending_signups, recharges, service_activity, users

# 4. Gmail SMTP login works from inside the backend pod
kubectl exec deployment/backend-deployment -n microservices -- python -c "
import os, smtplib
s = smtplib.SMTP('smtp.gmail.com', 587, timeout=10)
s.starttls()
s.login(os.environ['MAIL_USERNAME'], os.environ['MAIL_PASSWORD'])
print('LOGIN OK')
"
```

The `mysql-check` pod prints a harmless `couldn't attach to pod ... falling back to streaming logs` warning;
the query output still appears. To test sign-up, register on the site and check `pending_signups`
(`SELECT email, username FROM pending_signups;`) while the OTP is still pending.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `kubectl apply` of ArgoCD fails with `applicationsets.argoproj.io ... Too long: may not be more than 262144 bytes` | Client-side apply stores the whole CRD in an annotation | Re-run with `kubectl apply --server-side --force-conflicts -n argocd -f <install.yaml>` |
| Backend pods stuck in `CreateContainerConfigError`; `kubectl get secret backend-secret` says `NotFound` | The Secret was never created | Run `scripts/create-backend-secret.sh` (step 8), then `kubectl rollout restart deployment backend-deployment -n microservices` |
| Backend pods Running but no OTP / order emails; SMTP test fails with `Connection unexpectedly closed` | Wrong Gmail app password in the Secret (typo, spaces, or `<...>` brackets copied along) | Re-create the Secret with the bare 16-character app password and restart the deployment. Check the length with `kubectl exec deployment/backend-deployment -n microservices -- python -c "import os; print(len(os.environ['MAIL_PASSWORD']))"` (should print `16`) |
| `MAIL_PASSWORD` length prints `18` | Password was entered as `<xxxxxxxxxxxxxxxx>` | Remove the angle brackets |
| `mysql-check` prints the mysql `--help` text and the `-h` value looks like `-u` | `$(kubectl ...)` was run inside the mysql container, where kubectl does not exist, so the host came back empty | Look up `DBHOST` first in your own shell (see "Verify the deployment") |
| Changed the Secret but the app still uses the old value | Environment variables are only read when a pod starts | `kubectl rollout restart deployment backend-deployment -n microservices` |
| Gmail login still fails with the right password | Account has no 2-Step Verification, so app passwords are unavailable, or the app password was revoked | Enable 2-Step Verification and generate a new app password at https://myaccount.google.com/apppasswords |

## Clean up

Do not delete the shared sandbox resource group. From the same Terraform working directory and with the
same backend configuration used for deployment, remove only the resources managed by this Terraform state:

```bash
cd AKS-Terraform
terraform destroy
```

Review the destroy plan carefully before confirming. Keep the Terraform state storage account/container
until the destroy operation has completed.

## Security notes

- The original repo had DB and Gmail app passwords in plain text. Treat them as compromised, rotate them, and use
  your own Gmail app password in step 8.
- Never put real passwords in this README, in commit history, or in a chat or screenshot. If a password has
  appeared in a terminal log, a paste or a commit, treat it as exposed: revoke the Gmail app password
  (https://myaccount.google.com/apppasswords), change the MySQL admin password, and re-run step 8.
- The pipeline identity needs sufficient pre-existing permissions on the existing sandbox resource group.
  It does not create Azure role assignments; ACR admin credentials are used for image push/pull in this
  sandbox-compatible setup.
- The AKS service-principal client secret is stored in Terraform state by the AzureRM provider. Keep the
  remote state storage account private and tightly permissioned; never commit or publicly expose state files.
- For production, consider Azure Key Vault with the Secrets Store CSI driver instead of a plain Kubernetes
  Secret (workload identity is already enabled on the cluster), and zone-redundant HA for MySQL.
