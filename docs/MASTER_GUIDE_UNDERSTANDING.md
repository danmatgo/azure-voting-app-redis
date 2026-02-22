# 🧠 GUÍA MAESTRA: DevSecOps End-to-End
## Entendimiento Profundo de Infraestructura, Containers, Kubernetes y CI/CD

> **Propósito**: Entender el POR QUÉ de cada decisión técnica, no solo el cómo.

---

# 📖 TABLA DE CONTENIDOS

1. [La Arquitectura Completa](#la-arquitectura-completa)
2. [Fase 1: Terraform - Por qué IaC importa](#fase-1-terraform)
3. [Fase 2: Contenedores - Más que solo Docker](#fase-2-contenedores)
4. [Fase 3: Kubernetes - Orquestación real](#fase-3-kubernetes)
5. [Mejoras Enterprise](#mejoras-enterprise)
6. [Fase 4: CI/CD - Automatización inteligente](#fase-4-cicd)
7. [Fase 5: DevSecOps - Seguridad integrada](#fase-5-devsecops)
8. [Problemas y Soluciones](#problemas-y-soluciones)
9. [Cómo explicar todo en una entrevista](#como-explicar-en-entrevista)

---

# 🏗️ LA ARQUITECTURA COMPLETA

## ¿Qué construimos?

Una aplicación de votación con arquitectura de microservicios:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AZURE CLOUD                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    AZURE KUBERNETES SERVICE                   │   │
│  │  ┌─────────────────┐           ┌─────────────────┐           │   │
│  │  │    FRONTEND     │           │      REDIS      │           │   │
│  │  │   (Python/Flask)│──────────▶│    (Cache DB)   │           │   │
│  │  │                 │           │                 │           │   │
│  │  │  Port 8080      │           │    Port 6379    │           │   │
│  │  └─────────────────┘           └─────────────────┘           │   │
│  │           ▲                                                   │   │
│  │           │ ClusterIP                                         │   │
│  │  ┌────────┴────────┐                                          │   │
│  │  │  LoadBalancer   │◀──────── Internet                        │   │
│  │  │    (Port 80)    │                                          │   │
│  │  └─────────────────┘                                          │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │     ACR      │    │   Key Vault  │    │  Log Analytics│         │
│  │  (Imágenes)  │    │  (Secretos)  │    │  (Monitoring) │         │
│  └──────────────┘    └──────────────┘    └──────────────┘          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## El flujo de un usuario

```
1. Usuario abre http://IP_PUBLICA
2. Load Balancer recibe la petición
3. Rutea al pod del frontend (hay varios por HA)
4. Frontend consulta/actualiza votos en Redis
5. Frontend renderiza HTML con los resultados
6. Respuesta vuelve al usuario
```

---

# 🔧 FASE 1: TERRAFORM

## ¿Por qué Infrastructure as Code?

Antes de IaC, la infraestructura se creaba manualmente en el portal de Azure. Problemas:

| Sin IaC | Con IaC (Terraform) |
|---------|---------------------|
| "Funciona en mi cuenta" | Reproducible en cualquier cuenta |
| Documentación desactualizada | El código ES la documentación |
| Cambios no rastreables | Git history de cada cambio |
| Rollback manual y arriesgado | `terraform apply` de versión anterior |
| Horas configurando manualmente | Minutos ejecutando código |

## Estructura de archivos Terraform

```
terraform/
├── providers.tf      # Dónde y cómo conectarse
├── variables.tf      # Inputs configurables
├── main.tf           # Recursos a crear
├── outputs.tf        # Valores de salida
└── environments/
    ├── dev.tfvars    # Valores para desarrollo
    └── prod.tfvars   # Valores para producción
```

### providers.tf - La conexión

```hcl
terraform {
  required_version = ">= 1.0"
  
  backend "azurerm" {
    # Dónde guardar el estado
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatevoting2390"
    container_name       = "tfstate"
    key                  = "votingapp-dev.tfstate"
  }
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"  # ~> significa >= 3.0.0 y < 4.0.0
    }
  }
}
```

**¿Por qué `~> 3.0`?**: Permite actualizaciones menores (3.1, 3.2) que son backwards compatible, pero bloquea 4.0 que podría tener breaking changes.

### variables.tf - Parametrización

```hcl
variable "environment" {
  description = "Ambiente de despliegue"
  type        = string
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Ambiente debe ser dev, staging, o prod."
  }
}

variable "aks_node_vm_size" {
  description = "Tamaño de VM para nodos AKS"
  type        = string
  default     = "Standard_D2as_v4"
}
```

**¿Por qué validaciones?**: Previene errores costosos. Si alguien escribe "produccion" en vez de "prod", Terraform falla antes de crear recursos incorrectos.

### main.tf - Los recursos

```hcl
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(var.tags, {
    Environment = var.environment
  })
}

# Resource Group - Contenedor lógico de recursos
resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.common_tags
}

# Container Registry - Almacén de imágenes Docker
resource "azurerm_container_registry" "main" {
  name                = "${var.project_name}${var.environment}acr"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false  # ¡Importante! Usar Managed Identity, no admin
  tags                = local.common_tags
}
```

**¿Por qué `admin_enabled = false`?**: La autenticación con admin user y password es insegura. Usamos Managed Identity que no requiere credenciales.

### El AKS Cluster

```hcl
resource "azurerm_kubernetes_cluster" "main" {
  name                = "${local.name_prefix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${local.name_prefix}-aks"
  kubernetes_version  = "1.32.0"

  default_node_pool {
    name                = "system"
    vm_size             = var.aks_node_vm_size
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = var.aks_enable_autoscaling
    node_count          = var.aks_enable_autoscaling ? null : var.aks_node_count
    min_count           = var.aks_enable_autoscaling ? var.aks_min_nodes : null
    max_count           = var.aks_enable_autoscaling ? var.aks_max_nodes : null
  }

  identity {
    type = "SystemAssigned"  # AKS crea su propia identidad
  }

  network_profile {
    network_plugin = "kubenet"   # Más simple, suficiente para mayoría de casos
    network_policy = "calico"    # Habilita Network Policies
    pod_cidr       = "10.244.0.0/16"
    service_cidr   = "10.0.2.0/24"
    dns_service_ip = "10.0.2.10"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }
}
```

**Decisiones de diseño**:
- **System-assigned Managed Identity**: Azure crea y maneja la identidad automáticamente
- **Kubenet vs Azure CNI**: Kubenet es más simple y usa menos IPs. Azure CNI da cada pod una IP de la VNet (más complejo pero necesario para ciertas integraciones)
- **Calico**: Network Policy engine que permite reglas de firewall entre pods

### Role Assignment - Permisos

```hcl
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
```

**¿Por qué esto?**: El AKS necesita descargar imágenes del ACR. En lugar de usar credenciales, le asignamos un rol que le da permiso. Es el principio de **Least Privilege**: solo puede leer (Pull), no escribir (Push).

---

# 📦 FASE 2: CONTENEDORES

## ¿Por qué contenedores?

```
PROBLEMA CLÁSICO:
┌─────────────────┐     ┌─────────────────┐
│  Mi Máquina     │     │   Servidor      │
│                 │     │                 │
│  Python 3.11    │     │  Python 3.8     │
│  Flask 2.3      │ ══▶ │  Flask 2.0      │
│  Redis 4.5      │     │  Redis ???      │
│                 │     │                 │
│  "Funciona!"    │     │  "No funciona!" │
└─────────────────┘     └─────────────────┘

SOLUCIÓN CON CONTENEDORES:
┌─────────────────────────────────────────┐
│            CONTAINER IMAGE              │
│  ┌────────────────────────────────────┐ │
│  │  Python 3.11 + Flask 2.3 + App    │ │
│  │  Exactamente igual en todos lados │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
        ▼               ▼               ▼
     Mi PC          Staging          Prod
   (funciona)      (funciona)     (funciona)
```

## El Dockerfile explicado

```dockerfile
# === ETAPA 1: BUILD ===
FROM python:3.11-slim AS builder

WORKDIR /app

# Copiar SOLO requirements primero (optimización de cache)
COPY azure-vote/requirements.txt .

# Instalar dependencias en carpeta específica
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# === ETAPA 2: RUNTIME ===
FROM python:3.11-slim

# Metadatos de la imagen
LABEL maintainer="Daniel Matapi" \
      version="1.0" \
      description="Azure Voting App Frontend"

WORKDIR /app

# Crear usuario no-root ANTES de copiar archivos
RUN useradd --create-home --shell /bin/bash appuser

# Copiar dependencias desde builder
COPY --from=builder /install /usr/local

# Copiar código de la aplicación
COPY azure-vote/ .

# Cambiar ownership y usuario
RUN chown -R appuser:appuser /app
USER appuser

# Puerto que expone la app
EXPOSE 8080

# Health check - K8s y Docker pueden verificar que la app está viva
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/')" || exit 1

# Comando para iniciar la app
CMD ["python", "main.py"]
```

### ¿Por qué Multi-Stage Build?

```
SIN MULTI-STAGE:                    CON MULTI-STAGE:
┌────────────────────┐              ┌────────────────────┐
│ Image final        │              │ Build stage        │
│                    │              │ (se descarta)      │
│ - GCC, make, etc   │              │ - GCC, make, etc   │
│ - headers          │              │ - headers          │
│ - pip cache        │              │ - pip cache        │
│ - app + deps       │              └────────────────────┘
│                    │                       │
│ TAMAÑO: 1.2 GB     │              ┌────────┴───────────┐
└────────────────────┘              │ Runtime stage      │
                                    │ (imagen final)     │
                                    │                    │
                                    │ - python slim      │
                                    │ - app + deps       │
                                    │                    │
                                    │ TAMAÑO: 180 MB     │
                                    └────────────────────┘
```

### ¿Por qué usuario no-root?

```
CON ROOT:                           SIN ROOT:
┌────────────────────┐              ┌────────────────────┐
│ Container          │              │ Container          │
│ USER: root         │              │ USER: appuser      │
│                    │              │                    │
│ Si atacante entra: │              │ Si atacante entra: │
│ - Acceso total     │              │ - Solo /app        │
│ - Puede escapar    │              │ - No puede escapar │
│ - Daño ilimitado   │              │ - Daño limitado    │
└────────────────────┘              └────────────────────┘
```

## requirements.txt - Versiones pinned

```txt
Flask==2.3.3
redis==4.6.0
gunicorn==21.2.0
Werkzeug==2.3.7
```

**¿Por qué versiones exactas?**: 
- `Flask>=2.0` podría instalar Flask 3.0 mañana y romper la app
- Versiones exactas garantizan reproducibilidad
- En producción siempre quieres saber EXACTAMENTE qué tienes

---

# ☸️ FASE 3: KUBERNETES

## ¿Por qué Kubernetes?

Docker solo corre contenedores. Kubernetes los **orquesta**:

| Docker Solo | Kubernetes |
|-------------|------------|
| 1 contenedor en 1 servidor | N contenedores en N servidores |
| Se muere → se queda muerto | Se muere → se recrea automáticamente |
| Escalar manualmente | Escalar automáticamente basado en métricas |
| Balanceo manual | Service Discovery y Load Balancing built-in |
| Updates arriesgados | Rolling updates sin downtime |

## Namespace - Aislamiento lógico

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: voting-app
  labels:
    app: voting-app
    environment: dev
```

**¿Por qué?**: Evita colisiones de nombres. Puedes tener `voting-app/frontend` y `otra-app/frontend` sin conflictos.

## ConfigMap - Configuración externa

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: voting-app-config
  namespace: voting-app
data:
  TITLE: "Azure Voting App"
  VOTE1VALUE: "Cats"
  VOTE2VALUE: "Dogs"
```

**¿Por qué ConfigMap?**: Separar configuración del código. Puedes cambiar los valores de votación sin reconstruir la imagen.

## Deployment - El controlador de pods

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: voting-app
spec:
  replicas: 2
  
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0    # Nunca menos de 2 pods
      maxSurge: 1          # Máximo 3 pods temporalmente
  
  selector:
    matchLabels:
      app: frontend
  
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: frontend
          image: votingappdevacr.azurecr.io/azure-vote-front:latest
          imagePullPolicy: Always
          
          ports:
            - containerPort: 8080
          
          envFrom:
            - configMapRef:
                name: voting-app-config
          
          env:
            - name: REDIS
              value: "redis"
          
          resources:
            requests:
              cpu: 100m      # Mínimo garantizado
              memory: 128Mi
            limits:
              cpu: 500m      # Máximo permitido
              memory: 256Mi
          
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 10
          
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
```

### Explicación de cada sección:

**replicas: 2**
- Siempre hay 2 pods corriendo → Alta disponibilidad
- Si uno muere, el otro sigue sirviendo mientras se recrea

**RollingUpdate strategy**
```
Estado inicial:     [Pod1-v1] [Pod2-v1]
Creando nuevo:      [Pod1-v1] [Pod2-v1] [Pod3-v2]
Eliminando viejo:   [Pod2-v1] [Pod3-v2]
Creando nuevo:      [Pod2-v1] [Pod3-v2] [Pod4-v2]
Eliminando viejo:   [Pod3-v2] [Pod4-v2]
→ ZERO DOWNTIME
```

**resources (requests vs limits)**
```
requests: Lo que Kubernetes GARANTIZA
limits: Lo MÁXIMO que puede usar

Si pones limits muy bajos → OOMKilled (Out of Memory)
Si pones requests muy altos → No schedula en nodos pequeños
```

**livenessProbe vs readinessProbe**
```
livenessProbe:
- "¿Está vivo el proceso?"
- Si falla → K8s MATA el pod y crea uno nuevo

readinessProbe:
- "¿Está listo para recibir tráfico?"
- Si falla → K8s DEJA DE ENVIAR tráfico (pero no mata el pod)
```

## Service - Networking

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  type: LoadBalancer
  ports:
    - port: 80           # Puerto expuesto externamente
      targetPort: 8080   # Puerto del contenedor
  selector:
    app: frontend        # Envía tráfico a pods con este label
```

**Tipos de Service**:
```
ClusterIP (default):
  Solo accesible dentro del cluster
  Ej: Redis no necesita acceso externo

NodePort:
  Abre un puerto en cada nodo
  Útil para testing, no para producción

LoadBalancer:
  Crea un Load Balancer en la nube
  IP pública accesible desde internet
```

## HPA - Horizontal Pod Autoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: frontend-hpa
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
```

**¿Cómo funciona?**
```
CPU promedio > 70% → Agregar pods (hasta 10)
CPU promedio < 70% → Reducir pods (mínimo 2)

Ejemplo:
- 2 pods al 90% CPU → HPA crea pod 3
- 3 pods al 60% CPU → HPA mantiene 3
- 3 pods al 20% CPU → HPA reduce a 2
```

---

# 🏢 MEJORAS ENTERPRISE

## 1. Remote Backend

**Problema**: Estado de Terraform guardado localmente
```
Dev1: terraform apply → crea RG
Dev2: terraform apply → NO VE el RG → CONFLICTO
```

**Solución**: Estado en Azure Storage con locking
```
Dev1: terraform apply → lock → crea RG → unlock
Dev2: terraform apply → WAIT (locked) → ve cambios de Dev1
```

## 2. Kustomize

**Problema**: Copiar manifests para cada ambiente
```
k8s/dev/deployment.yaml   (100 líneas)
k8s/prod/deployment.yaml  (100 líneas, cambios mínimos)
→ Mantener 2 archivos casi iguales
```

**Solución**: Base + overlays
```
k8s/base/deployment.yaml  (100 líneas)
k8s/overlays/dev/kustomization.yaml (10 líneas de parches)
k8s/overlays/prod/kustomization.yaml (10 líneas de parches)
```

## 3. PodDisruptionBudget

**Problema**: Durante upgrade de nodos, K8s puede matar todos los pods
```
Node upgrade → drain → todos los pods de frontend mueren → DOWNTIME
```

**Solución**: PDB garantiza mínimo disponible
```yaml
spec:
  minAvailable: 1  # Siempre al menos 1 pod vivo
```

---

# 🔄 FASE 4: CI/CD

## La filosofía

```
ANTES (manual):
Dev → git push → esperar → ir a servidor → pull → build → test → deploy
                           ↓
                    "Olvidé correr los tests"
                    "El build falló en producción"

AHORA (CI/CD):
Dev → git push → [AUTOMÁTICO: test → build → scan → deploy]
                           ↓
                    Feedback en minutos
                    Mismo proceso siempre
```

## OIDC - Autenticación sin secretos

**Problema con secrets**:
```
GitHub Secret: AZURE_PASSWORD=MiPasswordSuperSecreto123
                    ↓
¿Quién tiene acceso? ¿Cuándo se rota? ¿Qué pasa si GitHub se compromete?
```

**Solución OIDC**:
```
GitHub: "Soy el repo X, branch Y, usuario Z"
Azure: *verifica la firma de GitHub*
Azure: "OK, aquí tienes un token válido por 15 minutos"
→ No hay password almacenado
→ Token temporal limita el daño si algo sale mal
```

## El Workflow explicado

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [master]
    paths: ['azure-vote/**', 'k8s/**']  # Solo si cambian estos archivos
  workflow_dispatch:  # Permite ejecutar manualmente

permissions:
  id-token: write    # Necesario para OIDC
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      image-tag: ${{ steps.meta.outputs.tag }}  # Pasa el tag al job deploy
    
    steps:
      - uses: actions/checkout@v4
      
      # Generar tag único basado en commit SHA
      - name: Set image tag
        id: meta
        run: |
          SHORT_SHA=$(echo ${{ github.sha }} | cut -c1-7)
          echo "tag=ACR/IMAGE:${SHORT_SHA}" >> $GITHUB_OUTPUT
      
      # Login a Azure usando OIDC
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      
      # Build sin pushear (para escanear primero)
      - uses: docker/build-push-action@v5
        with:
          push: false
          load: true
          tags: ${{ steps.meta.outputs.tag }}
      
      # Escanear ANTES de pushear
      - uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ steps.meta.outputs.tag }}
          severity: 'CRITICAL,HIGH'
      
      # Solo pushea si el scan pasa
      - run: docker push ${{ steps.meta.outputs.tag }}

  deploy:
    needs: build  # Espera a que build termine
    if: github.ref == 'refs/heads/master'  # Solo en master
    
    steps:
      # Configurar kubectl
      - name: Setup Kubeconfig
        run: |
          echo "${{ secrets.KUBE_CONFIG }}" | base64 -d > ~/.kube/config
      
      # Actualizar imagen y desplegar
      - name: Deploy
        run: |
          cd k8s/overlays/dev
          kustomize edit set image IMAGE=${{ needs.build.outputs.image-tag }}
          kubectl apply -k .
      
      # Verificar que el deploy fue exitoso
      - run: kubectl rollout status deployment/frontend -n voting-app
```

---

# 🔒 FASE 5: DEVSECOPS

## Shift-Left Security

```
ANTES (seguridad al final):
Dev → Build → Test → Deploy → SCAN → "Houston, tenemos problemas"
                                          ↓
                              Rollback, hotfix, caos

AHORA (shift-left):
Dev → SCAN → Build → SCAN → Test → SCAN → Deploy
       ↓
   Detectar temprano = Arreglar barato
```

## Trivy - Container Scanning

Escanea la imagen Docker buscando:
- CVEs en el sistema operativo base
- Vulnerabilidades en librerías (Flask, Redis, etc.)
- Configuraciones inseguras

```yaml
- uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ steps.meta.outputs.tag }}
    exit-code: '0'     # Reportar sin bloquear
    severity: 'CRITICAL,HIGH'
```

**¿Por qué exit-code 0?**: A veces hay vulnerabilidades en el OS base (Debian, Alpine) sin fix disponible. Bloquear el pipeline no soluciona el problema, pero sí lo documentamos.

## Dependabot - Dependency Scanning

Automáticamente:
1. Detecta dependencias desactualizadas
2. Verifica si tienen CVEs conocidos
3. Crea PRs con actualizaciones

## CodeQL - Static Analysis

Analiza el código Python buscando patrones inseguros:
- SQL Injection
- XSS
- Hardcoded credentials
- Path traversal

## Network Policies - Zero Trust Networking

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: redis-allow-frontend-only
spec:
  podSelector:
    matchLabels:
      app: redis
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - port: 6379
```

**¿Qué hace esto?**
```
SIN Network Policy:
  Cualquier pod → puede hablar con → Redis
  (un atacante en cualquier pod puede robar datos)

CON Network Policy:
  Solo frontend → puede hablar con → Redis
  Todo lo demás → BLOQUEADO
```

---

# 🔧 PROBLEMAS Y SOLUCIONES

## 1. Error de permisos en Entra ID

**Síntoma**:
```
az ad app create --display-name "test"
ERROR: Insufficient privileges
```

**Causa**: La cuenta no tiene rol de Application Administrator o Global Admin.

**Solución**: En entornos enterprise, solicitar permisos elevados temporales, o usar una cuenta de servicio con los permisos necesarios por separado.

## 2. Trivy bloqueando el pipeline

**Síntoma**:
```
CRITICAL: libssl3 CVE-2024-XXXX
Pipeline: FAILED
```

**Causa**: Vulnerabilidad en la imagen base de Debian sin parche disponible.

**Soluciones aplicables**:
1. Cambiar a imagen base más segura (Alpine, Distroless)
2. Si no hay parche, documentar la excepción y monitorear
3. Configurar Trivy para reportar sin bloquear (decisión de riesgo aceptado)

## 3. Deployment fallando con imagen incorrecta

**Síntoma**:
```
ImagePullBackOff
```

**Causas comunes**:
1. Nombre de imagen mal escrito
2. AKS no tiene permisos para pull del ACR
3. La imagen no existe en el registry

**Verificación**:
```bash
# ¿Existe la imagen?
az acr repository show-tags --name MYACR --repository IMAGE

# ¿Tiene permisos el AKS?
az role assignment list --scope /subscriptions/X/resourceGroups/Y/providers/Microsoft.ContainerRegistry/registries/Z
```

## 4. Pod en CrashLoopBackOff

**Síntoma**: Pod reiniciándose constantemente

**Diagnóstico**:
```bash
kubectl describe pod POD_NAME -n NAMESPACE
kubectl logs POD_NAME -n NAMESPACE --previous
```

**Causas comunes**:
1. Aplicación crashea al iniciar (error de código)
2. Variable de entorno faltante
3. No puede conectar a dependencia (Redis)
4. Recursos insuficientes (OOMKilled)

## 5. Cross-account deployment

**Situación**: ACR en una cuenta, AKS en otra.

**Solución implementada**:
1. OIDC para autenticar contra la cuenta del ACR
2. Kubeconfig exportado como secret para acceder al AKS
3. El workflow usa ambos métodos en jobs separados

---

# 🎤 CÓMO EXPLICAR EN ENTREVISTA

## Sobre IaC y Terraform

> "La infraestructura la manejo como código con Terraform. Uso remote backend en Azure Storage para el state compartido con locking, lo cual evita condiciones de carrera cuando múltiples personas trabajan en la infraestructura. Para manejar ambientes, uso tfvars separados con un archivo de variables por ambiente, entonces el mismo código despliega a dev, staging o prod con diferentes configuraciones."

## Sobre Contenedores

> "Para containerización uso multi-stage builds que reducen el tamaño de imagen significativamente - pasé de más de un GB a menos de 200MB eliminando herramientas de build del runtime. Las imágenes corren con usuario no-root para limitar el blast radius en caso de compromiso. Versiono las dependencias exactas en requirements.txt para garantizar reproducibilidad."

## Sobre Kubernetes

> "Uso Deployments con rolling updates configurados para zero-downtime. Tengo liveness y readiness probes diferenciados - liveness para detectar si el proceso murió, readiness para control de tráfico durante startups lentos. Los recursos están definidos con requests y limits para evitar noisy neighbors. Para configuración uso ConfigMaps y para secretos, integración con Key Vault."

## Sobre CI/CD

> "El pipeline usa GitHub Actions con OIDC para autenticación contra Azure - no hay secrets de credenciales almacenados, solo tokens de corta duración. El flujo es: build de imagen, scan de vulnerabilidades con Trivy antes de push, y deploy a Kubernetes usando Kustomize para aplicar configuraciones específicas del ambiente."

## Sobre Seguridad

> "Implemento shift-left security: escaneo de contenedores antes de push, análisis estático de código con CodeQL, y Dependabot para dependencias. En Kubernetes uso Network Policies para microsegmentación - por ejemplo, solo el frontend puede hablar con Redis. Los pods corren con security context hardened y PodDisruptionBudgets garantizan disponibilidad durante mantenimiento."

## Sobre troubleshooting

> "Para debugging en K8s mi flujo típico es: kubectl get pods para ver estado, describe para eventos y condiciones, logs para errores de aplicación. Si necesito investigar más, hago exec al container o creo un pod de debug. Para problemas de red, verifico Network Policies y uso pods efímeros con curl o nslookup."

---

# ✅ CHECKLIST DE CONOCIMIENTOS

| Tema | ¿Puedo explicar el POR QUÉ? | ¿Puedo resolver problemas? |
|------|----------------------------|---------------------------|
| Terraform state y locking | ☐ | ☐ |
| tfvars y ambientes | ☐ | ☐ |
| Multi-stage Dockerfile | ☐ | ☐ |
| Usuario no-root en containers | ☐ | ☐ |
| Deployment vs Pod | ☐ | ☐ |
| Rolling updates | ☐ | ☐ |
| Liveness vs Readiness probes | ☐ | ☐ |
| Requests vs Limits | ☐ | ☐ |
| Service types | ☐ | ☐ |
| HPA | ☐ | ☐ |
| Kustomize overlays | ☐ | ☐ |
| OIDC | ☐ | ☐ |
| Trivy y container scanning | ☐ | ☐ |
| Network Policies | ☐ | ☐ |

---

**Recuerda**: No memorizas comandos, entiendes sistemas. La entrevista busca gente que entiende el **por qué**, no solo el **cómo**.
