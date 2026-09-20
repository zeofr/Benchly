/**
 * Terraform Configuration — API Benchmark SaaS
 * 
 * This simulates infrastructure provisioning using the Kubernetes provider
 * targeting a local Minikube cluster. In production, swap the provider
 * for AWS EKS, GKE, or AKS.
 */

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

# ── Provider: Local Minikube ──────────────────────────────────────────────────
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = var.kube_context
  }
}

# ── Namespace ─────────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "benchmark" {
  metadata {
    name = var.namespace
    labels = {
      app         = "api-benchmark-saas"
      environment = var.environment
    }
  }
}

# ── Kubernetes Secret: Database Credentials ───────────────────────────────────
resource "kubernetes_secret" "db_secret" {
  metadata {
    name      = "db-secret"
    namespace = kubernetes_namespace.benchmark.metadata[0].name
  }

  data = {
    DB_USER     = var.db_user
    DB_PASSWORD = var.db_password
    DB_NAME     = var.db_name
  }

  type = "Opaque"
}

# ── PostgreSQL Deployment ─────────────────────────────────────────────────────
resource "kubernetes_deployment" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.benchmark.metadata[0].name
    labels    = { app = "postgres" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "postgres" }
    }

    template {
      metadata {
        labels = { app = "postgres" }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:15-alpine"

          port {
            container_port = 5432
          }

          env {
            name = "POSTGRES_DB"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_secret.metadata[0].name
                key  = "DB_NAME"
              }
            }
          }

          env {
            name = "POSTGRES_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_secret.metadata[0].name
                key  = "DB_USER"
              }
            }
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_secret.metadata[0].name
                key  = "DB_PASSWORD"
              }
            }
          }

          resources {
            requests = {
              memory = "256Mi"
              cpu    = "250m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }
        }
      }
    }
  }
}

# ── PostgreSQL Service ────────────────────────────────────────────────────────
resource "kubernetes_service" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.benchmark.metadata[0].name
  }

  spec {
    selector = { app = "postgres" }

    port {
      port        = 5432
      target_port = 5432
    }

    type = "ClusterIP"
  }
}

# ── Backend Deployment ────────────────────────────────────────────────────────
resource "kubernetes_deployment" "backend" {
  metadata {
    name      = "backend"
    namespace = kubernetes_namespace.benchmark.metadata[0].name
    labels    = { app = "backend" }
  }

  spec {
    replicas = var.backend_replicas

    selector {
      match_labels = { app = "backend" }
    }

    template {
      metadata {
        labels = { app = "backend" }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "4000"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        container {
          name  = "backend"
          image = "${var.dockerhub_username}/benchmark-backend:latest"

          port {
            container_port = 4000
          }

          env {
            name  = "PORT"
            value = "4000"
          }

          env {
            name  = "DB_HOST"
            value = "postgres"
          }

          env {
            name = "DB_NAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_secret.metadata[0].name
                key  = "DB_NAME"
              }
            }
          }

          env {
            name = "DB_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_secret.metadata[0].name
                key  = "DB_USER"
              }
            }
          }

          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_secret.metadata[0].name
                key  = "DB_PASSWORD"
              }
            }
          }

          resources {
            requests = {
              memory = "128Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "256Mi"
              cpu    = "500m"
            }
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 4000
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }
        }
      }
    }
  }
}

# ── Backend Service ───────────────────────────────────────────────────────────
resource "kubernetes_service" "backend" {
  metadata {
    name      = "backend"
    namespace = kubernetes_namespace.benchmark.metadata[0].name
  }

  spec {
    selector = { app = "backend" }

    port {
      port        = 4000
      target_port = 4000
    }

    type = "ClusterIP"
  }
}

