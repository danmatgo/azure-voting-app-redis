# 🚀 Guía Práctica Domingo
## Fases 6-8: Monitoring Enterprise, Cost Optimization & Troubleshooting

> **Tiempo estimado**: ~5 horas
> **Objetivo**: Operaciones del día a día, monitoring enterprise con Prometheus/Grafana, y skills de troubleshooting

---

# 📋 Agenda del Día

| Tiempo | Fase | Tema |
|--------|------|------|
| 30min | Prep | Recrear infraestructura |
| 2.5h | 6 | Monitoring Enterprise (Azure Monitor + Prometheus + Grafana) |
| 30min | 7 | Cost Optimization |
| 1.5h | 8 | Troubleshooting Práctico |

---

# 🔄 PREPARACIÓN: Recrear Infraestructura (30 min)

```powershell
cd "c:\Users\Daniel Matapi\cloud-practice\azure-voting-app-redis\terraform"

# Si ya tienes remote backend
terraform init
terraform apply -var-file="environments/dev.tfvars" -auto-approve

# Configurar kubectl
az aks get-credentials --resource-group votingapp-dev-rg --name votingapp-dev-aks --overwrite-existing

# Desplegar app con Kustomize
kubectl apply -k k8s/overlays/dev

# Verificar
kubectl get all -n voting-app
```

---

# FASE 6: MONITORING ENTERPRISE (2.5h)

## 🎓 Conceptos Clave

### Los 4 Golden Signals de Google SRE

```
┌─────────────────────────────────────────────────────────────┐
│                   4 GOLDEN SIGNALS                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. LATENCY         → ¿Qué tan rápido responde?            │
│     (tiempo de respuesta)                                   │
│                                                             │
│  2. TRAFFIC         → ¿Cuántas requests recibe?            │
│     (requests/segundo)                                      │
│                                                             │
│  3. ERRORS          → ¿Cuántas requests fallan?            │
│     (tasa de errores %)                                     │
│                                                             │
│  4. SATURATION      → ¿Qué tan llenos están los recursos?  │
│     (CPU, memoria, disco)                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Stack de Monitoring Enterprise

```
┌─────────────────────────────────────────────────────────────┐
│              MONITORING STACK ENTERPRISE                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  CAPA 1: Infraestructura (Azure Monitor)                    │
│  ├── Container Insights (ya configurado)                    │
│  ├── Log Analytics (KQL queries)                            │
│  └── Azure Alerts                                           │
│                                                             │
│  CAPA 2: Métricas (Prometheus)                              │
│  ├── Scraping de métricas de pods                          │
│  ├── Recording rules                                        │
│  └── PromQL para queries                                    │
│                                                             │
│  CAPA 3: Visualización (Grafana)                            │
│  ├── Dashboards unificados                                  │
│  ├── Alerting avanzado                                      │
│  └── Multi-datasource                                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### ¿Por qué Prometheus + Grafana además de Azure Monitor?

| Herramienta | Fortaleza | Caso de Uso |
|-------------|-----------|-------------|
| **Azure Monitor** | Infraestructura Azure, integración nativa | Nodos, cluster health, Azure services |
| **Prometheus** | Métricas de aplicación, estándar K8s | Custom metrics, pod-level, service mesh |
| **Grafana** | Visualización, multi-source | Dashboards unificados, business metrics |

**En entrevista**: "Usamos Azure Monitor para infraestructura y Prometheus/Grafana para métricas de aplicación. Este enfoque multi-herramienta nos da visibilidad completa del stack."

---

## Paso 6.1: Ver Métricas en Azure Portal (Container Insights)

```powershell
# Abre el portal directamente en AKS
$RG = "votingapp-dev-rg"
$AKS = "votingapp-dev-aks"

# Obtener la URL del portal
Write-Host "Abre: https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG/providers/Microsoft.ContainerService/managedClusters/$AKS/overview"
```

En el portal:
1. Ve a **Insights** en el menú lateral
2. Explora las pestañas: **Cluster**, **Nodes**, **Controllers**, **Containers**
3. Ve las métricas de CPU y memoria de tus pods

---

## Paso 6.2: Habilitar Azure Managed Prometheus

### ¿Qué es Azure Managed Prometheus?

Servicio totalmente gestionado que:
- Recolecta métricas de Kubernetes automáticamente
- Almacena en Azure Monitor Workspace
- Compatible 100% con PromQL
- Sin necesidad de administrar servidores

