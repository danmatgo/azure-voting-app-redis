# 🚀 Guía Práctica Avanzada (Bonus)
## Fase 9: GitOps, Helm & Secrets Management

> **Tiempo estimado**: ~4-5 horas
> **Objetivo**: Elevar el nivel del proyecto a estándares enterprise puros usando Helm para empaquetado, ArgoCD para GitOps (Pull-based) y Azure Key Vault con External Secrets.
> **Por qué importa**: Pasar de scripts/Kustomize push-based a GitOps pull-based es la diferencia clave entre un perfil Junior/Mid y un perfil Senior/Cloud Native.

---

# 📋 Agenda del Día

| Tiempo | Fase | Tema |
|--------|------|------|
| 30min | Prep | Recrear infraestructura base |
| 1.5h | 9.1 | Helm: Convirtiendo Kustomize en un Helm Chart |
| 1.5h | 9.2 | ArgoCD: Implementando GitOps (Pull-based deploy) |
| 1.0h | 9.3 | External Secrets (Azure Key Vault) |

---

# 🔄 PREPARACIÓN: Recrear Infraestructura (30 min)

Como vimos en la guía anterior, lo ideal es pausar/resumir, pero si destruiste todo, toca recrear.

```powershell
cd "c:\Users\Daniel Matapi\cloud-practice\azure-voting-app-redis\terraform"

# Aplicar infraestructura
terraform apply -var-file="environments/dev.tfvars" -auto-approve

# Configurar kubectl
az aks get-credentials --resource-group votingapp-dev-rg --name votingapp-dev-aks --overwrite-existing

# IMPORTANTE: NO despliegues la app con Kustomize esta vez.
# Vamos a desplegarla usando Helm y ArgoCD.
```

---

# FASE 9.1: HELM (EMPAQUETADO ENTERPRISE) (1.5h)

## 🎓 ¿Por qué Helm en lugar de Kustomize?

Kustomize es genial para "parchear" YAMLs (overlays), pero Helm es el "apt/yum/npm" de Kubernetes. Permite:
1. Usar variables (templating) reales en los YAMLs.
2. Agrupar múltiples recursos en una sola "Release" versionada.
3. Hacer rollbacks fácilmente (`helm rollback`).
4. Compartir aplicaciones complejas fácilmente.

## Paso 1: Instalar Helm en tu máquina

Si no lo tienes en Windows (usando winget o choco):
```powershell
winget install Helm.Helm
# Reinicia tu terminal si es necesario
helm version
```

## Paso 2: Crear la estructura del Chart

Abre tu proyecto en la terminal:
```powershell
cd "c:\Users\Daniel Matapi\cloud-practice\azure-voting-app-redis"

# Crear el scaffolding de Helm
helm create voting-app-chart

# Helm creará una carpeta 'voting-app-chart' con templates por defecto.
# Borraremos los templates por defecto para poner los nuestros:
Remove-Item -Recurse -Force voting-app-chart\templates\*
```

## Paso 3: Migrar YAMLs a Templates de Helm

Copia tus archivos base de Kubernetes (Deployment, Service) de `k8s/base/` a `voting-app-chart/templates/`.

Vamos a parametrizar el deployment del frontend. Edita `voting-app-chart/templates/frontend-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "{{ .Release.Name }}-frontend"
  labels:
    app: "{{ .Release.Name }}-frontend"
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: "{{ .Release.Name }}-frontend"
  template:
    metadata:
      labels:
        app: "{{ .Release.Name }}-frontend"
    spec:
      containers:
      - name: frontend
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        ports:
        - containerPort: 80
        env:
        - name: REDIS
          value: "{{ .Values.redis.host }}"
```

## Paso 4: Definir `values.yaml`

Edita `voting-app-chart/values.yaml` (borra su contenido e inserta esto):

```yaml
replicaCount: 1

image:
  repository: votingappdevacr.azurecr.io/azure-vote-front
  tag: latest # Usa el tag específico en prod

redis:
  host: "voting-app-redis"
```

## Paso 5: Instalar y Verificar el Chart localmente (Testing manual)

```powershell
# Validar sintaxis
helm lint ./voting-app-chart

# Ver qué YAMLs generaría (dry-run)
helm install my-vote-app ./voting-app-chart --dry-run --debug

# Instalarlo de verdad en el cluster
helm install my-vote-app ./voting-app-chart -n voting-app --create-namespace

# Verificar la release
helm list -n voting-app
kubectl get pods -n voting-app
```

**¡Felicidades!** Has empaquetado tu aplicación en Helm. Elimínala para el siguiente paso, porque ArgoCD se encargará de esto.
```powershell
helm uninstall my-vote-app -n voting-app
```

---

# FASE 9.2: ARGOCD (GITOPS PULL-BASED) (1.5h)

## 🎓 ¿Qué es ArgoCD y GitOps?

Hasta ahora usamos **Push-based CI/CD**: GitHub Actions ejecuta un script (kubectl apply) que *empuja* los cambios al cluster.
Pero para seguridad enterprise, el cluster no debe recibir peticiones de internet.

**Pull-based (GitOps con ArgoCD)**:
1. Instalas ArgoCD **dentro** de AKS.
2. ArgoCD monitorea tu repositorio GitHub.
3. Cuando haces un commit en git, ArgoCD detecta el cambio y él mismo *hala* (pull) el código y se auto-aplica.
El clúster solo hace conexiones salientes hacia GitHub. Más seguro y reconcilia "drifts" (cambios manuales).