# ── Frontend Deployment ───────────────────────────────────────────────────────
resource "kubernetes_deployment" "frontend" {
  metadata {
    name      = "frontend"
    namespace = kubernetes_namespace.benchmark.metadata[0].name
    labels    = { app = "frontend" }
  }

  spec {
    replicas = var.frontend_replicas

    selector {
      match_labels = { app = "frontend" }
    }

    template {
      metadata {
        labels = { app = "frontend" }
      }

      spec {
        container {
          name  = "frontend"
          image = "${var.dockerhub_username}/benchmark-frontend:latest"

          port {
            container_port = 8080   # nginx listens on 8080 (non-root), not 80
          }

          resources {
            requests = {
              memory = "64Mi"
              cpu    = "50m"
            }
            limits = {
              memory = "128Mi"
              cpu    = "200m"
            }
          }
        }
      }
    }
  }
}

# ── Redis Deployment ──────────────────────────────────────────────────────────
resource "kubernetes_deployment" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.benchmark.metadata[0].name
    labels    = { app = "redis" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "redis" }
    }

    template {
      metadata {
        labels = { app = "redis" }
      }

      spec {
        container {
          name    = "redis"
          image   = "redis:7-alpine"
          command = ["redis-server", "--appendonly", "yes"]

          port {
            container_port = 6379
          }

          resources {
            requests = { memory = "64Mi",  cpu = "50m"  }
            limits   = { memory = "256Mi", cpu = "200m" }
          }

          readiness_probe {
            exec {
              command = ["redis-cli", "ping"]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.benchmark.metadata[0].name
  }

  spec {
    selector = { app = "redis" }
    port {
      port        = 6379
      target_port = 6379
    }
    type = "ClusterIP"
  }
}

# ── Worker Deployment (Fix 16, 24) ────────────────────────────────────────────
resource "kubernetes_deployment" "worker" {
  metadata {
    name      = "worker"
    namespace = kubernetes_namespace.benchmark.metadata[0].name
    labels    = { app = "worker" }
  }

  spec {
    replicas = var.worker_replicas

    selector {
      match_labels = { app = "worker" }
    }

    template {
      metadata {
        labels = { app = "worker" }
      }

      spec {
        container {
          name    = "worker"
          image   = "${var.dockerhub_username}/benchmark-backend:latest"
          command = ["node", "src/worker.js"]

          env {
            name  = "REDIS_HOST"
            value = "redis"
          }

          env {
            name  = "DB_HOST"
            value = "postgres"
          }

          env {
            name = "DB_NAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_secret.metadata[0].name
                key  = "DB_NAME"
              }
            }
          }

          env {
            name = "DB_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_secret.metadata[0].name
                key  = "DB_USER"
              }
            }
          }

          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_secret.metadata[0].name
                key  = "DB_PASSWORD"
              }
            }
          }

          resources {
            requests = { memory = "256Mi", cpu = "200m"  }
            limits   = { memory = "512Mi", cpu = "1000m" }
          }
        }
      }
    }
  }
}

# ── Pod Disruption Budgets (Fix 14) ──────────────────────────────────────────
resource "kubernetes_pod_disruption_budget_v1" "backend_pdb" {
  metadata {
    name      = "backend-pdb"
    namespace = kubernetes_namespace.benchmark.metadata[0].name
  }
  spec {
    min_available = "1"
    selector {
      match_labels = { app = "backend" }
    }
  }
}

resource "kubernetes_pod_disruption_budget_v1" "frontend_pdb" {
  metadata {
    name      = "frontend-pdb"
    namespace = kubernetes_namespace.benchmark.metadata[0].name
  }
  spec {
    min_available = "1"
    selector {
      match_labels = { app = "frontend" }
    }
  }
}

# ── Frontend Service ──────────────────────────────────────────────────────────
resource "kubernetes_service" "frontend" {
  metadata {
    name      = "frontend"
    namespace = kubernetes_namespace.benchmark.metadata[0].name
  }

  spec {
    selector = { app = "frontend" }

    port {
      port        = 8080
      target_port = 8080
      node_port   = 30080
    }

    type = "NodePort"
  }
}
