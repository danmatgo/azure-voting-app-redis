# 📚 FASE 3: Consolidación del Conocimiento
## Kubernetes Manifests y Deployment a AKS

---

## ✅ Revisión de tus Archivos

| Archivo | Estado | Observaciones |
|---------|--------|---------------|
| `namespace.yaml` | ✅ Perfecto | Namespace con labels apropiados |
| `configmap.yaml` | ✅ Perfecto | Variables de configuración externalizadas |
| `redis-deployment.yaml` | ✅ Perfecto | Deployment + ClusterIP Service |
| `frontend-deployment.yaml` | ✅ Perfecto | Rolling update, probes, resources |
| `frontend-service.yaml` | ✅ Perfecto | LoadBalancer con port mapping correcto |
| `hpa.yaml` | ✅ Perfecto | Autoscaling basado en CPU |

---

## 🔧 Cambios/Ajustes que Hiciste (Errores Resueltos)

### 1. Puerto del Container: 80 → 8080

**Lo que cambiaste:**
```yaml
# Tú pusiste:
ports:
  - containerPort: 8080
livenessProbe:
  httpGet:
    port: 8080
```

**Por qué fue necesario:**
- La imagen base `python:3.11-slim` o tu app Flask probablemente escucha en 8080
- El Service mapea `port: 80` (externo) → `targetPort: 8080` (container)
- Esto es patrón común: usuarios acceden por 80, container usa puerto no-privilegiado

**Lección aprendida**: Siempre verificar en qué puerto escucha la app antes de configurar probes.

---

### 2. Agregaste imagePullPolicy: Always

```yaml
imagePullPolicy: Always
```

**Por qué es importante:**
- Con tag `latest`, Docker puede usar imagen cacheada
- `Always` fuerza a verificar el registry cada vez
- Asegura que siempre tengas la versión más reciente

| Policy | Comportamiento |
|--------|----------------|
| `Always` | Siempre verifica registry (usa más bandwidth) |
| `IfNotPresent` | Usa cache si existe localmente |
| `Never` | Solo usa imagen local |

**En producción con SHA tags**: Usarías `IfNotPresent` porque SHA es inmutable.

---

### 3. HPA Simplificado (solo CPU)

**Tú pusiste:**
```yaml
metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

**Removiste memory** - está bien porque:
- CPU es el indicador más común de carga
- Memory en Python/Flask es más estable
- Menos complejidad = menos posibles problemas

---

## 🏗️ Arquitectura Kubernetes que Desplegaste

```
┌─────────────────────────────────────────────────────────────────┐
│                      NAMESPACE: voting-app                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐          ┌─────────────────────────────┐   │
│  │   ConfigMap     │          │      HPA (frontend-hpa)     │   │
│  │ voting-app-config│          │  min:2 max:10 CPU:70%       │   │
│  └────────┬────────┘          └──────────────┬──────────────┘   │
│           │env                               │scale             │
│           ▼                                  ▼                  │
│  ┌────────────────────────────────────────────────────────┐     │
│  │              DEPLOYMENT: frontend (replicas: 2)         │     │
│  │  ┌──────────┐  ┌──────────┐                            │     │
│  │  │ Pod 1    │  │ Pod 2    │  ← rolling update          │     │
│  │  │ :8080    │  │ :8080    │  ← maxSurge:1              │     │
│  │  └──────────┘  └──────────┘  ← maxUnavailable:0        │     │
│  └────────────────────────────────────────────────────────┘     │
│           │                                                      │
│           ▼                                                      │
│  ┌────────────────────┐                                         │
│  │ SERVICE: frontend  │ ◄─── LoadBalancer                       │
│  │ port: 80           │      IP Pública de Azure                │
│  │ targetPort: 8080   │                                         │
│  └────────────────────┘                                         │
│           │                                                      │
│           │ env REDIS="redis"                                   │
│           ▼                                                      │
│  ┌────────────────────────────────────────────────────────┐     │
│  │              DEPLOYMENT: redis (replicas: 1)            │     │
│  │  ┌──────────┐                                          │     │
│  │  │ Pod      │  ← stateless para práctica               │     │
│  │  │ :6379    │  ← producción usaría PVC                 │     │
│  │  └──────────┘                                          │     │
│  └────────────────────────────────────────────────────────┘     │
│           │                                                      │
│           ▼                                                      │
│  ┌────────────────────┐                                         │
│  │ SERVICE: redis     │ ◄─── ClusterIP (solo interno)           │
│  │ port: 6379         │      DNS: redis.voting-app.svc          │
│  └────────────────────┘                                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📖 Recapitulación: ¿Qué significa cada cosa?

### Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: voting-app
```

| Concepto | Significado |
|----------|-------------|
| `Namespace` | Aislamiento lógico dentro del cluster |
| Por qué usarlo | Separar recursos por proyecto/ambiente |
| Scope | Services, Pods, ConfigMaps son namespace-scoped |

**Comandos útiles:**
```bash
kubectl get all -n voting-app     # Ver todo en el namespace
kubectl config set-context --current --namespace=voting-app  # Default
```

---

### ConfigMap

```yaml
kind: ConfigMap
data:
  TITLE: "Azure Voting App"
  VOTE1VALUE: "Terraform"
```

| Concepto | Significado |
|----------|-------------|
| `ConfigMap` | Almacena configuración no sensible |
| `data` | Pares clave-valor |
| `envFrom` | Inyecta todas las keys como env vars |

**ConfigMap vs Secret:**
- ConfigMap: Configuración visible (titles, URLs, feature flags)
- Secret: Datos sensibles (passwords, API keys) - base64 encoded

---

### Deployment

```yaml
kind: Deployment
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
    spec:
      containers:
        - name: frontend
          image: votingappdevacr.azurecr.io/azure-vote-front:latest
```

| Campo | Significado |
|-------|-------------|
| `replicas: 2` | Siempre mantener 2 pods corriendo |
| `selector.matchLabels` | Cómo el Deployment encuentra sus pods |
| `template` | Plantilla para crear pods |
| `strategy: RollingUpdate` | Actualizar gradualmente |
| `maxSurge: 1` | Máximo 1 pod extra durante update |
| `maxUnavailable: 0` | Siempre al menos 2 disponibles |

**Rolling Update en acción:**
1. Crea un pod nuevo (3 total)
2. Espera que esté Ready
3. Termina un pod viejo (2 total)
4. Repite hasta completar

---

### Probes (Liveness y Readiness)

```yaml
livenessProbe:
  httpGet:
    path: /
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

| Probe | Pregunta | Si falla |
|-------|----------|----------|
| `liveness` | "¿Está vivo?" | Kubernetes reinicia el pod |
| `readiness` | "¿Puede recibir tráfico?" | Se remueve del Service |

| Parámetro | Significado |
|-----------|-------------|
| `initialDelaySeconds` | Espera antes de primer check |
| `periodSeconds` | Cada cuánto verificar |
| `failureThreshold` | Cuántos fallos antes de actuar |
| `timeoutSeconds` | Máximo tiempo de espera por respuesta |

---

### Resources (Requests y Limits)

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

| Campo | Significado | Efecto |
|-------|-------------|--------|
| `requests` | Mínimo garantizado | Scheduler usa esto para ubicar pods |
| `limits` | Máximo permitido | Container es killed si excede |

**Unidades:**
- `100m` = 100 millicores = 0.1 CPU
- `128Mi` = 128 Mebibytes

---

### Service

```yaml
kind: Service
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: frontend
```

| Campo | Significado |
|-------|-------------|
| `type: LoadBalancer` | Crea Azure Load Balancer con IP pública |
| `port: 80` | Puerto donde escucha el Service |
| `targetPort: 8080` | Puerto del container |
| `selector` | Qué pods reciben el tráfico |

**Tipos de Service:**
| Tipo | Acceso | Uso |
|------|--------|-----|
| `ClusterIP` | Solo interno | Backend, databases |
| `NodePort` | Puerto en cada nodo | Raro en cloud |
| `LoadBalancer` | IP pública | Frontend, APIs |

---

### HPA (Horizontal Pod Autoscaler)

```yaml
kind: HorizontalPodAutoscaler
spec:
  scaleTargetRef:
    kind: Deployment
    name: frontend
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          averageUtilization: 70
```

| Campo | Significado |
|-------|-------------|
| `scaleTargetRef` | Qué Deployment escalar |
| `minReplicas` | Nunca menos de 2 |
| `maxReplicas` | Nunca más de 10 |
| `averageUtilization: 70` | Escala cuando promedio CPU > 70% |