```powershell
$RG = "votingapp-dev-rg"
$AKS = "votingapp-dev-aks"

# Crear Azure Monitor Workspace para Prometheus
az monitor account create `
    --name "votingapp-prometheus" `
    --resource-group $RG `
    --location eastus

# Obtener el ID del workspace
$MONITOR_WORKSPACE_ID = az monitor account show `
    --name "votingapp-prometheus" `
    --resource-group $RG `
    --query id -o tsv

# Habilitar Prometheus en AKS
az aks update `
    --name $AKS `
    --resource-group $RG `
    --enable-azure-monitor-metrics `
    --azure-monitor-workspace-resource-id $MONITOR_WORKSPACE_ID

Write-Host "Prometheus habilitado! Espera 2-3 minutos para que empiecen las métricas"
```

### Verificar que Prometheus está funcionando

```powershell
# Ver los pods del agente de Prometheus
kubectl get pods -n kube-system | Select-String "ama-metrics"

# Deberías ver algo como:
# ama-metrics-node-xxxxx     Running
# ama-metrics-xxxxx          Running
```

---

## Paso 6.3: Crear Azure Managed Grafana

### ¿Qué es Azure Managed Grafana?

- Grafana totalmente gestionado por Azure
- Integración automática con Azure AD (SSO)
- Conecta con Prometheus, Azure Monitor, Log Analytics
- Dashboards pre-configurados para AKS

```powershell
$RG = "votingapp-dev-rg"

# Crear instancia de Grafana (esto toma ~3-5 minutos)
az grafana create `
    --name "votingapp-grafana" `
    --resource-group $RG `
    --location eastus

# Obtener la URL de Grafana
$GRAFANA_URL = az grafana show `
    --name "votingapp-grafana" `
    --resource-group $RG `
    --query "properties.endpoint" -o tsv

Write-Host "Grafana disponible en: $GRAFANA_URL"
```

### Conectar Grafana con Prometheus

```powershell
# Obtener IDs necesarios
$GRAFANA_ID = az grafana show --name "votingapp-grafana" --resource-group $RG --query id -o tsv
$MONITOR_WORKSPACE_ID = az monitor account show --name "votingapp-prometheus" --resource-group $RG --query id -o tsv

# Asignar rol de lector a Grafana sobre Prometheus workspace
az role assignment create `
    --assignee-object-id $(az grafana show --name "votingapp-grafana" --resource-group $RG --query "identity.principalId" -o tsv) `
    --assignee-principal-type ServicePrincipal `
    --role "Monitoring Reader" `
    --scope $MONITOR_WORKSPACE_ID

# También dar acceso a las métricas del AKS
az role assignment create `
    --assignee-object-id $(az grafana show --name "votingapp-grafana" --resource-group $RG --query "identity.principalId" -o tsv) `
    --assignee-principal-type ServicePrincipal `
    --role "Monitoring Reader" `
    --scope $(az aks show -g $RG -n votingapp-dev-aks --query id -o tsv)

Write-Host "Grafana conectado a Prometheus!"
```

---

## Paso 6.4: Explorar Grafana y Crear Dashboard

### Acceder a Grafana

1. Abre la URL de Grafana (la obtuviste arriba)
2. Login automático con Azure AD
3. Ve a **Dashboards** → **Browse**

### Importar Dashboard de Kubernetes

1. En Grafana, ve a **Dashboards** → **Import**
2. Ingresa ID: `15760` (Kubernetes Cluster Monitoring)
3. Selecciona el datasource de Prometheus
4. Click **Import**

### Crear Dashboard para VotingApp

1. **Dashboards** → **New** → **New Dashboard**
2. Add visualization → Selecciona Prometheus
3. Queries PromQL para la app:

```promql
# CPU por pod del frontend
rate(container_cpu_usage_seconds_total{namespace="voting-app", pod=~".*frontend.*"}[5m])

# Memoria del frontend
container_memory_working_set_bytes{namespace="voting-app", pod=~".*frontend.*"}

# Requests por segundo (si tienes métricas HTTP)
rate(http_requests_total{namespace="voting-app"}[5m])
```

4. Guarda como "VotingApp Dashboard"

---

## Paso 6.5: Queries PromQL Esenciales

### En Grafana → Explore (icono de brújula)

