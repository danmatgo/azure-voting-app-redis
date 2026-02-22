# 🚀 Guía Práctica Sábado
## Mañana: Enterprise Catch-up (Fases 1-3) | Tarde: Fases 4-5

---

# ☀️ MAÑANA: Mejoras Enterprise a Fases 1-3

> **Objetivo**: Llevar lo que hiciste ayer a nivel enterprise
> **Tiempo**: ~2.5 horas

---

## 🔧 Paso 0: Recrear Infraestructura Base (10 min)

```powershell
cd "c:\Users\Daniel Matapi\cloud-practice\azure-voting-app-redis\terraform"
terraform init
terraform apply -auto-approve
# Espera ~5-10 min
terraform output
```

---

## 🏢 Mejora 1: Remote Backend (30 min)

### ¿Qué es?
En lugar de guardar el state en tu máquina local, lo guardas en Azure Storage donde todo el equipo puede accederlo con locking automático.

### ¿Por qué es enterprise?
```
LOCAL STATE:                     REMOTE STATE:
┌─────────┐                     ┌─────────┐
│ Dev 1   │─terraform.tfstate   │ Dev 1   │─┐
├─────────┤                     ├─────────┤ │
│ Dev 2   │─terraform.tfstate   │ Dev 2   │─┼──▶ Azure Storage
├─────────┤  (conflictos!)      ├─────────┤ │    (una sola fuente)
│ Dev 3   │─terraform.tfstate   │ Dev 3   │─┘
└─────────┘                     └─────────┘
```

### Paso 1.1: Crear Storage Account para el State

```powershell
# Variables
$TFSTATE_RG = "tfstate-rg"
$TFSTATE_SA = "tfstatevoting$(Get-Random -Maximum 9999)"  # Nombre único
$TFSTATE_CONTAINER = "tfstate"
$LOCATION = "eastus"

# Crear Resource Group para el state (separado del proyecto)
az group create --name $TFSTATE_RG --location $LOCATION

# Crear Storage Account
az storage account create `
    --name $TFSTATE_SA `
    --resource-group $TFSTATE_RG `
    --location $LOCATION `
    --sku Standard_LRS `
    --encryption-services blob

# Crear Container
az storage container create `
    --name $TFSTATE_CONTAINER `
    --account-name $TFSTATE_SA

# Mostrar valores
Write-Host ""
Write-Host "GUARDA ESTOS VALORES:"
Write-Host "storage_account_name = `"$TFSTATE_SA`""
Write-Host "container_name = `"$TFSTATE_CONTAINER`""
Write-Host "resource_group_name = `"$TFSTATE_RG`""
```

### Paso 1.2: Actualizar providers.tf

Edita `terraform/providers.tf` y agrega el backend:

```hcl
terraform {
  required_version = ">= 1.0"

  # BACKEND REMOTO - Guarda state en Azure Storage
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "TU_STORAGE_ACCOUNT"  # Reemplaza
    container_name       = "tfstate"
    key                  = "votingapp-dev.tfstate"
  }

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

### Paso 1.3: Migrar el state existente

```powershell
cd "c:\Users\Daniel Matapi\cloud-practice\azure-voting-app-redis\terraform"

# Reinicializa con el nuevo backend
terraform init -migrate-state

# Responde 'yes' cuando pregunte si quieres migrar

# Verifica que el state está en Azure
az storage blob list --account-name TU_STORAGE_ACCOUNT --container-name tfstate --output table
```

**✅ Listo!** Ya tienes Remote Backend.

---

## 🏢 Mejora 2: tfvars por Ambiente (15 min)

### ¿Qué es?
Archivos separados con configuración por ambiente (dev, staging, prod).

### Paso 2.1: Crear dev.tfvars

Crea `terraform/environments/dev.tfvars`:

```hcl
# Configuración para ambiente de desarrollo
project_name = "votingapp"
environment  = "dev"
location     = "eastus"

# AKS económico para dev
aks_node_count     = 1
aks_node_vm_size   = "Standard_B2s"
aks_min_nodes      = 1
aks_max_nodes      = 3

# Tags
tags = {
  Project     = "VotingApp"
  Environment = "Development"
  Owner       = "Daniel Matapi"
  CostCenter  = "Training"
  ManagedBy   = "Terraform"
}
```

### Paso 2.2: Crear prod.tfvars (ejemplo, no lo usaremos)

Crea `terraform/environments/prod.tfvars`:

```hcl
# Configuración para producción
project_name = "votingapp"
environment  = "prod"
location     = "eastus"