**behavior:**
- `stabilizationWindowSeconds: 300` para scaleDown: Evita "flapping"
- `stabilizationWindowSeconds: 0` para scaleUp: Respuesta inmediata

---

## 🐛 Errores Comunes y Soluciones (Para Entrevista)

### Error 1: ImagePullBackOff

```
STATUS: ImagePullBackOff
```

**Causas:**
1. Imagen no existe en el registry
2. No hay permisos de pull (ACR → AKS)
3. Nombre/tag incorrecto

**Debug:**
```bash
kubectl describe pod <pod-name> -n voting-app
# Buscar sección Events
```

**Solución:**
```bash
# Verificar que la imagen existe
az acr repository show-tags --name votingappdevacr --repository azure-vote-front

# Verificar role assignment
az role assignment list --assignee <aks-kubelet-id> --scope <acr-id>
```

---

### Error 2: CrashLoopBackOff

```
STATUS: CrashLoopBackOff
```

**Causas:**
1. La app crashea al iniciar
2. Puerto incorrecto (probe falla)
3. Variable de entorno faltante (ej: REDIS)

**Debug:**
```bash
kubectl logs <pod-name> -n voting-app
kubectl logs <pod-name> -n voting-app --previous  # Logs del crash anterior
```

---

### Error 3: Pending (Pod no arranca)

```
STATUS: Pending
```

**Causas:**
1. No hay nodos con recursos suficientes
2. Node pool en scaling
3. PVC pending (si usa storage)

**Debug:**
```bash
kubectl describe pod <pod-name> -n voting-app
# Buscar: "Insufficient cpu" o "Insufficient memory"
```

---

### Error 4: Service no tiene EXTERNAL-IP

```
NAME       TYPE           EXTERNAL-IP   PORT(S)
frontend   LoadBalancer   <pending>     80:32100/TCP
```

**Causas:**
1. Azure LB aún provisionando (esperar ~2 min)
2. Cuota de IPs públicas excedida
3. NSG bloqueando

**Solución:**
```bash
kubectl get svc frontend -n voting-app -w  # Esperar
kubectl describe svc frontend -n voting-app  # Ver eventos
```

---

## 🎤 Preguntas de Entrevista - Kubernetes

### Básicas

**P: ¿Cuál es la diferencia entre un Pod y un Deployment?**
> "Un Pod es la unidad mínima - un contenedor o grupo que comparten storage y red. Pero los Pods son efímeros, si mueren no regresan. Un Deployment es un controlador que mantiene un número deseado de Pods, los recrea si fallan, y maneja rolling updates. En producción siempre uso Deployments, nunca Pods directamente."

**P: ¿Para qué sirve un Service en Kubernetes?**
> "Los Pods tienen IPs que cambian cuando se recrean. El Service da una IP estable y nombre DNS, y hace load balancing entre los Pods. Por ejemplo, mi frontend se conecta al Service 'redis', no directamente a los Pods - si Redis se reinicia con nueva IP, el frontend sigue funcionando."

**P: ¿Qué es Rolling Update y por qué es importante?**
> "Es la estrategia de deployment por defecto. Reemplaza pods gradualmente: crea uno nuevo, espera que esté healthy, luego termina uno viejo. Así no hay downtime. Configuro maxSurge y maxUnavailable para controlar la velocidad. En mi proyecto usé maxUnavailable:0 para garantizar siempre 2 pods disponibles."

### Intermedias

**P: ¿Cuándo usarías Liveness vs Readiness probe?**
> "Liveness detecta si la app está colgada - si falla, Kubernetes reinicia el pod. Readiness detecta si puede recibir tráfico - si falla, se remueve del Service pero sigue corriendo. Por ejemplo, durante un deployment nuevo, el pod puede estar vivo pero cargando datos, entonces liveness pasa pero readiness no hasta que termine."

**P: ¿Qué pasa si no defines resource requests/limits?**
> "Sin requests, el scheduler no sabe cuántos recursos necesita el pod, puede sobrecargar nodos. Sin limits, un pod puede consumir toda la CPU/memoria del nodo, afectando otros pods. Es best practice siempre definir ambos - requests para scheduling, limits para protección."