```promql
# CPU total por namespace
sum(rate(container_cpu_usage_seconds_total{namespace="voting-app"}[5m])) by (pod)

# Memoria por container
container_memory_working_set_bytes{namespace="voting-app"} / 1024 / 1024

# Pods en estado Ready
kube_pod_status_ready{namespace="voting-app", condition="true"}

# Restart count (indica problemas)
kube_pod_container_status_restarts_total{namespace="voting-app"}

# Network bytes recibidos
rate(container_network_receive_bytes_total{namespace="voting-app"}[5m])
```

### Comparación: PromQL vs KQL

| PromQL (Prometheus) | KQL (Azure Monitor) | Uso |
|---------------------|---------------------|-----|
| `rate(cpu[5m])` | `Perf \| summarize avg(CPU)` | Promedios de CPU |
| `sum by (pod)` | `\| summarize by PodName` | Agrupar por pod |
| `{namespace="x"}` | `\| where Namespace == "x"` | Filtrar |

---

## Paso 6.6: Crear Alerta en Grafana

1. En tu dashboard, edita el panel de CPU
2. Click en **Alert** tab
3. **Create alert rule**:
   - Condition: `WHEN avg() OF query IS ABOVE 0.8`
   - Evaluate every: 1m
   - For: 5m
4. Add notification channel (configura email o Slack)
5. Save

### También en Azure Monitor (ya lo tenías):

```powershell
$RG = "votingapp-dev-rg"
$AKS = "votingapp-dev-aks"

# Crear Action Group
az monitor action-group create `
    --name "votingapp-alerts" `
    --resource-group $RG `
    --short-name "voting" `
    --action email admin tu-email@example.com

# Crear Alerta de CPU
az monitor metrics alert create `
    --name "high-cpu-alert" `
    --resource-group $RG `
    --scopes $(az aks show -g $RG -n $AKS --query id -o tsv) `
    --condition "avg node_cpu_usage_percentage > 80" `
    --window-size 5m `
    --evaluation-frequency 1m `
    --severity 2 `
    --description "CPU del nodo supera 80%"
```

---

## Paso 6.7: Query de Logs con KQL

En Azure Portal → Log Analytics Workspace → Logs:

```kusto
// Ver logs de los containers del frontend
ContainerLogV2
| where ContainerName == "frontend"
| where TimeGenerated > ago(1h)
| project TimeGenerated, LogMessage, ContainerName
| order by TimeGenerated desc
| take 50
```

```kusto
// Ver pods con alto consumo de memoria
KubePodInventory
| where Namespace == "voting-app"
| join kind=inner (
    Perf
    | where ObjectName == "K8SContainer"
    | where CounterName == "memoryWorkingSetBytes"
    | summarize AvgMemory = avg(CounterValue) by InstanceName
) on $left.ContainerID == $right.InstanceName
| project PodName = Name, AvgMemoryMB = AvgMemory / 1024 / 1024
| order by AvgMemoryMB desc
```

```kusto
// Errores en los últimos 30 minutos
ContainerLogV2
| where TimeGenerated > ago(30m)
| where LogMessage contains "error" or LogMessage contains "Error" or LogMessage contains "ERROR"
| project TimeGenerated, ContainerName, LogMessage
```

---

## 🎓 Cuándo usar cada herramienta

