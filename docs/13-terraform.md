# Terraform Infrastructure

## Overview

Terraform is used to **provision and manage Kubernetes resources** declaratively. The local config targets a Minikube cluster. There is also an `aws-eks.tf` file with an AWS EKS cluster definition for cloud deployment.

## Files

```
terraform/
├── main.tf           # Provider config + all K8s resources
├── variables.tf      # Input variable declarations
├── outputs.tf        # Output values (service URLs, namespace)
├── aws-eks.tf        # AWS EKS cluster (production target)
└── .terraform.lock.hcl  # Provider version lock file
```

## Providers

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.24" }
    helm       = { source = "hashicorp/helm",       version = "~> 2.12" }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context    # default: "minikube"
}
```

## Variables (`variables.tf`)

| Variable | Default | Description |
|----------|---------|-------------|
| `kube_context` | `"minikube"` | kubectl context to use |
| `namespace` | `"benchmark"` | K8s namespace name |
| `environment` | `"development"` | Environment label |
| `db_user` | `"postgres"` | Database username |
| `db_password` | — | Database password (no default — must be supplied) |
| `db_name` | `"benchmarkdb"` | Database name |
| `backend_replicas` | `2` | Initial backend replica count |
| `frontend_replicas` | `1` | Frontend replica count |
| `worker_replicas` | `1` | Worker replica count |
| `dockerhub_username` | — | Docker Hub username for image references |

## Resources created by `main.tf`

| Resource | Type | Description |
|----------|------|-------------|
| `kubernetes_namespace.benchmark` | Namespace | `benchmark` namespace with labels |
| `kubernetes_secret.db_secret` | Secret | DB credentials (Opaque) |
| `kubernetes_deployment.postgres` | Deployment | PostgreSQL single replica |
| `kubernetes_service.postgres` | ClusterIP service | Postgres internal access |
| `kubernetes_deployment.redis` | Deployment | Redis single replica with AOF |
| `kubernetes_service.redis` | ClusterIP service | Redis internal access |
| `kubernetes_deployment.backend` | Deployment | Backend API (configurable replicas) |
| `kubernetes_service.backend` | ClusterIP service | Backend internal access |
| `kubernetes_deployment.frontend` | Deployment | Frontend nginx |
| `kubernetes_service.frontend` | NodePort service | Frontend exposed on port 30080 |
| `kubernetes_deployment.worker` | Deployment | Worker process |
| `kubernetes_pod_disruption_budget_v1.backend_pdb` | PDB | Min 1 backend pod available during disruptions |
| `kubernetes_pod_disruption_budget_v1.frontend_pdb` | PDB | Min 1 frontend pod available |

## Outputs (`outputs.tf`)

After `terraform apply`, the following values are printed:

| Output | Description |
|--------|-------------|
| `namespace` | K8s namespace name |
| `backend_service_name` | Backend ClusterIP service name |
| `frontend_nodeport` | Frontend NodePort number (30080) |

## Usage

### Prerequisites

```bash
# Install Terraform
# macOS:  brew install terraform
# Linux:  see https://developer.hashicorp.com/terraform/install
# Windows: choco install terraform

minikube start --cpus=4 --memory=8192
```

### Apply

```bash
cd terraform

# Initialize providers
terraform init

# Preview changes
terraform plan -var="db_password=demo123" -var="dockerhub_username=myuser"

# Apply
terraform apply -var="db_password=demo123" -var="dockerhub_username=myuser"
```

### Destroy

```bash
terraform destroy -var="db_password=demo123" -var="dockerhub_username=myuser"
```

### Using a `.tfvars` file (recommended)

Create `terraform/terraform.tfvars` (do not commit this file):

```hcl
db_password        = "my-secure-password"
dockerhub_username = "mydockerhubuser"
backend_replicas   = 2
```

Then:
```bash
terraform apply   # auto-picks up terraform.tfvars
```

## AWS EKS (`aws-eks.tf`)

The `aws-eks.tf` file defines an EKS cluster for production deployment. It requires the `aws` provider and appropriate IAM credentials. Key resources:
- EKS cluster with managed node group
- Node group with `t3.medium` instances (2–5 nodes)
- IAM roles for nodes and cluster
- VPC configuration (uses default VPC by default)

To use in production:
```bash
terraform init
terraform workspace new production
terraform apply -var-file=production.tfvars
```

## State management

The local config uses local state (`terraform.tfstate`). For team usage, configure a remote backend:

```hcl
terraform {
  backend "s3" {
    bucket = "my-terraform-state"
    key    = "benchly/terraform.tfstate"
    region = "us-east-1"
  }
}
```