**P: ¿Cómo debuggeas un pod que no arranca?**
> "Primero `kubectl describe pod` para ver eventos - puede ser ImagePullBackOff, Pending por recursos, o error de scheduling. Luego `kubectl logs` para ver output de la app. Si crashea, `kubectl logs --previous` muestra logs del crash anterior. También verifico `kubectl get events` para ver problemas a nivel cluster."

### Avanzadas

**P: ¿Cómo implementarías blue-green deployment?**
> "Tendría dos Deployments: blue (producción actual) y green (nueva versión). Ambos corren simultáneamente. El Service apunta a blue. Después de validar green, cambio el selector del Service para apuntar a green. Si hay problemas, cambio de vuelta a blue instantáneamente. Es más recursos pero rollback inmediato."

**P: ¿Qué son Network Policies y cuándo las usarías?**
> "Son firewalls a nivel de Pod. Por defecto, todos los pods pueden comunicarse entre sí. Con Network Policies, puedo restringir - por ejemplo, solo el frontend puede conectarse a Redis, nada más. Las usaría en producción para defense in depth, especialmente en clusters multi-tenant."

**P: ¿Cómo manejarías secrets en Kubernetes?**
> "Kubernetes Secrets están en base64, no encriptados. Para producción integro con Azure Key Vault usando el CSI driver o AAD Pod Identity. Los secrets se montan como archivos o variables, y la rotación es automática. Nunca guardo secrets en Git ni en ConfigMaps."

---

## 🔑 Keywords para la Entrevista

| Keyword | Cómo usarla |
|---------|-------------|
| **Desired state** | "Kubernetes mantiene el estado deseado automáticamente" |
| **Self-healing** | "Si un pod muere, el Deployment lo recrea" |
| **Rolling update** | "Zero downtime deployments con rolling update" |
| **Declarative** | "Defino QUÉ quiero, no CÓMO hacerlo" |
| **Pod anti-affinity** | "Distribuyo pods en diferentes nodos para HA" |
| **Resource quotas** | "Limito recursos por namespace para control de costos" |
| **Labels y selectors** | "Todo en K8s se conecta mediante labels" |
| **Horizontal scaling** | "HPA escala pods, Cluster Autoscaler escala nodos" |

---

## 📋 Comandos que Ejecutaste

```bash
# Conectar a AKS
az aks get-credentials --resource-group votingapp-dev-rg --name votingapp-dev-aks

# Aplicar manifests en orden
kubectl apply -f namespace.yaml
kubectl apply -f configmap.yaml
kubectl apply -f redis-deployment.yaml
kubectl apply -f frontend-deployment.yaml
kubectl apply -f frontend-service.yaml
kubectl apply -f hpa.yaml

# Verificar
kubectl get all -n voting-app
kubectl get svc frontend -n voting-app  # Ver IP pública

# Debug útil
kubectl describe pod <name> -n voting-app
kubectl logs <pod-name> -n voting-app
kubectl exec -it <pod-name> -n voting-app -- /bin/sh
```

---

## ✅ Checklist Conocimiento Fase 3

- [ ] Puedo explicar Pod vs Deployment vs Service
- [ ] Entiendo rolling update y sus parámetros
- [ ] Sé la diferencia entre Liveness y Readiness probes
- [ ] Puedo explicar ClusterIP vs LoadBalancer
- [ ] Entiendo requests vs limits y por qué son importantes
- [ ] Sé debuggear ImagePullBackOff y CrashLoopBackOff
- [ ] Puedo explicar HPA y cuándo usarlo
- [ ] Entiendo cómo funciona el DNS interno de Kubernetes

---

## 🎓 Resumen: Lo que Puedes Decir en la Entrevista

> "En mi último proyecto implementé una aplicación multi-tier en AKS. Usé Deployments con rolling update strategy - configuré maxUnavailable:0 para garantizar zero downtime. Cada pod tiene liveness y readiness probes; el liveness reinicia pods colgados, el readiness previene enviar tráfico a pods que aún están iniciando. Para el backend usé ClusterIP porque solo necesita acceso interno, y LoadBalancer para el frontend. También configuré HPA para escalar automáticamente basado en CPU al 70%, con min 2 réplicas para HA y max 10 para controlar costos. Todo declarativo, versionado en Git, y desplegado con kubectl apply."
