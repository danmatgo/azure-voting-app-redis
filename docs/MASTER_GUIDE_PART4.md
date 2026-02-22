# 🧠 GUÍA MAESTRA - PARTE 4
## Kustomize, CI/CD y DevSecOps

---

# 📁 KUSTOMIZE - MANEJANDO AMBIENTES

## El Problema

Tienes manifests de Kubernetes que funcionan en desarrollo. Pero producción necesita:
- Más réplicas (no 2, sino 5)
- Más recursos (más CPU/memoria)
- Diferentes configuraciones
- Diferentes imágenes

**Solución tradicional**: Copiar todos los archivos y modificarlos.

```
k8s-dev/
├── deployment.yaml    (100 líneas)
├── service.yaml
└── ...

k8s-prod/
├── deployment.yaml    (100 líneas, 5 diferencias)
├── service.yaml
└── ...

Problema: Cambias algo base → tienes que cambiar en AMBOS lugares
```

## La Solución: Kustomize

Kustomize permite definir una BASE y OVERLAYS que solo contienen las diferencias.

```
k8s/
├── base/                    # Lo compartido (90% del código)
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ...
│
└── overlays/
    ├── dev/                 # Solo diferencias para dev
    │   └── kustomization.yaml (10 líneas)
    │
    └── prod/                # Solo diferencias para prod
        └── kustomization.yaml (10 líneas)
```

## Cómo Funciona

### base/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: voting-app
resources:
  - namespace.yaml
  - configmap.yaml
  - deployment.yaml
  - service.yaml
  - hpa.yaml
  - pdb.yaml
  - network-policies.yaml
```

**¿Qué hace?**: Lista todos los recursos que componen esta aplicación.

`resources`: Archivos YAML a incluir.

### overlays/dev/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - target:
      kind: Deployment
      name: frontend
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 1
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/cpu
        value: 50m
```

**`resources: - ../../base`**: Incluir TODO de la carpeta base.

**`patches`**: Modificaciones a aplicar encima.

**Partes del patch**:
- `target`: ¿Qué recurso modificar? (Deployment llamado "frontend")
- `patch`: ¿Qué cambios hacer?
  - `op: replace`: Reemplazar un valor
  - `path`: Ubicación del valor (en formato JSON Pointer)
  - `value`: El nuevo valor

**¿Qué significa `/spec/replicas`?**

Es un JSON Pointer. Navega el YAML:
```yaml
spec:           # /spec
  replicas: 2   # /spec/replicas
```

**¿Y `/spec/template/spec/containers/0/resources/requests/cpu`?**

```yaml
spec:
  template:
    spec:
      containers:
        - name: frontend      # [0] = primer elemento
          resources:
            requests:
              cpu: 100m       # Este valor
```

## Usando Kustomize

```bash
# Ver qué generaría (sin aplicar)
kubectl kustomize k8s/overlays/dev

# Aplicar directamente
kubectl apply -k k8s/overlays/dev

# En un pipeline CI/CD
cd k8s/overlays/dev
kustomize edit set image VIEJA_IMAGEN=NUEVA_IMAGEN
kubectl apply -k .
```

**`kustomize edit set image`**: Cambia la imagen sin editar archivos manualmente.

---

# 🔄 CI/CD - AUTOMATIZACIÓN

## ¿Qué problema resuelve?

**Sin CI/CD**:
1. Developer hace commit
2. Developer se conecta al servidor
3. Developer ejecuta manualmente: build, test, deploy
4. Si hay error, volver a empezar
5. Tiempo: horas. Errores: frecuentes.

**Con CI/CD**:
1. Developer hace commit
2. Sistema automáticamente: build, test, scan, deploy
3. Developer recibe notificación del resultado
4. Tiempo: minutos. Errores: detectados temprano.

## Los conceptos

**CI (Continuous Integration)**:
- Cada commit se construye y se testea automáticamente
- Feedback rápido: "tu código rompió algo"
- Merge frecuente a la rama principal

**CD (Continuous Delivery/Deployment)**:
- Delivery: Artefacto listo para deploy con un click
- Deployment: Deploy automático a producción

## GitHub Actions

GitHub Actions ejecuta "workflows" cuando ocurren eventos.

### Anatomía de un Workflow

```yaml
name: CI/CD Pipeline
```
**`name`**: Nombre que aparece en la UI de GitHub.

```yaml
on:
  push:
    branches: [master]
    paths: ['azure-vote/**', 'k8s/**']
  pull_request:
    branches: [master]
  workflow_dispatch:
```