```
┌─────────────────────────────────────────────────────────────┐
│           DECISION TREE: QUÉ HERRAMIENTA USAR               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ¿Es métrica de infraestructura Azure?                      │
│  └── SÍ → Azure Monitor                                     │
│       (nodos, networking, storage)                          │
│                                                             │
│  ¿Es métrica de aplicación/pods?                            │
│  └── SÍ → Prometheus + Grafana                              │
│       (custom metrics, request rates, latency)              │
│                                                             │
│  ¿Necesitas logs detallados?                                │
│  └── SÍ → Log Analytics + KQL                               │
│       (debugging, audit, troubleshooting)                   │
│                                                             │
│  ¿Dashboard para stakeholders?                              │
│  └── SÍ → Grafana                                           │
│       (visualización bonita, multi-source)                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## ✅ Checklist Fase 6

- [ ] Exploré Container Insights en el portal
- [ ] Habilité Azure Managed Prometheus
- [ ] Creé Azure Managed Grafana
- [ ] Conecté Grafana con Prometheus
- [ ] Importé dashboard de Kubernetes
- [ ] Ejecuté queries PromQL básicas
- [ ] Ejecuté queries KQL en Log Analytics
- [ ] Creé al menos una alerta
- [ ] Entiendo los 4 Golden Signals
- [ ] Sé cuándo usar cada herramienta

---

# FASE 7: FINOPS & COST MANAGEMENT (45 min)

## 🎓 ¿Qué es FinOps?

**FinOps** = Financial Operations para Cloud. Es la práctica de dar **visibilidad, control y optimización** de costos cloud a toda la organización.

```
┌─────────────────────────────────────────────────────────────┐
│                    CICLO FINOPS                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│     INFORM ──────▶ OPTIMIZE ──────▶ OPERATE                │
│        │               │               │                    │
│        │               │               │                    │
│   Visibilidad     Reducir          Gobierno                │
│   de costos       desperdicio      continuo                │
│        │               │               │                    │
│        ▼               ▼               ▼                    │
│   - Dashboards    - Right-size     - Budgets               │
│   - Reports       - Reserved       - Alertas               │
│   - Allocations   - Spot VMs       - Policies              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎓 Dónde se gasta dinero en tu setup

```
┌─────────────────────────────────────────────────────────────┐
│                    COSTOS DEL PROYECTO                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  GRATIS:                                                    │
│  ├── Control plane (AKS)                                    │
│  ├── Kubernetes API                                         │
│  └── GitHub Actions (2000 min/mes free)                     │
│                                                             │
│  PAGADO (orden de impacto):                                 │
│  ├── 💰💰💰 VMs de los nodos (70-80% del costo)            │
│  ├── 💰💰  Azure Managed Grafana (~$90/mes)                │
│  ├── 💰    Load Balancer (~$20/mes)                        │
│  ├── 💰    Log Analytics (por GB ingestado)                │
│  ├── 💰    Azure Monitor Workspace (Prometheus)            │
│  ├── 💵    Storage (discos OS de nodos)                    │
│  └── 💵    ACR Basic (~$5/mes)                             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Paso 7.1: Azure Cost Management (Portal)

### Navegar al portal

1. Abre: **https://portal.azure.com**
2. Busca: **"Cost Management + Billing"**
3. Click en **"Cost Management"** → **"Cost analysis"**

### Explorar Cost Analysis

```
FILTROS IMPORTANTES:
├── Scope: Selecciona tu suscripción o Resource Group
├── View: Cambia entre "Accumulated" y "Daily"
├── Group by: 
│   ├── Resource (ver qué recursos cuestan más)
│   ├── Resource type (ver por tipo: VMs, Storage, etc.)
│   ├── Tag (si usas tags de cost allocation)
│   └── Service name (services de Azure)
└── Date range: Últimos 7 días, este mes, custom
```

### Lo que debes mirar:

1. **Top 5 recursos más caros** - usualmente son VMs
2. **Tendencia diaria** - ¿hay picos anormales?
3. **Forecast** - Azure predice cuánto gastarás este mes

---

## Paso 7.2: Crear Budget con Alertas

### Desde el Portal (RECOMENDADO)

1. En Cost Management → **Budgets** → **+ Add**
2. Configurar:

| Campo | Valor para tu proyecto |
|-------|----------------------|
| Name | `votingapp-dev-budget` |
| Reset period | Monthly |
| Amount | $50 (o lo que consideres razonable) |

3. En **Alert conditions**, agregar:

| % del budget | Acción |
|--------------|--------|
| 50% | Email de aviso "vas a mitad" |
| 80% | Email de warning "cerca del límite" |
| 100% | Email urgente + considera auto-shutdown |

4. En **Alert recipients**: tu email

### ¿Por qué es crítico en enterprise?

```
ESCENARIO REAL:
┌─────────────────────────────────────────────────────────────┐
│  Sin Budget:                                                 │
│  └── Developer deja cluster corriendo el fin de semana      │
│      └── Lunes: factura de $500 inesperada 💸               │
│                                                             │
│  Con Budget + Alertas:                                       │
│  └── Viernes 5pm: alerta "80% del budget"                   │
│      └── Developer: "ah, debo destruir antes de irme"       │
│          └── Lunes: $0 de sorpresas ✅                      │
└─────────────────────────────────────────────────────────────┘
```

---

## Paso 7.3: Azure Advisor (Recomendaciones Automáticas)

### Navegar a Advisor

1. En Azure Portal, busca: **"Advisor"**
2. Ve a la pestaña **"Cost"**

### Qué te puede recomendar:

| Recomendación | Explicación |
|--------------|-------------|
| **Resize underutilized VMs** | "Tu VM usa 5% CPU, bájala de tamaño" |
| **Buy Reserved Instances** | "Llevas 3 meses con esta VM, compra reserva" |
| **Delete unattached disks** | "Este disco no está conectado a nada" |
| **Shutdown unused resources** | "Este recurso no se ha usado en 30 días" |

### En tu proyecto probablemente verás:

- ✅ Ya usas B-series (burstable) - optimizado
- ⚠️ Posiblemente: "Consider Reserved Instances" (ignorar, es dev)
- ⚠️ Posiblemente: "Delete unattached resources" (limpiar después)

---

## Paso 7.4: Cost Allocation con Tags

### ¿Qué son los Tags de costo?

Etiquetas que agregas a recursos para saber **quién** o **qué proyecto** los usa.

### Tags que ya tienes en Terraform:

```hcl
# Ya definidos en tu variables.tf
tags = {
  Project     = "VotingApp"
  Environment = "dev"
  Owner       = "Daniel"
  ManagedBy   = "Terraform"
}
```

### Cómo usarlos en Cost Analysis:

1. En Cost Analysis → **Group by** → **Tag**
2. Selecciona tag: `Project` o `Environment`
3. Ahora ves costos separados por proyecto/ambiente

### En enterprise:

```
EJEMPLO REAL DE TAGS:
┌─────────────────────────────────────────────────────────────┐
│  Empresa con 50 equipos:                                     │
│                                                             │
│  Tags obligatorios:                                          │
│  ├── CostCenter: "CC-12345" (para contabilidad)             │
│  ├── Team: "platform-engineering"                           │
│  ├── Project: "customer-portal"                             │
│  └── Environment: "prod/staging/dev"                        │
│                                                             │
│  Reportes mensuales:                                         │
│  ├── "El equipo Platform gastó $5,000 este mes"            │
│  ├── "El proyecto Customer Portal cuesta $2,000/mes"        │
│  └── "Tenemos $3,000 en recursos sin tags (¡investigar!)"  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Paso 7.5: Alertas de Anomalías de Costo