# AKS robusto para prod
aks_node_count     = 3
aks_node_vm_size   = "Standard_D4s_v3"
aks_min_nodes      = 3
aks_max_nodes      = 10

tags = {
  Project     = "VotingApp"
  Environment = "Production"
  Owner       = "Platform Team"
  CostCenter  = "Production"
  ManagedBy   = "Terraform"
}
```

### Paso 2.3: Usar tfvars

```powershell
# Cómo se usaría en la práctica:
terraform plan -var-file="environments/dev.tfvars"
terraform apply -var-file="environments/dev.tfvars"

# Para producción sería:
# terraform apply -var-file="environments/prod.tfvars"
```

**✅ Listo!** Ya tienes configuración por ambiente.

---

## 🏢 Mejora 3: Kustomize para K8s (45 min)

### ¿Qué es?
Herramienta nativa de K8s para manejar variaciones de manifests entre ambientes SIN duplicar código.

### ¿Por qué es enterprise?
```
SIN KUSTOMIZE:                    CON KUSTOMIZE:
k8s/                              k8s/
├── dev/                          ├── base/
│   ├── deployment.yaml           │   ├── deployment.yaml
│   ├── service.yaml              │   ├── service.yaml
│   └── (todo duplicado)          │   └── kustomization.yaml
├── staging/                      └── overlays/
│   ├── deployment.yaml               ├── dev/
│   └── (todo duplicado)              │   └── kustomization.yaml (solo cambios)
└── prod/                              ├── staging/
    └── (todo duplicado)               └── prod/
```

### Paso 3.1: Crear kustomization.yaml base

Crea `k8s/base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: voting-app

resources:
  - namespace.yaml
  - configmap.yaml
  - redis-deployment.yaml
  - frontend-deployment.yaml
  - frontend-service.yaml
  - hpa.yaml

commonLabels:
  app.kubernetes.io/managed-by: kustomize
```

### Paso 3.2: Crear overlay de dev

Crea `k8s/overlays/dev/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: voting-app

resources:
  - ../../base

namePrefix: dev-

commonLabels:
  environment: development

# Parches para dev: menos recursos, menos réplicas
patches:
  - patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: frontend
      spec:
        replicas: 1
        template:
          spec:
            containers:
              - name: frontend
                resources:
                  requests:
                    cpu: 50m
                    memory: 64Mi
                  limits:
                    cpu: 200m
                    memory: 128Mi
```

### Paso 3.3: Crear overlay de prod

Crea `k8s/overlays/prod/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: voting-app-prod

resources:
  - ../../base

namePrefix: prod-

commonLabels:
  environment: production

# Parches para prod: más recursos, más réplicas
patches:
  - patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: frontend
      spec:
        replicas: 3
        template:
          spec:
            containers:
              - name: frontend
                resources:
                  requests:
                    cpu: 200m
                    memory: 256Mi
                  limits:
                    cpu: 1000m
                    memory: 512Mi
```

### Paso 3.4: Probar Kustomize

```powershell
# Ve los manifests que generaría para dev (sin aplicar)
kubectl kustomize k8s/overlays/dev

# Ve los manifests que generaría para prod
kubectl kustomize k8s/overlays/prod

# Aplica el overlay de dev
kubectl apply -k k8s/overlays/dev

# Verifica
kubectl get all -n voting-app
```

**✅ Listo!** Ya tienes Kustomize.

---

## 🏢 Mejora 4: PodDisruptionBudget (10 min)

### ¿Qué es?
Garantiza disponibilidad mínima durante mantenimiento del cluster.

Crea `k8s/base/pdb.yaml`:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: frontend-pdb
  namespace: voting-app
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: frontend
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: redis-pdb
  namespace: voting-app
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: redis
```

Agrega a `k8s/base/kustomization.yaml`:

```yaml
resources:
  - namespace.yaml
  - configmap.yaml
  - redis-deployment.yaml
  - frontend-deployment.yaml
  - frontend-service.yaml
  - hpa.yaml
  - pdb.yaml  # Agregar esta línea
```

```powershell
kubectl apply -k k8s/overlays/dev
kubectl get pdb -n voting-app
```

---

## 🏢 Mejora 5: .dockerignore (5 min)

Crea `azure-vote/.dockerignore`:

```
# Git
.git
.gitignore

# Python
__pycache__
*.pyc
*.pyo
.pytest_cache
.coverage
htmlcov/
.tox
.env
venv/
*.egg-info

# IDE
.vscode/
.idea/
*.swp

# Docker
Dockerfile
docker-compose*.yml

# Docs
*.md
docs/

# Tests
tests/
test_*.py
```