## Paso 1: Instalar ArgoCD en AKS

```powershell
# Crear namespace
kubectl create namespace argocd

# Instalar ArgoCD oficial
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Esperar a que los pods estén listos
kubectl get pods -n argocd -w
```

## Paso 2: Acceder a ArgoCD UI

```powershell
# Obtener la contraseña inicial (por defecto es el nombre del pod server)
$ARGOCD_SERVER_POD = kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2
$ARGOCD_PASSWORD = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | [System.Convert]::FromBase64String($pwd) | [System.Text.Encoding]::UTF8.GetString($pwd)
# Hay una forma más fácil usando el CLI, pero podemos usar Port-Forward para ver la UI:

kubectl port-forward svc/argocd-server -n argocd 8080:443
# Abre tu navegador en https://localhost:8080
# Admin: admin
# Password: (ejecuta el comando para obtener el initial secret, o búscalo en el portal)

# Forma rápida de sacar el password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
# (Decodifica ese base64 en https://www.base64decode.org/)
```

## Paso 3: Crear la ArgoCD Application

Podemos hacer esto desde la UI o por YAML. Hagámoslo como verdaderos ingenieros, por YAML (`argocd-app.yaml`):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: voting-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/TU_USUARIO/azure-voting-app-redis.git' # ¡CAMBIA ESTO!
    targetRevision: main
    path: voting-app-chart # La ruta de tu chart de Helm dentro del repo
    helm:
      valueFiles:
      - values.yaml
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: voting-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

Aplícalo:
```powershell
kubectl apply -f argocd-app.yaml
```

**¡Magia!** ArgoCD leerá tu repo de git, detectará que ahí hay un Chart de Helm, lo renderizará y lo aplicará en tu clúster. Si vas a la UI de ArgoCD verás un grafo hermoso de cómo se despliega tu app.

---

# FASE 9.3: EXTERNAL SECRETS CON KVB (1h) (Avanzado)

## 🎓 El Problema de los Secretos en Kubernetes
Los `Secrets` nativos de K8s solo están codificados en Base64, NO encriptados. Subirlos a Git es un riesgo enorme de seguridad.

**Solución**: External Secrets Operator. Mantienes el secreto real en Azure Key Vault, y ESO se encarga de sincronizarlo desde Azure directo a la memoria de K8s sin pasar por tu código ni por Git.

## Paso 1: Habilitar y crear Azure Key Vault

```powershell
$RG = "votingapp-dev-rg"

# Crear Key Vault
az keyvault create --name "votingapp-kv-dev" --resource-group $RG --location eastus

# Crear un secreto ahí dentro (ej. contraseña de Redis)
az keyvault secret set --vault-name "votingapp-kv-dev" --name "redis-password" --value "SuperSecret123!"
```

## Paso 2: Configurar Identidad de Pod (Workload Identity)
*(Nota: Esto requiere configurar Azure AD Workload Identity, que puede ser complejo. Si se complica, usa Service Principals temporalmente o sáltate esta fase hasta una entrevista específica de seguridad).*

```powershell
# Instalar External Secrets usando Helm
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace --set installCRDs=true
```

## Paso 3: Crear el ClusterSecretStore y el ExternalSecret

Un `ClusterSecretStore` le dice a K8s *CÓMO* autenticarse con Key Vault.
Un `ExternalSecret` le dice a K8s *QUÉ* secreto ir a buscar y cómo llamarlo en K8s.

Si logras implementar esto, puedes decir en entrevista:
*"Los secretos nunca tocaron el repositorio Git. Usé External Secrets Operator para sincronizarlos dinámicamente desde Azure Key Vault mediante Workload Identity."* (¡Nivel Senior garantizado!).

---

# 🏆 LECCIONES PARA ENTREVISTA (Qué decir)

**P: ¿Qué es GitOps y cómo lo implementas?**
> "GitOps es usar Git como la única fuente de la verdad para la infraestructura y las aplicaciones. Usando herramientas pull-based como ArgoCD, el clúster monitorea el repositorio de Git y concilia cualquier diferencia. Si alguien edita algo directamente con kubectl, ArgoCD lo 'cura' revirtiéndolo al estado definido en Git (self-healing)."

**P: Kustomize vs Helm, ¿cuál prefieres?**
> "Uso ambos, pero para distribuir aplicaciones prefiero Helm porque permite templating de verdad y agrupar recursos en 'Releases', además de facilitar rollbacks (helm rollback). Kustomize es excelente para pipelines de CI/CD más sencillos donde solo necesito aplicar parches a manifiestos existentes sin la complejidad de crear un chart desde cero."

**P: ¿Cómo manejas secretos en Kubernetes?**
> "Los secretos de K8s son base64, no están encriptados. El peor antipatrón es subirlos a Git. La mejor práctica que sigo es guardar los secretos en un Key Management Service centralizado como Azure Key Vault y usar External Secrets Operator en el clúster para que los sincronice en tiempo de ejecución."

---

## ✅ Checklist de Cierre

- [ ] ¿Conecto ArgoCD a mi repositorio en GitHub?
- [ ] ¿Entiendo la diferencia entre push y pull deployments?
- [ ] ¿Creé mi primer Helm Chart?
- [ ] ¿Entiendo el riesgo de los secretos en Base64?
- [ ] Has añadido +1 año de experiencia 'percibida' a tu perfil técnico.