### Configurar Anomaly Alerts

1. En Cost Management → **Cost alerts** → **+ Add**
2. Tipo: **Anomaly alert**
3. Configurar:
   - Scope: Tu suscripción
   - Email recipients: tu correo
   
Esto te avisa cuando hay un **gasto inusual** (ej: alguien crea 10 VMs por error).

---

## Paso 7.6: Optimizaciones Enterprise (Conocimiento para Entrevista)

### Matriz de Optimización

| Estrategia | Ahorro | Cuándo usar | Ya implementado |
|------------|--------|-------------|-----------------|
| **B-series (Burstable)** | ~60% | Dev/Test | ✅ Standard_B2s |
| **Cluster Autoscaler** | Variable | Workloads variables | ✅ min:1, max:3 |
| **Spot Instances** | hasta 90% | Workloads tolerantes | ⬜ Opcional |
| **Reserved Instances** | hasta 72% | Workloads estables 1-3 años | ⬜ No aplica (dev) |
| **Shutdown schedules** | 100% fuera horario | Dev/Test | ✅ destroy manual |
| **Right-sizing** | 20-50% | VMs sobredimensionadas | ✅ kubectl top |

### Spot Instances (Para mencionar en entrevista)

```hcl
# En Terraform - para workloads tolerantes a interrupciones
resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  name                  = "spot"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = "Standard_D2s_v3"
  priority              = "Spot"
  eviction_policy       = "Delete"
  spot_max_price        = -1  # Precio máximo del mercado
  
  node_labels = {
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }
  
  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]
}
```

**Cuándo usar Spot:**
- Batch jobs
- CI/CD runners
- Dev/Test environments
- Workloads que pueden reiniciarse

**Cuándo NO usar Spot:**
- Bases de datos de producción
- APIs críticas para el negocio
- Workloads stateful

---

## 🎓 FinOps: Lo que preguntan en entrevista