---

## ✅ Checklist Mañana Completado

- [ ] Remote Backend configurado
- [ ] tfvars por ambiente creados
- [ ] Kustomize con overlays dev/prod
- [ ] PodDisruptionBudget agregado
- [ ] .dockerignore creado
- [ ] `kubectl apply -k k8s/overlays/dev` exitoso

---

# 🌙 TARDE/NOCHE: Fases 4-5 (CI/CD + DevSecOps)

> **Tiempo**: ~3-4 horas

---

## ⚠️ ARQUITECTURA ESPECIAL: Cross-Account Setup

Tu configuración actual:

```
┌─────────────────────────────────────────────────────────────────┐
│                    TU ARQUITECTURA                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CUENTA PERSONAL (macapixes1@hotmail.com)                      │
│  ├── App Registration / OIDC (Global Admin ✅)                 │
│  ├── ACR (votingappdevacr)                                     │
│  └── tfstate Storage Account                                    │
│                                                                 │
│  CUENTA TRABAJO (estebanmatapi@exsis.com.co)                   │
│  └── AKS (votingapp-dev-aks)                                   │
│                                                                 │
│  GITHUB ACTIONS                                                 │
│  ├── Login a cuenta PERSONAL (OIDC) → Push imagen a ACR       │
│  └── Login a cuenta TRABAJO (kubeconfig) → Deploy a AKS       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## FASE 4: CI/CD CON GITHUB ACTIONS (2-2.5h)

### 🎓 Conceptos Clave

**OIDC (OpenID Connect)** = GitHub prueba su identidad a Azure sin passwords.

```
GitHub Actions                    Azure AD (Personal)
     │                               │
     │──"Soy el repo X, branch Y"───▶│
     │                               │
     │◀────Token temporal (15min)────│
     │                               │
     │────Usa token para ACR────────▶│ ACR (push imagen)
```

### Paso 4.1: Configurar OIDC en Cuenta Personal

**IMPORTANTE**: Asegúrate de estar logueado en la cuenta personal:

```powershell
# Verificar cuenta actual
az account show --query user.name -o tsv
# Debe mostrar: macapixes1@hotmail.com

# Si no, cambiar:
az logout
az login --use-device-code
# Usar: macapixes1@hotmail.com
```

Ahora configura OIDC:

```powershell
# Variables - AJUSTA TU USUARIO DE GITHUB
$GITHUB_ORG = "TU_USUARIO_GITHUB"  # ej: "danielmatapi" 
$GITHUB_REPO = "azure-voting-app-redis"
$SUBSCRIPTION_ID = az account show --query id -o tsv
$RG_NAME = "votingapp-dev-rg"
$APP_NAME = "github-actions-votingapp"

# Mostrar valores para verificar
Write-Host "Subscription: $SUBSCRIPTION_ID"
Write-Host "Working on: $RG_NAME"

# Crear App Registration
az ad app create --display-name $APP_NAME
$APP_ID = az ad app list --display-name $APP_NAME --query "[0].appId" -o tsv
$OBJECT_ID = az ad app list --display-name $APP_NAME --query "[0].id" -o tsv

Write-Host "App ID: $APP_ID"

# Crear Service Principal
az ad sp create --id $APP_ID

# Asignar rol Contributor al Resource Group
az role assignment create `
    --assignee $APP_ID `
    --role "Contributor" `
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG_NAME"

# Asignar rol AcrPush al ACR
$ACR_ID = az acr show --name votingappdevacr --resource-group $RG_NAME --query id -o tsv
az role assignment create `
    --assignee $APP_ID `
    --role "AcrPush" `
    --scope $ACR_ID

# Federated Credential (OIDC)
$SUBJECT = "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/master"

az ad app federated-credential create --id $OBJECT_ID --parameters "{
    `"name`": `"github-master`",
    `"issuer`": `"https://token.actions.githubusercontent.com`",
    `"subject`": `"$SUBJECT`",
    `"audiences`": [`"api://AzureADTokenExchange`"]
}"

# GUARDAR ESTOS VALORES
Write-Host ""
Write-Host "============================================"
Write-Host "GITHUB SECRETS - CUENTA PERSONAL (ACR):"
Write-Host "============================================"
Write-Host "AZURE_CLIENT_ID: $APP_ID"
Write-Host "AZURE_TENANT_ID: $(az account show --query tenantId -o tsv)"
Write-Host "AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
Write-Host "============================================"
```

### Paso 4.2: Obtener Kubeconfig de Cuenta Trabajo

Ahora necesitas el kubeconfig del AKS que está en tu cuenta de trabajo:

```powershell
# Cambiar a cuenta de trabajo
az logout
az login --use-device-code
# Usar: estebanmatapi@exsis.com.co

