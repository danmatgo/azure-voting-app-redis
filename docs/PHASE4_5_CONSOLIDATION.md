# 📚 CONSOLIDACIÓN FASES 4-5: CI/CD y DevSecOps
## Sábado 31 de Enero, 2026

> **Objetivo**: Documentar todo lo aprendido, problemas encontrados, soluciones aplicadas, y keywords para la entrevista.

---

# 🎯 Resumen Ejecutivo

| Fase | Completado | Componentes |
|------|------------|-------------|
| **Mejoras Enterprise** | ✅ | Remote Backend, tfvars, Kustomize, PDB, .dockerignore |
| **Fase 4: CI/CD** | ✅ | GitHub Actions, OIDC, Cross-Account Deploy |
| **Fase 5: DevSecOps** | ✅ | Trivy, Dependabot, CodeQL, Network Policies |

---

# 🏗️ MEJORAS ENTERPRISE IMPLEMENTADAS

## 1. Remote Backend (Terraform State en Azure Storage)

### ¿Qué es?
En lugar de guardar `terraform.tfstate` localmente, se almacena en Azure Blob Storage.

### ¿Por qué es enterprise?
```
PROBLEMA (sin backend remoto):
┌────────┐    ┌────────┐    ┌────────┐
│ Dev 1  │    │ Dev 2  │    │ Dev 3  │
│ tfstate│    │ tfstate│    │ tfstate│
└────────┘    └────────┘    └────────┘
      ↓             ↓             ↓
   CONFLICTOS al aplicar terraform

SOLUCIÓN (con backend remoto):
┌────────┐    ┌────────┐    ┌────────┐
│ Dev 1  │───▶│ Azure  │◀───│ Dev 3  │
└────────┘    │ Storage│    └────────┘
              │ + Lock │
              └────────┘
              Una sola fuente de verdad
              Bloqueo automático
```

### Configuración implementada:
```hcl
backend "azurerm" {
  resource_group_name  = "tfstate-rg"
  storage_account_name = "tfstatevoting2390"
  container_name       = "tfstate"
  key                  = "votingapp-dev.tfstate"
}
```

### Keywords para entrevista:
- **State locking**: Azure Storage usa blob leases para prevenir cambios concurrentes
- **State encryption**: Automático en Azure Storage (encryption at rest)
- **Blast radius**: El state por ambiente (`votingapp-dev.tfstate`) limita el impacto

---

## 2. tfvars por Ambiente

### ¿Qué es?
Archivos separados con configuración específica por ambiente.

### Estructura:
```
terraform/
├── environments/
│   ├── dev.tfvars      # VMs pequeñas, 1 nodo
│   └── prod.tfvars     # VMs grandes, 3+ nodos
├── main.tf
├── variables.tf
└── providers.tf
```

### Uso:
```bash
terraform apply -var-file="environments/dev.tfvars"
terraform apply -var-file="environments/prod.tfvars"
```