**P: ¿Cómo gestionas costos en la nube?**
> "Aplico el ciclo FinOps: Inform, Optimize, Operate. Primero visibilidad con Cost Management y tags de allocation por equipo/proyecto. Luego optimización con right-sizing basado en métricas reales, autoscaler para elasticidad, y Reserved Instances para workloads estables. Finalmente gobierno con budgets y alertas para evitar sorpresas."

**P: ¿Cómo evitas sorpresas de facturación?**
> "Budgets con alertas al 50%, 80% y 100%. Anomaly alerts para gastos inusuales. Tags obligatorios para que todo recurso tenga dueño. Y revisión semanal de Cost Analysis para detectar tendencias."

**P: ¿Cuál es la diferencia entre Spot y Reserved Instances?**
> "Spot es capacidad sobrante de Azure con hasta 90% de descuento pero te pueden quitar la VM con 30 segundos de aviso - ideal para batch jobs o dev. Reserved es un compromiso de 1-3 años con hasta 72% de descuento - ideal para workloads predecibles de producción."

**P: ¿Cómo implementas chargeback/showback?**
> "Usando tags de Cost Allocation. Cada recurso tiene tags de CostCenter, Team y Project. Luego en Cost Analysis agrupo por tag y genero reportes mensuales que muestran cuánto gasta cada equipo. Esto crea accountability - cuando un equipo ve su factura, optimiza más."

---

## ✅ Checklist Fase 7

- [ ] Exploré Cost Analysis en el portal
- [ ] Entiendo los top 5 recursos más caros
- [ ] Creé un Budget con alertas (50%, 80%, 100%)
- [ ] Revisé Azure Advisor para recomendaciones
- [ ] Entiendo cómo funcionan los tags de Cost Allocation
- [ ] Sé explicar la diferencia entre Spot y Reserved
- [ ] Puedo hablar del ciclo FinOps (Inform, Optimize, Operate)

---

# FASE 8: TROUBLESHOOTING PRÁCTICO (1.5h)

## 🎓 El Método de Troubleshooting

```
1. OBSERVE     →  kubectl get, describe, logs, Grafana dashboards
2. ANALYZE     →  ¿Qué está mal? ¿Desde cuándo? ¿Qué cambió?
3. HYPOTHESIZE →  ¿Qué podría causar esto?
4. TEST        →  Probar la hipótesis
5. FIX         →  Aplicar la solución
6. VERIFY      →  Confirmar que funciona + documentar
```

---

## Escenario 1: Pod en CrashLoopBackOff (20 min)

### Simular el problema

```powershell
# Cambia el comando del container a algo que falla
kubectl patch deployment frontend -n voting-app --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/command", "value": ["python", "noexiste.py"]}]'

# Espera y observa
kubectl get pods -n voting-app -w
```

### Diagnosticar

```powershell
# Ver estado
kubectl get pods -n voting-app

# Ver detalles del pod
kubectl describe pod -l app=frontend -n voting-app | Select-String -Pattern "State|Reason|Message|Events" -Context 0,5

# Ver logs
kubectl logs -l app=frontend -n voting-app --previous

# Ver en Grafana: dashboard muestra restart count aumentando
```

### Resolver

```powershell
# Revertir el cambio
kubectl rollout undo deployment/frontend -n voting-app

# Verificar
kubectl rollout status deployment/frontend -n voting-app
```

---

## Escenario 2: ImagePullBackOff (20 min)

### Simular el problema

```powershell
# Cambia la imagen a una que no existe
kubectl set image deployment/frontend frontend=votingappdevacr.azurecr.io/noexiste:v999 -n voting-app

# Observa
kubectl get pods -n voting-app -w
```

### Diagnosticar

```powershell
# Ver eventos
kubectl describe pod -l app=frontend -n voting-app | Select-String -Pattern "Events" -Context 0,10

# Respuesta típica: "Failed to pull image... not found"

# Verificar qué imágenes existen en ACR
az acr repository list --name votingappdevacr
az acr repository show-tags --name votingappdevacr --repository azure-vote-front
```

### Resolver

```powershell
# Revertir a imagen correcta
kubectl rollout undo deployment/frontend -n voting-app
```

---

## Escenario 3: Service sin External IP (15 min)

### Diagnosticar

```powershell
kubectl get svc -n voting-app

# Si EXTERNAL-IP está <pending> por mucho tiempo:
kubectl describe svc frontend -n voting-app

# Buscar en Events mensajes como:
# - "Error syncing load balancer"
# - "Quota exceeded"
```

