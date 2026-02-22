# 🧠 GUÍA MAESTRA - PARTE 3
## Kubernetes - Explicación profunda

---

# ☸️ KUBERNETES - ¿POR QUÉ EXISTE?

## El problema que Docker NO resuelve

Docker es genial para empaquetar y correr UN contenedor. Pero en producción:

| Pregunta | Docker solo | Necesitas algo más |
|----------|-------------|-------------------|
| ¿Qué pasa si un contenedor se cae? | Se queda caído | Algo que lo reinicie |
| ¿Cómo corro 10 copias? | Manualmente | Algo que lo maneje |
| ¿Cómo distribuyo tráfico entre copias? | Manualmente | Un load balancer |
| ¿Cómo actualizo sin downtime? | Bajar, actualizar, subir | Rolling updates |
| ¿Cómo escalo cuando hay más tráfico? | Adivinar y crear más | Autoscaling |

**Kubernetes resuelve todos estos problemas.**

## Conceptos fundamentales

### Cluster

Un cluster de Kubernetes es un grupo de máquinas trabajando juntas.

```
┌─────────────────────────────────────────────────────────────┐
│                     KUBERNETES CLUSTER                       │
│                                                              │
│  ┌────────────────────┐  ┌────────────────────┐             │
│  │   CONTROL PLANE    │  │       NODES        │             │
│  │   (El cerebro)     │  │  (Los trabajadores) │            │
│  │                    │  │                    │             │
│  │  - API Server      │  │  Node 1            │             │
│  │  - Scheduler       │  │  ├── Pod A         │             │
│  │  - Controller Mgr  │  │  └── Pod B         │             │
│  │  - etcd            │  │                    │             │
│  │                    │  │  Node 2            │             │
│  │                    │  │  ├── Pod C         │             │
│  │                    │  │  └── Pod D         │             │
│  └────────────────────┘  └────────────────────┘             │
└─────────────────────────────────────────────────────────────┘
```

**Control Plane** (en AKS, Azure lo maneja por ti):
- **API Server**: El punto de entrada. Todo pasa por aquí.
- **Scheduler**: Decide en qué Node correr cada Pod.
- **Controller Manager**: Mantiene el estado deseado.
- **etcd**: Base de datos de todo el estado del cluster.

**Nodes** (tú pagas por estos):
- Máquinas virtuales que corren tus contenedores
- Cada Node tiene un agente (kubelet) que habla con el Control Plane

### Pod

La unidad más pequeña en Kubernetes. Un Pod contiene uno o más contenedores.

```
POD = Grupo de contenedores que:
├── Comparten network namespace (misma IP)
├── Comparten storage volumes
├── Se schedulejan juntos en el mismo Node
└── Se escalan juntos

CASO TÍPICO: 1 contenedor por Pod
CASO AVANZADO: App + sidecar (logging, proxy, etc.)
```

**¿Por qué Pod y no Container directamente?**

El Pod agrega funcionalidades:
- Health checks (liveness, readiness)
- Restart policies
- Resource limits
- Volumes compartidos

### Deployment

Un Deployment maneja un grupo de Pods idénticos.

```
DEPLOYMENT "frontend"
│
├── ReplicaSet (maneja las réplicas)
│   │
│   ├── Pod frontend-abc123
│   ├── Pod frontend-def456
│   └── Pod frontend-ghi789
│
└── Strategy: RollingUpdate
```

**¿Por qué no crear Pods directamente?**

1. Si un Pod muere, nadie lo recrea
2. No hay forma de tener múltiples copias idénticas
3. No hay forma de actualizar sin downtime

El Deployment se encarga de todo esto.

### Service

Un Service da una dirección estable a un grupo de Pods.

**El problema**: Los Pods son efímeros. Su IP cambia cada vez que se recrean.

```
SIN SERVICE:
App → Pod IP 10.244.0.5 → Pod muere
App → 10.244.0.5 ??? → Error!

CON SERVICE:
App → Service "redis" → Cualquier Pod con label app=redis
                       (Kubernetes resuelve automáticamente)
```

