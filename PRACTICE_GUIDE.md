# 🚀 DevSecOps Pipeline - Guía de Práctica Manual
## Preparación Entrevista EPAM - Azure Voting App

> **Modo**: Hands-on manual para máxima retención
> **Tiempo estimado**: 3 días (Vie-Dom)
> **Costo estimado**: ~$4-5 USD total

---

# 📅 VIERNES - Fases 1-3: Infraestructura Base

---

## FASE 1: TERRAFORM - Infrastructure as Code

### 🎓 Conceptos Clave (Lee esto primero, memoriza para la entrevista)

| Concepto | Qué es | Por qué importa |
|----------|--------|-----------------|
| **Terraform** | Herramienta IaC de HashiCorp, declarativa, cloud-agnostic | Reproducibilidad, versionado en Git, plan antes de apply |
| **Resource Group** | Contenedor lógico de recursos Azure | Organización, permisos grupales, eliminación fácil |
| **ACR** | Azure Container Registry - registro privado Docker | Almacena imágenes, integración nativa con AKS |
| **AKS** | Azure Kubernetes Service - K8s administrado | Control plane gratis, solo pagas nodos |
| **Managed Identity** | Identidad Azure sin passwords | Zero Trust, elimina credential leaks |
| **Kubenet** | Plugin de red simple para AKS | Económico, pods usan IPs internas |

---

### 📁 Paso 1.1: Crear estructura de carpetas

```powershell
cd "c:\Users\Daniel Matapi\cloud-practice\azure-voting-app-redis"
mkdir terraform
mkdir k8s
mkdir k8s\base
mkdir .github
mkdir .github\workflows
mkdir docs
```

---

### 📝 Paso 1.2: Crear providers.tf

Crea `terraform/providers.tf`:

```hcl
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
```

**📚 Notas sobre providers.tf:**
- `required_version`: Versión mínima de Terraform
- `required_providers`: Provider Azure con versión ~> 3.0 (cualquier 3.x)
- `features {}`: Bloque obligatorio, configura comportamiento del provider
- `prevent_deletion_if_contains_resources = false`: Permite destruir RG con recursos

**🎤 Pregunta entrevista**: "¿Por qué usarías backend remoto?"
> "Para colaboración del equipo, state compartido, locking automático, y encryption at rest del state que contiene info sensible."

---

### 📝 Paso 1.3: Crear variables.tf

Crea `terraform/variables.tf`:

```hcl
variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
  default     = "votingapp"
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment debe ser: dev, staging, o prod."
  }
}

variable "location" {
  description = "Región de Azure"
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Tags para recursos"
  type        = map(string)
  default = {
    Project     = "VotingApp"
    Environment = "Development"
    Owner       = "Daniel Matapi"
    CostCenter  = "Training"
    ManagedBy   = "Terraform"
  }
}

variable "aks_node_count" {
  description = "Número de nodos"
  type        = number
  default     = 1
}

variable "aks_node_vm_size" {
  description = "Tamaño de VM"
  type        = string
  default     = "Standard_B2s"
}

variable "aks_enable_autoscaling" {
  description = "Habilitar autoscaling"
  type        = bool
  default     = true
}

variable "aks_min_nodes" {
  description = "Mínimo nodos"
  type        = number
  default     = 1
}

variable "aks_max_nodes" {
  description = "Máximo nodos"
  type        = number
  default     = 3
}

variable "vnet_address_space" {
  description = "Address space VNet"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_prefix" {
  description = "Prefix subnet AKS"
  type        = string
  default     = "10.0.1.0/24"
}
```

**📚 Notas sobre variables.tf:**
- `validation`: Valida que el valor sea válido antes de ejecutar
- `type = map(string)`: Diccionario clave-valor para tags
- `Standard_B2s`: VM económica (2 vCPU, 4GB RAM, ~$30/mes)
- Los tags son críticos para cost tracking y organización