### Causas comunes

| Mensaje | Causa | Solución |
|---------|-------|----------|
| "quota exceeded" | Límite de IPs públicas | Aumentar quota o usar Ingress |
| "subnet full" | Sin IPs disponibles | Expandir subnet |
| Pending forever | NSG bloqueando | Verificar reglas NSG |

---

## Escenario 4: Aplicación lenta (20 min)

### Diagnosticar

```powershell
# Ver uso de recursos (CLI)
kubectl top pods -n voting-app
kubectl top nodes

# Ver en Grafana - buscar:
# - CPU cerca del límite
# - Memoria saturada
# - Throttling

# Si CPU cerca de límite:
kubectl describe pod -l app=frontend -n voting-app | Select-String "Limits|Requests"

# Ver HPA
kubectl get hpa -n voting-app
```

### Resolver

```powershell
# Aumentar recursos temporalmente
kubectl patch deployment frontend -n voting-app -p '{"spec":{"template":{"spec":{"containers":[{"name":"frontend","resources":{"limits":{"cpu":"1000m"}}}]}}}}'

# O forzar scaling manual
kubectl scale deployment frontend --replicas=3 -n voting-app
```

---

## Escenario 5: No conecta a Redis (15 min)

### Diagnosticar

```powershell
# Ver logs del frontend
kubectl logs -l app=frontend -n voting-app | Select-String "redis|Redis|connection"

# Verificar que Redis está corriendo
kubectl get pods -l app=redis -n voting-app

# Verificar el Service de Redis
kubectl get svc redis -n voting-app
kubectl describe svc redis -n voting-app

# Test de conectividad desde frontend
kubectl exec -it $(kubectl get pod -l app=frontend -n voting-app -o jsonpath='{.items[0].metadata.name}') -n voting-app -- python -c "import redis; r = redis.Redis('redis'); print(r.ping())"
```

### Causas comunes

| Síntoma | Causa | Solución |
|---------|-------|----------|
| Connection refused | Redis no está corriendo | Verificar deployment de Redis |
| Name resolution failed | Service no existe | Crear/verificar Service |
| Connection timeout | NetworkPolicy bloqueando | Verificar/ajustar NetworkPolicy |

---

## 📋 Comandos de Troubleshooting Esenciales

```bash
# Estado general
kubectl get all -n voting-app
kubectl get events -n voting-app --sort-by='.lastTimestamp'

# Pods problemáticos
kubectl get pods -n voting-app -o wide
kubectl describe pod <pod-name> -n voting-app
kubectl logs <pod-name> -n voting-app
kubectl logs <pod-name> -n voting-app --previous  # Si crasheó

# Recursos
kubectl top pods -n voting-app
kubectl top nodes

# Exec into pod (debug)
kubectl exec -it <pod-name> -n voting-app -- /bin/sh

# Rollback
kubectl rollout undo deployment/<name> -n voting-app
kubectl rollout history deployment/<name> -n voting-app

# Network debug
kubectl run debug --rm -it --image=busybox -n voting-app -- /bin/sh
# Dentro: nslookup redis, wget -qO- http://frontend:80/
```

---

## ✅ Checklist Fase 8

> **NOTA**: Si ya resolviste problemas reales durante la práctica, consulta [TROUBLESHOOTING_REAL.md](docs/TROUBLESHOOTING_REAL.md) - eso tiene más valor que escenarios simulados.

- [ ] Practiqué CrashLoopBackOff y sé cómo diagnosticarlo
- [ ] Practiqué ImagePullBackOff y sé la causa común
- [ ] Entiendo cómo diagnosticar problemas de Service
- [ ] Sé usar kubectl top, describe, logs, exec
- [ ] Usé Grafana para correlacionar métricas con problemas
- [ ] Puedo hacer rollback de un deployment

---

# 💡 Al Terminar Domingo

```powershell
# Destruir todo para evitar costos
cd "c:\Users\Daniel Matapi\cloud-practice\azure-voting-app-redis\terraform"
terraform destroy -auto-approve

# Eliminar recursos de monitoring manual (si creaste aparte)
az grafana delete --name votingapp-grafana --resource-group votingapp-dev-rg --yes
az monitor account delete --name votingapp-prometheus --resource-group votingapp-dev-rg --yes

# También el resource group del tfstate (opcional, si no lo usarás más)
# az group delete --name tfstate-rg --yes
```