**`on`**: ¿Cuándo ejecutar este workflow?

- `push: branches: [master]`: Cuando hay push a master
- `paths`: SOLO si cambiaron archivos en estas carpetas
- `pull_request`: Cuando crean o actualizan un PR
- `workflow_dispatch`: Botón manual en GitHub

**¿Por qué `paths`?**: Si solo cambió el README, no tiene sentido hacer build y deploy.

```yaml
env:
  ACR_NAME: votingappdevacr
  ACR_LOGIN_SERVER: votingappdevacr.azurecr.io
  IMAGE_NAME: azure-vote-front
```

**`env`**: Variables de entorno disponibles en todo el workflow.

Definirlas aquí evita repetir valores en múltiples lugares.

```yaml
permissions:
  id-token: write
  contents: read
```

**`permissions`**: Qué permisos tiene el workflow.

- `id-token: write`: Necesario para OIDC con Azure (explicado abajo)
- `contents: read`: Puede leer el código del repo

```yaml
jobs:
  build:
    name: Build & Scan
    runs-on: ubuntu-latest
```

**`jobs`**: Las tareas a ejecutar. Cada job corre en una máquina separada.

**`runs-on`**: En qué sistema operativo correr. `ubuntu-latest` es el más común.

---

## OIDC - Autenticación sin secretos

### El problema con secretos tradicionales

```
Proceso tradicional:
1. Crear Service Principal en Azure
2. Copiar password
3. Guardar en GitHub Secrets
4. Workflow usa el password

Problemas:
├── Password almacenado en 2 lugares (Azure, GitHub)
├── Password puede expirar
├── Si GitHub se compromete → password expuesto
└── Hay que rotar manualmente
```

### La solución: OIDC (OpenID Connect)

```
Proceso OIDC:
1. Crear App Registration en Azure
2. Configurar "Federated Credential":
   "Confío en tokens de GitHub Actions para repo X, branch Y"
3. Workflow pide un token a GitHub
4. Workflow presenta token a Azure
5. Azure verifica el token y da acceso temporal (15 min)

Beneficios:
├── NO hay password almacenado en GitHub
├── Tokens duran 15 minutos (blast radius limitado)
├── Si GitHub se compromete → tokens expiran automáticamente
└── Zero secret management
```

### ¿Cómo funciona paso a paso?

```
┌─────────────────┐                     ┌─────────────────┐
│  GitHub Actions │                     │    Azure AD     │
│                 │                     │                 │
│  1. Necesito    │                     │                 │
│     acceso a    │                     │                 │
│     Azure       │                     │                 │
│        │        │                     │                 │
│        ▼        │                     │                 │
│  2. Pido token  │                     │                 │
│     a GitHub    │──────────────────▶ │                 │
│     OIDC        │    3. GitHub       │                 │
│                 │       genera JWT   │                 │
│                 │                     │                 │
│  4. Presento    │                     │                 │
│     token a     │──────────────────▶ │  5. Azure       │
│     Azure       │                     │     verifica:   │
│                 │                     │     - Firma     │
│                 │                     │     - Repo      │
│                 │                     │     - Branch    │
│                 │◀──────────────────│                 │
│  6. Recibo      │    5. OK, aquí    │                 │
│     token       │       tienes      │                 │
│     Azure       │       token       │                 │
│     temporal    │                     │                 │
└─────────────────┘                     └─────────────────┘
```

### Configuración en el workflow

```yaml
- name: Azure Login (OIDC)
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

**¿Qué son estos IDs?**

- `client-id`: Identificador de la App Registration (pública, no secreta)
- `tenant-id`: Identificador del directorio de Azure AD (pública)
- `subscription-id`: La suscripción de Azure a usar (pública)

**NINGUNO es secreto.** Solo identifican qué cuenta usar. La autenticación real es por OIDC.

---

## El Job de Build

```yaml
steps:
  - uses: actions/checkout@v4
```
**¿Qué hace?**: Descarga el código del repo a la máquina del runner.

Sin esto, el runner está vacío.

```yaml
  - name: Set image tag
    id: meta
    run: |
      SHORT_SHA=$(echo ${{ github.sha }} | cut -c1-7)
      echo "tag=${{ env.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:${SHORT_SHA}" >> $GITHUB_OUTPUT