# Obtener kubeconfig y guardarlo como base64
az aks get-credentials `
    --resource-group votingapp-dev-rg `
    --name votingapp-dev-aks `
    --file ./kubeconfig-temp `
    --overwrite-existing

# Convertir a base64 para GitHub Secret
$KUBECONFIG_B64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes("./kubeconfig-temp"))

Write-Host ""
Write-Host "============================================"
Write-Host "GITHUB SECRET - CUENTA TRABAJO (AKS):"
Write-Host "============================================"
Write-Host "KUBE_CONFIG: (copia todo el texto base64 siguiente)"
Write-Host $KUBECONFIG_B64
Write-Host "============================================"

# Limpiar archivo temporal
Remove-Item ./kubeconfig-temp -Force
```

### Paso 4.3: Configurar GitHub Secrets

Ve a GitHub → Settings → Secrets → Actions y agrega:

| Nombre | Valor | Cuenta |
|--------|-------|--------|
| `AZURE_CLIENT_ID` | App ID del paso 4.1 | Personal |
| `AZURE_TENANT_ID` | Tenant ID del paso 4.1 | Personal |
| `AZURE_SUBSCRIPTION_ID` | Subscription ID del paso 4.1 | Personal |
| `KUBE_CONFIG` | El base64 del paso 4.2 | Trabajo |

### Paso 4.4: Crear Workflow CI/CD (Cross-Account)

Crea `.github/workflows/ci-cd.yaml`:

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [main]
    paths: ['azure-vote/**', 'k8s/**', '.github/workflows/**']
  pull_request:
    branches: [main]
  workflow_dispatch:

env:
  # ACR está en cuenta PERSONAL
  ACR_NAME: votingappdevacr
  ACR_LOGIN_SERVER: votingappdevacr.azurecr.io
  IMAGE_NAME: azure-vote-front

permissions:
  id-token: write
  contents: read

jobs:
  # ============================================
  # JOB 1: BUILD - Usa cuenta PERSONAL (ACR)
  # ============================================
  build:
    name: Build & Scan
    runs-on: ubuntu-latest
    outputs:
      image-tag: ${{ steps.meta.outputs.tag }}
    
    steps:
      - uses: actions/checkout@v4

      - name: Set image tag
        id: meta
        run: |
          SHORT_SHA=$(echo ${{ github.sha }} | cut -c1-7)
          echo "tag=${{ env.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:${SHORT_SHA}" >> $GITHUB_OUTPUT

      - uses: docker/setup-buildx-action@v3

      # Login a cuenta PERSONAL con OIDC
      - name: Azure Login (Personal - ACR)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Login to ACR
        run: az acr login --name ${{ env.ACR_NAME }}

      - name: Build Docker image
        uses: docker/build-push-action@v5
        with:
          context: ./azure-vote
          push: false
          load: true
          tags: ${{ steps.meta.outputs.tag }}

      - name: Trivy vulnerability scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ steps.meta.outputs.tag }}
          format: 'table'
          exit-code: '1'
          ignore-unfixed: true
          severity: 'CRITICAL,HIGH'

      - name: Push to ACR
        if: success()
        run: docker push ${{ steps.meta.outputs.tag }}

  # ============================================
  # JOB 2: DEPLOY - Usa cuenta TRABAJO (AKS)
  # ============================================
  deploy:
    name: Deploy to AKS
    needs: build
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/master' && github.event_name == 'push'
    
    steps:
      - uses: actions/checkout@v4

      # Configurar kubectl con kubeconfig de cuenta TRABAJO
      - name: Setup Kubeconfig (Work Account - AKS)
        run: |
          mkdir -p $HOME/.kube
          echo "${{ secrets.KUBE_CONFIG }}" | base64 -d > $HOME/.kube/config
          chmod 600 $HOME/.kube/config

      - name: Verify AKS connection
        run: kubectl get nodes

      - name: Deploy with Kustomize
        run: |
          cd k8s/overlays/dev
          
          # Actualizar imagen en kustomization
          kustomize edit set image ${{ env.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}=${{ needs.build.outputs.image-tag }}
          
          # Aplicar manifests
          kubectl apply -k .

      - name: Verify deployment
        run: |
          kubectl rollout status deployment/frontend -n voting-app --timeout=120s
          echo "✅ Deployment successful!"

      - name: Get application URL
        run: |
          echo "Waiting for LoadBalancer IP..."
          for i in {1..30}; do
            IP=$(kubectl get svc frontend -n voting-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
            if [ -n "$IP" ]; then
              echo "🌐 Application URL: http://$IP"
              exit 0
            fi
            sleep 10
          done
          echo "⚠️ LoadBalancer IP not ready yet"
```