**Tipos de Service**:

```
ClusterIP (default):
┌─────────────────────────────────┐
│         CLUSTER                 │
│                                 │
│  App ──── ClusterIP ──── Pods  │
│           (solo interno)        │
└─────────────────────────────────┘
Solo accesible dentro del cluster.
Uso: bases de datos, services internos.


NodePort:
┌─────────────────────────────────┐
│         CLUSTER                 │
│                                 │      ┌──────────┐
│  NodePort ──────── Pods        │◀─────│ Internet │
│  (puerto 30000-32767)           │      └──────────┘
└─────────────────────────────────┘
Abre un puerto en cada Node.
Uso: testing, acceso directo a nodes.


LoadBalancer:
┌─────────────────────────────────┐      ┌──────────────┐
│         CLUSTER                 │      │ Azure        │
│                                 │◀─────│ Load Balancer│◀── Internet
│  LoadBalancer ──── Pods        │      │ (IP pública) │
└─────────────────────────────────┘      └──────────────┘
Azure crea un Load Balancer real con IP pública.
Uso: aplicaciones web públicas.
```

---

# MANIFESTS DE KUBERNETES - LÍNEA POR LÍNEA

## namespace.yaml

```yaml
apiVersion: v1
```
**¿Qué es?**: La versión de la API de Kubernetes para este tipo de recurso.

Diferentes recursos tienen diferentes versiones:
- `v1`: Stable, para Pods, Services, etc.
- `apps/v1`: Para Deployments, DaemonSets, etc.
- `autoscaling/v2`: Para HPA

```yaml
kind: Namespace
```
**¿Qué es?**: El tipo de recurso que estamos creando.

```yaml
metadata:
  name: voting-app
  labels:
    app: voting-app
    environment: dev
```
**`metadata`**: Información SOBRE el recurso.
- `name`: Cómo se llama (único dentro del cluster)
- `labels`: Etiquetas clave-valor para organizar y seleccionar recursos

**¿Para qué sirven los labels?**

Para seleccionar recursos. Ejemplos:
- "Dame todos los pods con label `app=frontend`"
- "Borra todo con label `environment=dev`"
- "Aplica política de red a pods con label `tier=backend`"

---

## configmap.yaml

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

**¿Qué es un ConfigMap?**

Un lugar para guardar configuración que no es secreta.

**¿Por qué no hardcodear en el código?**

1. Cambiar config sin reconstruir imagen
2. Diferentes valores para diferentes ambientes
3. Separar configuración de código (buena práctica)

**¿Cómo llega al contenedor?**

Opción 1: Variables de entorno (lo que usamos):
```yaml
envFrom:
  - configMapRef:
      name: voting-app-config
# Result: TITLE=Azure Voting App, VOTE1VALUE=Cats, etc.
```

Opción 2: Archivos montados:
```yaml
volumes:
  - name: config
    configMap:
      name: voting-app-config
# Result: Archivos en el filesystem del contenedor
```

---

## deployment.yaml - Línea por Línea

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: voting-app
  labels:
    app: frontend
```

La metadata del Deployment. `apps/v1` porque Deployments están en el grupo `apps`.

```yaml
spec:
```
**¿Qué es spec?**: La especificación. Lo que QUEREMOS que exista.

```yaml
  replicas: 2
```
**¿Qué significa?**: "Siempre quiero 2 Pods corriendo".

Si hay 0, Kubernetes crea 2.
Si hay 3, Kubernetes mata 1.
Si hay 2, perfecto.

```yaml
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
```

**¿Qué es la estrategia?**: Cómo actualizar cuando cambias la imagen.

**RollingUpdate**: Actualizar gradualmente, sin downtime.

```
Estado inicial:  [Pod1-v1] [Pod2-v1]
Crear nuevo:     [Pod1-v1] [Pod2-v1] [Pod3-v2]
Matar viejo:              [Pod2-v1] [Pod3-v2]
Crear nuevo:              [Pod2-v1] [Pod3-v2] [Pod4-v2]
Matar viejo:                        [Pod3-v2] [Pod4-v2]
Final:                              [Pod3-v2] [Pod4-v2]