```

**¿Qué hace?**: Crea un tag único para la imagen.

**`${{ github.sha }}`**: El hash del commit (ej: `abc123def456...`)

**`cut -c1-7`**: Tomar los primeros 7 caracteres → `abc123d`

**Resultado**: `votingappdevacr.azurecr.io/azure-vote-front:abc123d`

**¿Por qué SHA y no `latest`?**

- `latest` → ¿Qué versión es? No sabes sin investigar.
- `abc123d` → Exactamente sabes qué commit es.

Si hay un bug en producción, puedes ver qué commit se deployó y qué cambió.

```yaml
  - uses: docker/setup-buildx-action@v3
```
**¿Qué hace?**: Instala BuildX, una versión avanzada de `docker build`.

Beneficios: Multi-platform builds, mejor caching.

```yaml
  - name: Build Docker image
    uses: docker/build-push-action@v5
    with:
      context: ./azure-vote
      push: false
      load: true
      tags: ${{ steps.meta.outputs.tag }}
```

**`context`**: Carpeta desde donde se hace el build (donde está el Dockerfile).

**`push: false`**: NO enviar al registry todavía.

**`load: true`**: Cargar la imagen localmente (para escanearla).

**¿Por qué no pushear inmediatamente?**

```
Build → Push → Scan encuentra vulnerabilidad → Ya está en el registry 😱

vs

Build → Scan → (si OK) → Push ✅
```

Escanear ANTES de pushear es más seguro.

---

## El Job de Deploy

```yaml
deploy:
  name: Deploy to AKS
  needs: build
  runs-on: ubuntu-latest
  if: github.ref == 'refs/heads/master' && github.event_name == 'push'
```

**`needs: build`**: Esperar a que el job `build` termine exitosamente.

**`if`**: SOLO ejecutar si:
- Es la rama master
- Es un push (no un PR)

En PRs solo queremos build+test, no deploy.

```yaml
  - name: Setup Kubeconfig
    run: |
      mkdir -p $HOME/.kube
      echo "${{ secrets.KUBE_CONFIG }}" | base64 -d > $HOME/.kube/config
      chmod 600 $HOME/.kube/config
```

**¿Qué es kubeconfig?**

El archivo que dice cómo conectarse a Kubernetes:
- URL del cluster
- Certificados de autenticación
- Contextos (si manejas múltiples clusters)

**¿Por qué base64?**

GitHub Secrets no maneja bien archivos con caracteres especiales. Se codifica en base64 para almacenarlo como texto plano.

**`chmod 600`**: Solo el dueño puede leer/escribir. Kubernetes requiere esto por seguridad.

```yaml
  - name: Deploy with Kustomize
    run: |
      cd k8s/overlays/dev
      kustomize edit set image ${{ env.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}=${{ needs.build.outputs.image-tag }}
      kubectl apply -k .
```

**`needs.build.outputs.image-tag`**: Obtener el tag que generó el job de build.

**Flujo**:
1. Ir a la carpeta del overlay de dev
2. Actualizar la imagen al nuevo tag
3. Aplicar todos los manifests

```yaml
  - name: Verify deployment
    run: |
      kubectl rollout status deployment/frontend -n voting-app --timeout=120s
```

**¿Qué hace `rollout status`?**

Espera a que el Deployment termine de actualizar:
- Nuevos pods creados
- Viejos pods eliminados
- Todos los pods healthy

Si en 120 segundos no termina → falla el pipeline.

---

# 🔒 DEVSECOPS - SEGURIDAD INTEGRADA

## La filosofía: Shift-Left

```
ANTES (seguridad al final):
Código → Build → Test → Deploy → Producción → SCAN → ¡Problemas!
                                                      ↓
                                              Rollback, pánico

AHORA (shift-left):
       SCAN    SCAN    SCAN    SCAN
         ↓       ↓       ↓       ↓
Código → Build → Test → Stage → Producción
         ↑
    Detectar temprano = Arreglar barato
```

**¿Por qué se llama "shift-left"?**

En un diagrama de tiempo, la seguridad se "mueve a la izquierda" (más temprano en el proceso).

---

## Trivy - Escaneo de Contenedores

### ¿Qué es?

Trivy escanea imágenes Docker buscando:
- **CVEs**: Vulnerabilidades conocidas en paquetes del SO
- **Vulnerabilidades en librerías**: Flask, Redis, etc.
- **Misconfigurations**: Dockerfile inseguros

### En el workflow

```yaml
- name: Trivy vulnerability scan
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ steps.meta.outputs.tag }}
    format: 'table'
    exit-code: '0'
    severity: 'CRITICAL,HIGH'