**🎤 Pregunta entrevista**: "¿Cómo manejas diferentes ambientes?"
> "Uso workspaces de Terraform + archivos .tfvars por ambiente. dev.tfvars tiene node_count=1, prod.tfvars tiene node_count=3. También condicionales basados en var.environment."

---

### 📝 Paso 1.4: Crear main.tf

Crea `terraform/main.tf`:

```hcl
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(var.tags, {
    Environment = var.environment
  })
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_container_registry" "main" {
  name                = "${var.project_name}${var.environment}acr"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.common_tags
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = local.common_tags
}

resource "azurerm_subnet" "aks" {
  name                 = "${local.name_prefix}-aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_prefix]
}

resource "azurerm_network_security_group" "aks" {
  name                = "${local.name_prefix}-aks-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }
  
  tags = local.common_tags
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.name_prefix}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "${local.name_prefix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${local.name_prefix}-aks"
  kubernetes_version  = "1.28"
  
  default_node_pool {
    name                = "system"
    vm_size             = var.aks_node_vm_size
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = var.aks_enable_autoscaling
    node_count          = var.aks_enable_autoscaling ? null : var.aks_node_count
    min_count           = var.aks_enable_autoscaling ? var.aks_min_nodes : null
    max_count           = var.aks_enable_autoscaling ? var.aks_max_nodes : null
    tags                = local.common_tags
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  network_profile {
    network_plugin = "kubenet"
    network_policy = "calico"
    pod_cidr       = "10.244.0.0/16"
    service_cidr   = "10.0.2.0/24"
    dns_service_ip = "10.0.2.10"
  }
  
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }
  
  tags = local.common_tags
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
```

**📚 Notas sobre main.tf:**

| Recurso | Propósito |
|---------|-----------|
| `locals` | Variables computadas, name_prefix = votingapp-dev |
| `resource_group` | Contenedor de todos los recursos |
| `container_registry` | Almacena imágenes Docker, SKU Basic = $5/mes |
| `virtual_network` | Red privada aislada 10.0.0.0/16 |
| `subnet` | Subnet donde viven los nodos AKS |
| `network_security_group` | Firewall: solo permite HTTP/HTTPS y tráfico interno |
| `log_analytics_workspace` | Recibe logs y métricas de AKS |
| `kubernetes_cluster` | El cluster AKS con autoscaling |
| `role_assignment` | Da permiso al AKS para pull del ACR (Zero Trust) |

**Puntos clave:**
- `admin_enabled = false` en ACR: Usamos Managed Identity, no passwords
- `identity { type = "SystemAssigned" }`: Azure crea identidad automática
- `kubelet_identity[0].object_id`: La identidad que usa kubelet para pull de imágenes
- `network_policy = "calico"`: Permite crear políticas de red entre pods

**🎤 Pregunta entrevista**: "¿Cómo aseguras comunicación AKS-ACR sin passwords?"
> "Uso System-assigned Managed Identity. AKS tiene identidad automática, le asigno rol AcrPull en el ACR. Azure valida la identidad, no hay secrets que puedan ser comprometidos. Zero Trust."

---

### 📝 Paso 1.5: Crear outputs.tf

Crea `terraform/outputs.tf`:

```hcl
output "resource_group_name" {
  description = "Nombre del Resource Group"
  value       = azurerm_resource_group.main.name
}

output "acr_login_server" {
  description = "URL del ACR"
  value       = azurerm_container_registry.main.login_server
}

output "acr_name" {
  description = "Nombre del ACR"
  value       = azurerm_container_registry.main.name
}

output "aks_cluster_name" {
  description = "Nombre del cluster AKS"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_cluster_id" {
  description = "ID del cluster AKS"
  value       = azurerm_kubernetes_cluster.main.id
}

output "aks_get_credentials_command" {
  description = "Comando para configurar kubectl"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}

output "acr_login_command" {
  description = "Comando para login a ACR"
  value       = "az acr login --name ${azurerm_container_registry.main.name}"
}
```