→ En todo momento hubo al menos 2 pods sirviendo tráfico
→ ZERO DOWNTIME
```

**`maxUnavailable: 0`**: Nunca tener menos del número deseado.
**`maxSurge: 1`**: Máximo 1 Pod extra durante la transición.

Otra opción es `Recreate`: mata todo y crea de nuevo. Tiene downtime pero es más simple.

```yaml
  selector:
    matchLabels:
      app: frontend
```

**¿Qué hace selector?**: Define qué Pods "pertenecen" a este Deployment.

El Deployment busca Pods con label `app: frontend` y los considera suyos.

**IMPORTANTE**: Esto TIENE que coincidir con los labels del template de abajo.

```yaml
  template:
    metadata:
      labels:
        app: frontend
```

**¿Qué es template?**: La plantilla para crear Pods.

Los labels aquí DEBEN coincidir con el selector de arriba. Si no coinciden, el Deployment crea Pods pero no los reconoce como suyos.

```yaml
    spec:
      containers:
        - name: frontend
          image: votingappdevacr.azurecr.io/azure-vote-front:latest
          imagePullPolicy: Always
```

**`image`**: Qué imagen Docker usar.

**`imagePullPolicy`**:
- `Always`: Siempre descargar del registry (asegura última versión)
- `IfNotPresent`: Solo descargar si no está en el Node
- `Never`: Nunca descargar (solo usar caché local)

**¿Por qué `Always`?**: Si usamos tag `latest`, queremos la última versión. Si no, cada Node podría tener versiones diferentes cacheadas.

En producción se usan tags específicos (ej: `v1.2.3` o el SHA del commit).

```yaml
          ports:
            - containerPort: 8080
```

**¿Qué hace?**: Documenta que el contenedor escucha en puerto 8080.

**NO abre el puerto.** Es solo documentación. El puerto se expone via Service.

```yaml
          envFrom:
            - configMapRef:
                name: voting-app-config
```

Inyecta TODAS las claves del ConfigMap como variables de entorno.

Si el ConfigMap tiene:
```yaml
data:
  TITLE: "Azure Voting App"
  VOTE1VALUE: "Cats"
```

El contenedor tiene:
```
TITLE=Azure Voting App
VOTE1VALUE=Cats
```

```yaml
          env:
            - name: REDIS
              value: "redis"
```

Una variable de entorno específica. Le dice a la app dónde está Redis.

**¿Por qué "redis"?**: Es el nombre del Service de Redis. Kubernetes DNS resuelve "redis" a la IP del Service.

```yaml
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
```

**¿Qué son requests y limits?**

```
requests = Lo que Kubernetes GARANTIZA al Pod
limits = Lo MÁXIMO que el Pod puede usar

requests:
├── Scheduler usa esto para decidir en qué Node poner el Pod
└── "Necesito al menos 100m CPU para funcionar"