```

**`image-ref`**: Qué imagen escanear.

**`format: table`**: Resultado como tabla legible (hay opciones como JSON, SARIF).

**`exit-code: '0'`**: NO fallar el pipeline aunque encuentre vulnerabilidades.

**`severity: 'CRITICAL,HIGH'`**: Solo reportar vulnerabilidades críticas y altas.

### ¿Por qué exit-code 0?

A veces hay vulnerabilidades en el sistema operativo base (Debian, Alpine) que:
1. No tienen parche disponible
2. No son explotables en tu contexto

Bloquear el pipeline no soluciona el problema. Mejor:
1. Reportar la vulnerabilidad
2. Documentar la decisión de riesgo
3. Crear ticket para dar seguimiento

**En producción real**:
- `exit-code: 1` para fallar en CRITICAL
- Lista de CVEs ignorados con justificación
- Proceso de revisión cuando hay nuevas vulnerabilidades

---

## Dependabot - Actualizaciones automáticas

### ¿Qué es?

Un bot de GitHub que:
1. Revisa qué dependencias tienes
2. Ve si hay versiones nuevas
3. Crea PRs automáticamente con las actualizaciones

### Configuración

```yaml
# .github/dependabot.yml
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

  - package-ecosystem: "docker"
    directory: "/azure-vote"
    schedule:
      interval: "weekly"
```

**`package-ecosystem`**: Qué tipo de dependencias revisar.
- `pip`: requirements.txt de Python
- `github-actions`: Actions usados en workflows
- `docker`: Imágenes base en Dockerfile

**`directory`**: Dónde buscar el archivo de dependencias.

**`schedule: weekly`**: Revisar una vez por semana.

### ¿Cómo funciona?

```
Lunes temprano:
├── Dependabot: "Flask 2.3.3 tiene CVE, hay 2.3.4 disponible"
├── Crea PR: "Bump Flask from 2.3.3 to 2.3.4"
├── Pipeline corre tests automáticamente
└── Si tests pasan, puedes hacer merge

vs

Sin Dependabot:
├── Meses después te enteras del CVE
├── Para entonces usas 10 librerías desactualizadas
└── Actualizar todo junto es arriesgado
```

---

## CodeQL - Análisis estático

### ¿Qué es?

Un analyzer de código que busca patrones de vulnerabilidades SIN ejecutar el código.

### ¿Qué detecta?

- **SQL Injection**: Usuario puede inyectar SQL malicioso
- **XSS**: Usuario puede inyectar JavaScript
- **Command Injection**: Usuario puede ejecutar comandos del sistema
- **Path Traversal**: Usuario puede acceder a archivos del sistema
- **Hardcoded secrets**: Passwords en el código

### Configuración

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

**`paths: ['**.py']`**: Solo correr si cambian archivos Python.

**`schedule: cron`**: También correr cada Lunes a las 6am, para detectar nuevos patrones.

**`security-events: write`**: Permiso para crear Security Alerts en GitHub.

---

## Network Policies - Seguridad en Kubernetes

### El problema

Por defecto, cualquier Pod puede hablar con cualquier otro Pod.

```
SIN NETWORK POLICIES:
┌─────────────────────────────────────┐
│          KUBERNETES                 │
│                                     │
│  Frontend ────▶ Redis    ✅        │
│  Attacker ────▶ Redis    ✅ 😱     │
│  Attacker ────▶ API      ✅ 😱     │
│                                     │
└─────────────────────────────────────┘
```

### La solución

Network Policies = Firewall a nivel de Pods.

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

**¿Qué dice esto?**

1. Para pods con label `app: redis`
2. Solo permitir tráfico ENTRANTE (Ingress)
3. Solo desde pods con label `app: frontend`
4. Solo al puerto 6379

**Resultado**:
```
CON NETWORK POLICIES:
┌─────────────────────────────────────┐
│          KUBERNETES                 │
│                                     │
│  Frontend ────▶ Redis    ✅        │
│  Attacker ────▶ Redis    ❌ 🔒     │
│  Attacker ────▶ API      ❌ 🔒     │
│                                     │
└─────────────────────────────────────┘
```

### ¿Por qué Calico?

Network Policies son un estándar de Kubernetes, pero necesitas un CNI plugin que las implemente.

- **Azure CNI básico**: NO soporta Network Policies
- **Calico**: Soporta Network Policies y más (global policies, etc.)

Por eso en Terraform configuramos:
```hcl
network_policy = "calico"
```