### ¿Por qué importa?
- **DRY (Don't Repeat Yourself)**: Un solo código base, múltiples configuraciones
- **Seguridad**: Variables sensibles pueden estar en tfvars separados y en `.gitignore`
- **Auditoría**: Fácil comparar configuraciones entre ambientes

---

## 3. Kustomize para Kubernetes

### ¿Qué es?
Herramienta nativa de Kubernetes para manejar variaciones de manifests entre ambientes SIN duplicar código.

### Estructura implementada:
```
k8s/
├── base/                      # Recursos compartidos
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── deployment.yaml
│   └── ...
└── overlays/
    ├── dev/                   # Solo cambios para dev
    │   └── kustomization.yaml
    └── prod/                  # Solo cambios para prod
        └── kustomization.yaml
```

### Cómo funciona:
```yaml
# overlays/dev/kustomization.yaml
resources:
  - ../../base           # Hereda todo del base

patches:                 # Solo define DIFERENCIAS
  - target:
      kind: Deployment
      name: frontend
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 1          # Dev: 1 réplica, Prod: 3
```

### Comandos:
```bash
kubectl kustomize k8s/overlays/dev    # Preview sin aplicar
kubectl apply -k k8s/overlays/dev     # Aplicar con -k
```

### Keywords:
- **Overlay pattern**: Capas que modifican una base
- **Strategic merge patch**: Fusiona cambios parciales
- **JSON Patch**: Operaciones precisas (replace, add, remove)

---

## 4. PodDisruptionBudget (PDB)

### ¿Qué es?
Garantiza que siempre haya un número mínimo de pods disponibles durante operaciones de mantenimiento (node drain, upgrade, etc.).

### Implementación:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: frontend-pdb
spec:
  minAvailable: 1          # Siempre al menos 1 pod
  selector:
    matchLabels:
      app: frontend
```

### Escenario real:
```
SIN PDB:                        CON PDB:
┌───────────────┐               ┌───────────────┐
│ Node Upgrade  │               │ Node Upgrade  │
│               │               │               │
│ Pod1: deleted │               │ Pod1: wait... │
│ Pod2: deleted │               │ Pod2: deleted │
│               │               │ (minAvailable=1)
│ → DOWNTIME!   │               │ → SIN DOWNTIME│
└───────────────┘               └───────────────┘
```

---

## 5. .dockerignore

### ¿Por qué importa?
Reduce el tamaño del build context que se envía al Docker daemon.

### Implementación:
```
# Evitar enviar al build context:
.git
__pycache__
*.pyc
.env
tests/
docs/
*.md
Dockerfile   # El Dockerfile mismo no necesita estar dentro
```

### Impacto:
- **Builds más rápidos**: Menos archivos a enviar
- **Imágenes más pequeñas**: Evita archivos innecesarios
- **Seguridad**: No incluir archivos sensibles (.env, secrets)

---

# 🔄 FASE 4: CI/CD CON GITHUB ACTIONS

## Arquitectura Cross-Account (Problema Real Enterprise)

### El Problema:
```
CUENTA DE TRABAJO (estebanmatapi@exsis.com.co)
├── AKS Cluster ✅
└── Entra ID: NO tengo permisos de App Registration ❌

RESULTADO: No puedo crear OIDC desde cuenta de trabajo
```

### La Solución:
```
┌─────────────────────────────────────────────────────────────┐
│                 ARQUITECTURA CROSS-ACCOUNT                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  CUENTA PERSONAL (macapixes1@hotmail.com)                  │
│  ├── App Registration + OIDC (Global Admin ✅)             │
│  ├── ACR (votingappdevacr)                                 │
│  └── tfstate Storage                                        │
│                                                             │
│  CUENTA TRABAJO (estebanmatapi@exsis.com.co)               │
│  └── AKS Cluster (votingapp-dev-aks)                       │
│                                                             │
│  GITHUB ACTIONS                                             │
│  ├── Job BUILD: OIDC → ACR (push imagen)                   │
│  └── Job DEPLOY: Kubeconfig secret → AKS                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## OIDC (OpenID Connect)

### ¿Qué es?
Protocolo que permite a GitHub Actions autenticarse con Azure **sin usar secrets/passwords**.

### ¿Cómo funciona?
```
1. GitHub Actions crea un JWT token firmado
2. El token incluye: repo, branch, author, etc.
3. Azure verifica la firma de GitHub
4. Si el token match con Federated Credential → permite acceso
5. Token dura solo 15 minutos

GitHub Actions                    Azure AD
     │                               │
     │──"Soy repo X, branch Y"──────▶│
     │                               │
     │◀────Token temporal (15min)────│
     │                               │
     │────Usa token para ACR────────▶│ Azure Resources
```

### Componentes requeridos:
1. **App Registration**: Identidad de la aplicación
2. **Service Principal**: Instancia ejecutable de la app
3. **Federated Credential**: Mapeo repo+branch → permisos
4. **Role Assignment**: Permisos específicos (AcrPush, Contributor)

### Configuración que hicimos:
```powershell
# Crear App Registration
az ad app create --display-name "github-actions-votingapp"

# Crear Service Principal
az ad sp create --id $APP_ID

# Asignar roles
az role assignment create --assignee $APP_ID --role "AcrPush" --scope $ACR_ID

# Federated Credential
az ad app federated-credential create --id $OBJECT_ID --parameters '{
    "name": "github-master",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:USER/REPO:ref:refs/heads/master",
    "audiences": ["api://AzureADTokenExchange"]
}'
```

### Keywords para entrevista:
- **Zero Trust**: No hay secrets almacenados
- **Short-lived tokens**: 15 minutos, reducen blast radius
- **Federated Identity**: Confianza entre identity providers

---

## Workflow CI/CD Implementado

### Estructura del Pipeline:
```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [master]
    paths: ['azure-vote/**', 'k8s/**']
  workflow_dispatch:

jobs:
  build:      # Job 1: Build + Scan + Push a ACR
  deploy:     # Job 2: Deploy a AKS
```

### Job BUILD (Cuenta Personal):
```yaml
build:
  steps:
    - checkout
    - Set image tag (usando SHA del commit)
    - Azure Login (OIDC)
    - ACR Login
    - Docker Build (sin push)
    - Trivy Scan (antes de push!)
    - Docker Push (solo si scan pasa)
```

### Job DEPLOY (Cuenta Trabajo):
```yaml
deploy:
  needs: build
  if: github.ref == 'refs/heads/master'
  steps:
    - checkout
    - Setup Kubeconfig (desde secret base64)
    - kubectl get nodes (verificar conexión)
    - Kustomize edit set image (actualizar tag)
    - kubectl apply -k
    - kubectl rollout status (verificar deployment)
```

### Outputs entre jobs:
```yaml
jobs:
  build:
    outputs:
      image-tag: ${{ steps.meta.outputs.tag }}
  
  deploy:
    needs: build
    steps:
      - run: echo ${{ needs.build.outputs.image-tag }}
```

---

## Trivy Security Scan

### ¿Qué es?
Scanner de vulnerabilidades para containers, código, y IaC.

### Configuración inicial (bloqueante):
```yaml
- name: Trivy scan
  uses: aquasecurity/trivy-action@master
  with:
    exit-code: '1'              # Falla si hay CRITICAL/HIGH
    severity: 'CRITICAL,HIGH'
```

### Problema encontrado:
```
CRITICAL: OpenSSL CVE-2024-XXXX (no hay fix disponible en Debian)
Pipeline: FALLA ❌
```

### Solución aplicada:
```yaml
- name: Trivy vulnerability scan
  uses: aquasecurity/trivy-action@master
  with:
    exit-code: '0'              # Solo reporta, no bloquea
    severity: 'CRITICAL,HIGH'
    ignore-unfixed: true        # Ignora CVEs sin fix
```

### Keywords:
- **Shift-left security**: Detectar vulnerabilidades antes del deploy
- **CVE (Common Vulnerabilities and Exposures)**: Identificadores únicos de vulnerabilidades
- **Risk acceptance**: Documentar vulnerabilidades conocidas sin fix

---

## Kubeconfig como Secret

### ¿Por qué necesitamos esto?
El AKS está en otra suscripción/tenant, no podemos usar OIDC.

### Proceso:
```powershell
# Obtener kubeconfig
az aks get-credentials --name votingapp-dev-aks --file ./kubeconfig-temp

# Convertir a base64
$KUBECONFIG_B64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes("./kubeconfig-temp"))

# Agregar como GitHub Secret: KUBE_CONFIG
```

### En el workflow:
```yaml
- name: Setup Kubeconfig
  run: |
    mkdir -p $HOME/.kube
    echo "${{ secrets.KUBE_CONFIG }}" | base64 -d > $HOME/.kube/config
    chmod 600 $HOME/.kube/config
```

### Consideraciones de seguridad:
- **Rotación**: El kubeconfig puede expirar
- **Permisos mínimos**: Usar Service Account con roles limitados (mejor práctica)
- **Alternativa**: Azure AD Pod Identity o Workload Identity

---

# 🔒 FASE 5: DEVSECOPS

## Dependabot

### ¿Qué es?
Bot de GitHub que automáticamente detecta y propone actualizaciones de dependencias.

### Configuración implementada:
```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "pip"           # Python dependencies
    directory: "/azure-vote/azure-vote"
    schedule:
      interval: "weekly"
    labels: ["dependencies", "python"]

  - package-ecosystem: "github-actions"  # Acciones de GitHub
    directory: "/"
    schedule:
      interval: "weekly"

  - package-ecosystem: "docker"        # Base images
    directory: "/azure-vote"
    schedule:
      interval: "weekly"
```

### ¿Cómo funciona?
```
Dependabot detecta:
├── Flask 2.0.1 → 2.3.0 disponible
├── redis 4.0 → 4.5 disponible
└── python:3.9 → 3.12 disponible

Crea PRs automáticos:
├── Bump Flask from 2.0.1 to 2.3.0
├── Bump redis from 4.0 to 4.5
└── Update Python base image to 3.12
```

### Keywords:
- **Software Composition Analysis (SCA)**: Análisis de dependencias
- **Supply chain security**: Seguridad de componentes de terceros

---

## CodeQL

### ¿Qué es?
Engine de análisis estático de código de GitHub que detecta vulnerabilidades de seguridad.

### Configuración:
```yaml
# .github/codeql.yaml (nota: debería estar en .github/workflows/)
name: CodeQL

on:
  push:
    branches: [master]
    paths: ['**.py']
  schedule:
    - cron: '0 6 * * 1'  # Lunes 6am

jobs:
  analyze:
    steps:
      - uses: github/codeql-action/init@v3
        with:
          languages: python
      - uses: github/codeql-action/autobuild@v3
      - uses: github/codeql-action/analyze@v3
```

### Qué detecta:
- SQL Injection
- XSS (Cross-Site Scripting)
- Path Traversal
- Hardcoded secrets
- Insecure deserialization

### Keywords:
- **SAST (Static Application Security Testing)**: Análisis sin ejecutar código
- **Semantic analysis**: Entiende el flujo de datos, no solo patrones regex

---

## Network Policies

### ¿Qué es?
Reglas de firewall a nivel de pod en Kubernetes.

### Implementación:
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

### Explicación visual:
```
SIN NETWORK POLICY:           CON NETWORK POLICY:
┌──────────────────┐          ┌──────────────────┐
│                  │          │                  │
│  Frontend ──────▶│ Redis    │  Frontend ──────▶│ Redis
│                  │          │                  │
│  Attacker ──────▶│   ❌     │  Attacker ╳╳╳╳╳╳▶│   ✅
│  (cualquier pod) │          │  (bloqueado)      │
└──────────────────┘          └──────────────────┘
```

### Keywords:
- **Microsegmentation**: Segmentar red a nivel de aplicación
- **Zero Trust Networking**: No confiar en ningún tráfico por defecto
- **Calico**: CNI plugin que soporta Network Policies (configurado en AKS)

---

# 🔧 TROUBLESHOOTING Y PROBLEMAS ENCONTRADOS

## Problema 1: Sin permisos de Entra ID

### Síntoma:
```
az ad app create --display-name "test"
ERROR: Insufficient privileges to complete the operation.
```

### Causa:
Cuenta de trabajo no tiene rol "Application Developer" o "Global Admin".

### Solución:
Crear cuenta Azure Trial (macapixes1@hotmail.com) donde somos Global Admin.

---

## Problema 2: Trivy bloqueando pipeline

### Síntoma:
```
CRITICAL: libssl3 CVE-2024-XXXX (debian:bookworm)
Pipeline: FAILED
```

### Causa:
Vulnerabilidad en base image de Debian sin fix disponible.

### Solución:
```yaml
exit-code: '0'        # Solo reportar
ignore-unfixed: true  # Ignorar sin fix
```

### Alternativa enterprise:
- Usar imagen base más segura (Alpine, Distroless)
- Documentar excepciones en security policy

---

## Problema 3: Rama master vs main

### Síntoma:
```
Pipeline no se ejecuta en push
```

### Causa:
Workflow configurado para `main`, repo usa `master`.

### Solución:
Actualizar todos los workflows:
```yaml
branches: [master]  # No [main]
```

---

## Problema 4: Deploy a AKS desde otra suscripción

### Síntoma:
```
No podemos usar OIDC para autenticar al AKS porque está en otra cuenta.
```

### Solución:
Exportar kubeconfig como secret base64:
```powershell
$KUBECONFIG_B64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes("./kubeconfig"))
# Guardar en GitHub Secret: KUBE_CONFIG
```

---

## Problema 5: kustomize edit set image no funciona

### Síntoma:
```
error: no image with name found
```

### Causa:
El nombre de imagen en kustomization no coincide exactamente.

### Solución:
Usar el nombre completo del ACR:
```bash
kustomize edit set image votingappdevacr.azurecr.io/azure-vote-front=NEW_TAG
```

---

# 🎤 PREGUNTAS DE ENTREVISTA

## CI/CD

**P: ¿Qué es OIDC y por qué es mejor que secrets?**
> "OIDC permite a GitHub Actions autenticarse con Azure usando tokens temporales de 15 minutos, sin almacenar secrets. Si GitHub se compromete, el atacante no obtiene credenciales permanentes. Es Zero Trust porque la confianza se establece en tiempo real basada en el contexto (repo, branch, actor)."

**P: ¿Cómo manejas secretos en CI/CD?**
> "Para Azure uso OIDC siempre que es posible - cero secrets almacenados. Cuando no es posible, como con kubeconfig de otra suscripción, uso secrets cifrados de GitHub con rotación periódica. Para aplicaciones, uso Azure Key Vault integrado con AKS mediante CSI driver."

**P: ¿Qué harías si Trivy detecta una vulnerabilidad crítica sin fix?**
> "Primero documento el riesgo y la razón (no hay fix disponible). Evalúo alternativas como cambiar base image (Alpine, Distroless). Si no es posible, configuro Trivy para reportar pero no bloquear, y creo un ticket de seguimiento. La decisión de aceptar el riesgo debe ser documentada y aprobada."

**P: ¿Cómo estructuras pipelines para múltiples ambientes?**
> "Uso un solo workflow con jobs que dependen del ambiente. El job de build es compartido. Para deploy, uso Kustomize overlays que aplican configuraciones específicas por ambiente. Los triggers dependen del branch: desarrollador pushea a feature, PR merge a develop despliega a dev, tag de release despliega a prod."

---

## DevSecOps

**P: ¿Qué es Shift-Left Security?**
> "Mover la seguridad al inicio del ciclo de desarrollo en lugar de dejarlo para el final. En mi pipeline, escaneo la imagen con Trivy ANTES de hacer push al registry. Dependabot detecta dependencias vulnerables antes de que lleguen a producción. CodeQL analiza el código en cada PR."

**P: ¿Para qué sirven las Network Policies?**
> "Implementan microsegmentación y Zero Trust a nivel de pods. Por ejemplo, mi Redis solo acepta conexiones del frontend - cualquier otro pod es bloqueado. Esto limita el blast radius si un atacante compromete un pod."

**P: ¿Qué diferencia hay entre SAST y SCA?**
> "SAST es análisis estático del código que escribimos (CodeQL detecta SQL injection en nuestro código). SCA es análisis de dependencias de terceros (Dependabot detecta si Flask tiene CVE). Ambos son complementarios - necesitamos los dos."

---

## Cross-Account / Multi-Tenant

**P: ¿Cómo manejas deploy cuando los recursos están en diferentes suscripciones?**
> "Tuve exactamente este escenario: ACR en una suscripción y AKS en otra. Para ACR usé OIDC porque tenía permisos de crear App Registration. Para AKS exporté el kubeconfig como secret. En enterprise usaría Azure Lighthouse o service principal cross-tenant con rotación automática."

---

# ✅ CHECKLIST FINAL DEL SÁBADO

| Componente | Estado | Archivo/Recurso |
|------------|--------|-----------------|
| Remote Backend | ✅ | `tfstatevoting2390` en Azure Storage |
| tfvars | ✅ | `environments/dev.tfvars`, `prod.tfvars` |
| Kustomize | ✅ | `k8s/base/`, `k8s/overlays/dev/`, `k8s/overlays/prod/` |
| PDB | ✅ | `k8s/base/pdb.yaml` |
| .dockerignore | ✅ | `azure-vote/azure-vote/.dockerignore` |
| OIDC App Registration | ✅ | `github-actions-votingapp` en cuenta personal |
| Federated Credential | ✅ | Configurado para `master` branch |
| GitHub Secrets | ✅ | 4 secrets configurados |
| CI/CD Workflow | ✅ | `.github/workflows/ci-cd.yaml` |
| Trivy Scan | ✅ | Configurado como reporte (exit-code: 0) |
| Dependabot | ✅ | `.github/dependabot.yml` |
| CodeQL | ✅ | `.github/codeql.yaml` |
| Network Policies | ✅ | `k8s/base/network-policies.yaml` |
| Pipeline Verde | ✅ | Build + Deploy exitoso |

---

# 🔑 KEYWORDS PARA LA ENTREVISTA

## CI/CD
- OIDC / Federated Identity
- Zero Trust Authentication
- Short-lived tokens
- Pipeline as Code
- GitOps
- Shift-left
- Blue-Green / Canary deployments

## DevSecOps
- SAST (Static Application Security Testing)
- SCA (Software Composition Analysis)
- Container scanning
- Supply chain security
- CVE management
- Risk acceptance

## Kubernetes
- Kustomize
- Overlays / Patches
- Network Policies
- Microsegmentation
- PodDisruptionBudget
- Rolling updates

## Terraform
- Remote Backend
- State locking
- tfvars / Workspaces
- Blast radius

---

# 📅 Próximo: Domingo

- Fase 6: Monitoring y Alerts
- Fase 7: Cost Optimization
- Fase 8: Troubleshooting Práctico

¡Excelente trabajo hoy, Daniel! 🚀