---

# 🎤 Preguntas de Entrevista - Operations & Monitoring

## Monitoring

**P: ¿Qué stack de monitoring usas para Kubernetes?**
> "Uso un enfoque de múltiples capas: Azure Monitor para infraestructura del cluster, Prometheus para métricas de aplicación y pods, y Grafana para visualización unificada. Prometheus con PromQL me da flexibilidad para queries complejas, mientras que Azure Monitor me da integración nativa con alertas y el ecosistema Azure."

**P: ¿Por qué usar Prometheus si ya tienes Azure Monitor?**
> "Son complementarios. Azure Monitor es excelente para métricas de infraestructura y tiene integración nativa con alerting. Pero Prometheus es el estándar de facto en Kubernetes - tiene mejor granularidad para métricas de aplicación, service discovery automático, y PromQL es más poderoso para agregaciones complejas. Además, si migras a otro cloud, Prometheus es portable."

**P: ¿Cuáles son los 4 Golden Signals?**
> "Latency, Traffic, Errors, y Saturation. Son las métricas clave que todo sistema debería monitorear según Google SRE. Latency es tiempo de respuesta, Traffic es throughput, Errors es tasa de fallos, y Saturation es qué tan cerca estamos de los límites de recursos."

## Troubleshooting

**P: ¿Cómo diagnosticas un pod en CrashLoopBackOff?**
> "Primero kubectl describe pod para ver eventos y el exit code. Luego kubectl logs --previous para ver qué pasó antes del crash. También reviso Grafana donde puedo ver el restart count aumentando y correlacionar con métricas de recursos. Causas comunes: la app falla al iniciar por config incorrecta, falta una variable de entorno, o el probe falla. Puedo hacer rollback rápido con kubectl rollout undo."

**P: Un cliente reporta que la app está lenta. ¿Qué haces?**
> "Primero verifico los 4 Golden Signals en Grafana - latency, error rate, traffic. Luego kubectl top pods para ver consumo de recursos. En Grafana puedo ver si hay CPU throttling. Verifico el HPA - si está al máximo de réplicas, puede ser un problema de capacidad. También reviso latencia hacia Redis en los logs. El enfoque es siempre: observe, analyze, hypothesize, test, fix, verify."

## Cost Optimization

**P: ¿Cómo optimizas costos en AKS?**
> "Varias estrategias: B-series VMs para dev que son burstable y ~60% más baratas. Cluster autoscaler para escalar nodos basado en demanda real. Spot instances para workloads tolerantes a interrupciones - hasta 90% de ahorro. Reserved instances para workloads predecibles. Right-sizing basado en kubectl top y métricas de Prometheus. Y siempre destruir recursos dev/staging cuando no se usan - terraform destroy al final del día."

---

# 🔑 Keywords para Entrevista

## Monitoring
- Prometheus, PromQL, Service Discovery, Scraping
- Grafana, Dashboards, Alerting, Visualization
- Azure Monitor, Container Insights, Log Analytics
- KQL (Kusto Query Language)
- 4 Golden Signals (Latency, Traffic, Errors, Saturation)
- Observability (Metrics, Logs, Traces)
- Multi-tool monitoring strategy

## Cost / FinOps
- FinOps (Inform, Optimize, Operate)
- Budgets, Cost Alerts, Anomaly Detection
- Cost Allocation Tags, Showback, Chargeback
- Azure Advisor, Cost Analysis
- Spot Instances, Reserved Instances
- Right-sizing, Cluster Autoscaler
- B-series (burstable), D-series (dedicated)

## Troubleshooting
- CrashLoopBackOff, ImagePullBackOff
- kubectl describe, logs, exec, top
- Rollback, Rollout
- Root Cause Analysis (RCA)

---

# 📋 Resumen: Plan Lunes y Martes

**Lunes:**
- Leer las consolidaciones (PHASE1-5, COMPLETE_RECAP)
- Repasar las preguntas de entrevista de cada fase
- Practicar explicar Prometheus vs Azure Monitor verbalmente

**Martes:**
- Simulación de entrevista (pide a alguien que te pregunte)
- Repaso de comandos clave (terraform, docker, kubectl, promql)
- Descansar bien para el miércoles

¡Éxito en la entrevista! 🚀