**📚 Notas sobre outputs.tf:**
- Los outputs muestran valores importantes después del apply
- `aks_get_credentials_command`: Te da el comando listo para copiar
- Útiles para scripts y pipelines CI/CD

---

### 🚀 Paso 1.6: Desplegar la infraestructura

```powershell
cd "c:\Users\Daniel Matapi\cloud-practice\azure-voting-app-redis\terraform"

terraform init
terraform validate
terraform plan
terraform apply

terraform output
```

**Tiempo estimado**: ~5-10 minutos

---

### ✅ Checklist Fase 1

- [ ] `terraform/providers.tf` creado
- [ ] `terraform/variables.tf` creado
- [ ] `terraform/main.tf` creado
- [ ] `terraform/outputs.tf` creado
- [ ] `terraform init` exitoso
- [ ] `terraform validate` sin errores
- [ ] `terraform apply` completado
- [ ] Puedo ver recursos en Azure Portal

---

## FASE 2: CONTAINERIZACIÓN

### 🎓 Conceptos Clave

| Concepto | Qué es | Por qué importa |
|----------|--------|-----------------|
| **Dockerfile** | Receta para construir imagen | Reproducible, versionable |
| **Multi-stage build** | Múltiples FROM, imagen final mínima | Reduce tamaño y superficie de ataque |
| **Non-root user** | Usuario sin privilegios | Seguridad: limita daño si hay exploit |
| **HEALTHCHECK** | Verificación de salud en imagen | K8s puede usarlo para probes |

---

### 📝 Paso 2.1: Crear requirements.txt

Crea `azure-vote/azure-vote/requirements.txt`:

```
Flask==2.3.3
redis==5.0.1
gunicorn==21.2.0
Werkzeug==2.3.7
```

---

### 📝 Paso 2.2: Actualizar Dockerfile

Reemplaza `azure-vote/Dockerfile` con:

```dockerfile
FROM python:3.11-slim as builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY azure-vote/requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

FROM python:3.11-slim

LABEL maintainer="Daniel Matapi" \
      version="1.0" \
      description="Azure Vote Frontend"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/home/appuser/.local/bin:$PATH"

RUN groupadd --gid 1000 appgroup && \
    useradd --uid 1000 --gid appgroup --shell /bin/bash --create-home appuser

WORKDIR /app

COPY --from=builder /root/.local /home/appuser/.local
COPY azure-vote/azure-vote/ /app/

RUN chown -R appuser:appgroup /app
USER appuser

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:80/')" || exit 1

CMD ["python", "main.py"]
```

**📚 Notas sobre Dockerfile:**
- **Stage 1 (builder)**: Instala dependencias, incluye gcc para compilar
- **Stage 2 (runtime)**: Solo copia lo necesario, sin gcc
- `--from=builder`: Copia desde el stage anterior
- `USER appuser`: Corre como non-root (seguridad)
- `HEALTHCHECK`: Docker/K8s pueden verificar salud

**🎤 Pregunta entrevista**: "¿Por qué usuario non-root?"
> "Si un atacante explota vulnerabilidad, obtiene permisos del proceso. Con root podría modificar sistema o escalar. Con appuser el daño está contenido. Además, muchos clusters K8s rechazan contenedores root."

---

### 📝 Paso 2.3: Actualizar main.py

Edita la última parte de `azure-vote/azure-vote/main.py`:

```python
if __name__ == "__main__":
    app.run(host='0.0.0.0', port=80)
```

---

### 🚀 Paso 2.4: Build y Push a ACR