### Paso 4.5: Push y Verificar

```powershell
git add .
git commit -m "feat: Add CI/CD with OIDC (ACR) and kubeconfig (AKS)"
git push origin master

# Ve a GitHub → Actions para ver el pipeline
```

---

## FASE 5: DEVSECOPS (1-1.5h)

### Paso 5.1: Dependabot

Crea `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: "pip"
    directory: "/azure-vote/azure-vote"
    schedule:
      interval: "weekly"
    labels: ["dependencies", "python"]

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    labels: ["dependencies", "actions"]

  - package-ecosystem: "docker"
    directory: "/azure-vote"
    schedule:
      interval: "weekly"
    labels: ["dependencies", "docker"]
```

### Paso 5.2: CodeQL

Crea `.github/workflows/codeql.yaml`:

```yaml
name: CodeQL

on:
  push:
    branches: [master]
    paths: ['**.py']
  schedule:
    - cron: '0 6 * * 1'

jobs:
  analyze:
    runs-on: ubuntu-latest
    permissions:
      security-events: write
    steps:
      - uses: actions/checkout@v4
      - uses: github/codeql-action/init@v3
        with:
          languages: python
      - uses: github/codeql-action/autobuild@v3
      - uses: github/codeql-action/analyze@v3
```

### Paso 5.3: Network Policies

Crea `k8s/base/network-policies.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: redis-allow-frontend-only
  namespace: voting-app
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

Agrega a `k8s/base/kustomization.yaml`:

```yaml
resources:
  - namespace.yaml
  - configmap.yaml
  - redis-deployment.yaml
  - frontend-deployment.yaml
  - frontend-service.yaml
  - hpa.yaml
  - pdb.yaml
  - network-policies.yaml  # Agregar
```

### Paso 5.4: Commit Final del Día

```powershell
git add .
git commit -m "feat(security): Add DevSecOps - Dependabot, CodeQL, NetworkPolicies"
git push origin master
```

---

## ✅ Checklist Fases 4-5 Completado

- [ ] OIDC configurado en cuenta PERSONAL (macapixes1@hotmail.com)
- [ ] Kubeconfig obtenido de cuenta TRABAJO (estebanmatapi@exsis.com.co)
- [ ] GitHub Secrets agregados (4 secrets)
- [ ] Workflow CI/CD funcionando
- [ ] Trivy scan pasando
- [ ] Dependabot configurado
- [ ] CodeQL configurado
- [ ] Network Policies aplicadas

---

## 🎤 Para la Entrevista: Cross-Account Setup

> "En mi proyecto de práctica tuve una situación real de enterprise: no tenía permisos de Entra ID en mi cuenta de trabajo para configurar OIDC. La solución fue usar una arquitectura cross-account: configuré OIDC en una cuenta trial donde soy Global Admin para el ACR y build, y uso kubeconfig como secret para deploy al AKS de la cuenta de trabajo. Esto refleja escenarios reales donde diferentes equipos controlan diferentes recursos."

---

## 💡 Al Terminar Sábado

**Desde cuenta de trabajo:**
```powershell
az login --use-device-code  # estebanmatapi@exsis.com.co
cd terraform
terraform destroy -auto-approve
```

**Desde cuenta personal (opcional, conservar para mañana):**
```powershell
az login --use-device-code  # macapixes1@hotmail.com
# El OIDC y ACR se pueden reusar mañana
```

---

## 📋 Lo que Puedes Decir en la Entrevista

> "Para IaC uso Terraform con remote backend en Azure Storage para state compartido y locking. Manejo múltiples ambientes con tfvars separados. 
>
> En Kubernetes uso Kustomize para overlays - un base compartido y patches por ambiente. Todo deployment tiene PodDisruptionBudget para garantizar disponibilidad durante mantenimiento.
>
> Mi CI/CD usa GitHub Actions con OIDC para autenticación Zero Trust contra Azure - sin secrets guardados. El pipeline hace scan de vulnerabilidades con Trivy antes de push. Para seguridad en el cluster, implemento NetworkPolicies que restringen comunicación entre pods."