limits:
├── Si el Pod intenta usar más, Kubernetes lo throttlea (CPU) o lo mata (memoria)
└── "Nunca dejes que use más de 500m CPU"
```

**¿Qué significa "m" en CPU?**

`m` = millicores. 1000m = 1 CPU.

- `100m` = 0.1 CPU (10% de un core)
- `500m` = 0.5 CPU (50% de un core)

**¿Por qué especificar esto?**

Sin limits, un Pod puede monopolizar todo el Node y matar a los demás.
Sin requests, el Scheduler no sabe cuánto espacio necesita.

```yaml
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 10
```

**¿Qué es livenessProbe?**

Pregunta: "¿Está VIVO el proceso?"

Si falla repetidamente → Kubernetes MATA el Pod y crea uno nuevo.

**¿Cuándo falla livenessProbe?**
- La aplicación se colgó (deadlock)
- La aplicación crasheó pero el proceso sigue
- El Pod no responde

**Parámetros**:
- `initialDelaySeconds: 15`: Esperar 15s antes del primer check (dar tiempo a que arranque)
- `periodSeconds: 10`: Revisar cada 10 segundos

```yaml
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
```

**¿Qué es readinessProbe?**

Pregunta: "¿Está LISTO para recibir tráfico?"

Si falla → Kubernetes DEJA de enviar tráfico al Pod (pero NO lo mata).

**¿Cuándo falla readinessProbe?**
- La app está iniciando (cargando datos)
- La app perdió conexión a la base de datos
- La app está temporalmente ocupada

**Diferencia clave**:

| Probe | Si falla | Ejemplo de uso |
|-------|----------|----------------|
| liveness | Mata el Pod | App se colgó, necesita reinicio |
| readiness | Deja de enviar tráfico | App está iniciando, no lista aún |

**Ejemplo práctico**:

```
Pod arranca
│
├── 0s-5s: readiness failing (normal, está arrancando)
│          → No recibe tráfico
│
├── 5s: readiness passing
│       → Empieza a recibir tráfico
│
└── Después: liveness checking cada 10s
             → Si falla 3 veces, reiniciar Pod
```

---

## service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: voting-app
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: frontend
```

**`type: LoadBalancer`**: Azure creará un Load Balancer real con IP pública.

**`port: 80`**: El puerto expuesto al mundo (lo que el usuario pone en el navegador).

**`targetPort: 8080`**: El puerto al que envía el tráfico (donde el contenedor escucha).

```
Usuario ──HTTP:80──▶ Load Balancer ──:8080──▶ Pod
```

**`selector: app: frontend`**: Envía tráfico a TODOS los Pods con label `app: frontend`.

Kubernetes automáticamente balancea entre todos los Pods que matchean.

---

## hpa.yaml (Horizontal Pod Autoscaler)

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
```

**¿Qué hace el HPA?**

Automáticamente ajusta el número de réplicas basado en métricas.

**Flujo**:
```
1. HPA lee métricas de CPU de todos los Pods del frontend
2. Calcula el promedio
3. Si promedio > 70% → agregar réplicas
4. Si promedio < 70% → quitar réplicas (pero nunca menos de minReplicas)
```

**Ejemplo**:

```
Situación: 2 pods, cada uno al 85% CPU
           Promedio = 85%
           Target = 70%
           
HPA calcula: necesito ~ 85/70 * 2 = 2.4 → 3 pods

Resultado: HPA crea 1 pod más

Nueva situación: 3 pods, cada uno al ~57% CPU
                 Promedio = 57%
                 
HPA: OK, no haré nada
```

**¿Por qué min 2?**: Alta disponibilidad. Si uno muere, el otro sigue sirviendo mientras se recrea.

**¿Por qué max 10?**: Prevenir runaway scaling. Si hay un bug que causa 100% CPU, no queremos crear infinitos pods.

---

## pdb.yaml (PodDisruptionBudget)

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
```

**¿Qué es PDB?**

Una garantía de disponibilidad durante operaciones voluntarias (upgrades, drain, etc.).

**¿Qué es una "disruption voluntaria"?**

- Admin drena un Node para mantenimiento
- Upgrade de Kubernetes
- Scaling down del cluster

**Sin PDB**:
```
Admin: kubectl drain node-1
Kubernetes: OK, mato todos los pods de node-1
            (incluyendo los 2 únicos frontends)
Usuarios: ERROR 503
```

**Con PDB**:
```
Admin: kubectl drain node-1
Kubernetes: Hay 2 frontends en node-1, pero PDB dice minAvailable=1
            Mato 1, espero a que otro esté listo,
            luego mato el segundo
Usuarios: (ni se enteran)
```

**`minAvailable: 1`**: Siempre debe haber al menos 1 Pod disponible.

Alternativa: `maxUnavailable: 1` = máximo 1 puede estar no-disponible a la vez.