```powershell
cd "c:\Users\Daniel Matapi\cloud-practice\azure-voting-app-redis"

cd terraform
$ACR_NAME = terraform output -raw acr_name
$ACR_LOGIN_SERVER = terraform output -raw acr_login_server
cd ..

Write-Host "ACR Name: $ACR_NAME"
Write-Host "ACR Server: $ACR_LOGIN_SERVER"

az acr login --name $ACR_NAME

cd azure-vote
docker build -t azure-vote-front:local .

$IMAGE_SHA = docker inspect --format='{{.Id}}' azure-vote-front:local
$SHORT_SHA = $IMAGE_SHA.Substring(7, 12)
Write-Host "Image SHA: $SHORT_SHA"

docker tag azure-vote-front:local "${ACR_LOGIN_SERVER}/azure-vote-front:${SHORT_SHA}"
docker tag azure-vote-front:local "${ACR_LOGIN_SERVER}/azure-vote-front:latest"

docker push "${ACR_LOGIN_SERVER}/azure-vote-front:${SHORT_SHA}"
docker push "${ACR_LOGIN_SERVER}/azure-vote-front:latest"

az acr repository list --name $ACR_NAME --output table
az acr repository show-tags --name $ACR_NAME --repository azure-vote-front --output table

cd ..
```

---

### ✅ Checklist Fase 2

- [ ] `requirements.txt` creado
- [ ] `Dockerfile` actualizado
- [ ] `main.py` actualizado
- [ ] `docker build` exitoso
- [ ] `az acr login` exitoso
- [ ] Imagen en ACR (verificar en Portal)

---

## FASE 3: KUBERNETES MANIFESTS

### 🎓 Conceptos Clave

| Concepto | Qué es | Cuándo usar |
|----------|--------|-------------|
| **Pod** | Unidad mínima, efímero | Casi nunca directamente |
| **Deployment** | Controla pods, replicas, updates | Siempre para apps |
| **Service** | IP estable, load balancing | Para exponer pods |
| **ClusterIP** | Solo acceso interno | Backend (Redis) |
| **LoadBalancer** | IP pública | Frontend |
| **ConfigMap** | Configuración no sensible | Variables de app |
| **HPA** | Autoscaling de pods | Producción |
| **Liveness probe** | ¿Está vivo? | Reinicia si falla |
| **Readiness probe** | ¿Está listo? | Remueve del LB si falla |

---

### 📝 Paso 3.1: namespace.yaml

Crea `k8s/base/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: voting-app
  labels:
    app: voting-app
    env: development
```

---

### 📝 Paso 3.2: configmap.yaml

Crea `k8s/base/configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: voting-app-config
  namespace: voting-app
data:
  TITLE: "Azure Voting App - DevSecOps Demo"
  VOTE1VALUE: "Terraform"
  VOTE2VALUE: "ARM Templates"
  SHOWHOST: "true"
```

---

### 📝 Paso 3.3: redis-deployment.yaml

Crea `k8s/base/redis-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: voting-app
  labels:
    app: redis
    tier: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
        tier: backend
    spec:
      containers:
      - name: redis
        image: mcr.microsoft.com/oss/bitnami/redis:6.0.8
        ports:
        - containerPort: 6379
          name: redis
        env:
        - name: ALLOW_EMPTY_PASSWORD
          value: "yes"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 250m
            memory: 256Mi
        livenessProbe:
          tcpSocket:
            port: 6379
          initialDelaySeconds: 15
          periodSeconds: 20
        readinessProbe:
          tcpSocket:
            port: 6379
          initialDelaySeconds: 5
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: voting-app
  labels:
    app: redis
spec:
  type: ClusterIP
  ports:
  - port: 6379
    targetPort: 6379
  selector:
    app: redis
```

**📚 Notas:**
- `ClusterIP`: Solo acceso interno (otros pods pueden conectar a `redis:6379`)
- `resources`: Requests = mínimo garantizado, Limits = máximo permitido
- `ALLOW_EMPTY_PASSWORD`: Solo para práctica, producción usa password

---

### 📝 Paso 3.4: frontend-deployment.yaml

Crea `k8s/base/frontend-deployment.yaml`:

**⚠️ IMPORTANTE**: Reemplaza `<TU_ACR_SERVER>` con tu valor (ej: `votingappdevacr.azurecr.io`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: voting-app
  labels:
    app: frontend
    tier: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: frontend
        tier: frontend
    spec:
      containers:
      - name: frontend
        image: <TU_ACR_SERVER>/azure-vote-front:latest
        ports:
        - containerPort: 80
        envFrom:
        - configMapRef:
            name: voting-app-config
        env:
        - name: REDIS
          value: "redis"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
```

**📚 Notas:**
- `replicas: 2`: Alta disponibilidad
- `maxSurge: 1, maxUnavailable: 0`: Durante update, siempre hay 2 pods
- `envFrom`: Inyecta todas las variables del ConfigMap
- `env REDIS`: Nombre del Service de Redis

---

### 📝 Paso 3.5: frontend-service.yaml

Crea `k8s/base/frontend-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: voting-app
  labels:
    app: frontend
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
  selector:
    app: frontend
```

---

### 📝 Paso 3.6: hpa.yaml

Crea `k8s/base/hpa.yaml`:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: frontend-hpa
  namespace: voting-app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: frontend
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
```

**📚 Notas:**
- Escala cuando CPU > 70% o Memory > 80%
- `stabilizationWindowSeconds: 300` en scaleDown: Evita scale down prematuro
- `stabilizationWindowSeconds: 0` en scaleUp: Scale up inmediato

---

### 🚀 Paso 3.7: Deploy a AKS

```powershell
cd "c:\Users\Daniel Matapi\cloud-practice\azure-voting-app-redis"

cd terraform
$RG_NAME = terraform output -raw resource_group_name
$AKS_NAME = terraform output -raw aks_cluster_name
$ACR_LOGIN_SERVER = terraform output -raw acr_login_server
cd ..

az aks get-credentials --resource-group $RG_NAME --name $AKS_NAME --overwrite-existing

kubectl get nodes

Write-Host "`n>>> EDITA frontend-deployment.yaml y reemplaza <TU_ACR_SERVER> con: $ACR_LOGIN_SERVER`n"

# Después de editar:
kubectl apply -f k8s/base/namespace.yaml
kubectl apply -f k8s/base/configmap.yaml
kubectl apply -f k8s/base/redis-deployment.yaml
kubectl apply -f k8s/base/frontend-deployment.yaml
kubectl apply -f k8s/base/frontend-service.yaml
kubectl apply -f k8s/base/hpa.yaml

kubectl get all -n voting-app

# Espera la IP pública (~2 min)
kubectl get svc frontend -n voting-app -w
```

---

### ✅ Checklist Fase 3

- [ ] Todos los YAML creados en `k8s/base/`
- [ ] `frontend-deployment.yaml` tiene el ACR correcto
- [ ] kubectl conectado
- [ ] `kubectl apply` exitoso
- [ ] LoadBalancer tiene EXTERNAL-IP
- [ ] La app funciona en el navegador

---

## 🎤 Resumen Preguntas Entrevista Fases 1-3

| Tema | Pregunta | Tu respuesta clave |
|------|----------|-------------------|
| IaC | ¿Ventajas de Terraform? | Reproducibilidad, Git history, plan antes de apply |
| IaC | ¿Backend remoto para qué? | Colaboración, locking, encryption del state |
| Security | ¿Zero Trust AKS-ACR? | Managed Identity + rol AcrPull, sin passwords |
| Docker | ¿Multi-stage build? | Reduce tamaño, menos superficie de ataque |
| Docker | ¿Non-root user? | Contiene daño si hay exploit |
| K8s | ¿Rolling update vs Recreate? | Rolling = zero downtime |
| K8s | ¿Liveness vs Readiness? | Liveness reinicia, Readiness remueve del LB |

---

## 💡 Al terminar hoy

```powershell
cd "c:\Users\Daniel Matapi\cloud-practice\azure-voting-app-redis\terraform"
terraform destroy -auto-approve
```

---

<!-- TODO: Fases 4-8 para Sábado y Domingo - Daniel debe avisar cuando complete Fases 1-3 -->
