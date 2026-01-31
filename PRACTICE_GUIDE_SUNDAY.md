# 🚀 Guía Práctica Domingo
## Fases 6-8: Monitoring, Cost Optimization & Troubleshooting

> **Tiempo estimado**: ~4 horas
> **Objetivo**: Operaciones del día a día y skills de troubleshooting

---

# 📋 Agenda del Día

| Tiempo | Fase | Tema |
|--------|------|------|
| 30min | Prep | Recrear infraestructura |
| 1.5h | 6 | Monitoring y Alerts |
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

# FASE 6: MONITORING Y ALERTS (1.5h)

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

### Qué ya tienes configurado

Tu AKS ya tiene **Container Insights** habilitado (lo configuraste en Terraform con `oms_agent`).

```
AKS ──métricas──▶ Log Analytics Workspace ──▶ Azure Monitor
                                              ├── Dashboards
                                              ├── Alerts
                                              └── Workbooks
```

---

## Paso 6.1: Ver Métricas en Azure Portal

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

## Paso 6.2: Crear Alerta de CPU Alta

```powershell
# Variables
$RG = "votingapp-dev-rg"
$AKS = "votingapp-dev-aks"
$WORKSPACE_ID = az aks show --resource-group $RG --name $AKS --query "addonProfiles.omsagent.config.logAnalyticsWorkspaceResourceID" -o tsv
$WORKSPACE_NAME = az monitor log-analytics workspace show --ids $WORKSPACE_ID --query name -o tsv

# Crear Action Group (a dónde se envían las alertas)
az monitor action-group create `
    --name "votingapp-alerts" `
    --resource-group $RG `
    --short-name "voting" `
    --action email admin TU_EMAIL@example.com

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

Write-Host "Alerta creada!"
```

---

## Paso 6.3: Query de Logs (Kusto/KQL)

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

## Paso 6.4: Crear Dashboard Personalizado

En Azure Portal:
1. Ve a **Dashboard** → **New dashboard**
2. Nombre: "VotingApp Monitoring"
3. Agrega tiles:
   - Métricas de AKS (CPU, Memory)
   - Logs recientes
   - Estado de pods

O usa CLI para crear metric chart:

```powershell
# Ver métricas disponibles
az monitor metrics list-definitions --resource $(az aks show -g votingapp-dev-rg -n votingapp-dev-aks --query id -o tsv) --query "[].name.value" -o tsv
```

---

## ✅ Checklist Fase 6

- [ ] Exploré Container Insights en el portal
- [ ] Creé Action Group para alertas
- [ ] Creé alerta de CPU alta
- [ ] Ejecuté queries KQL básicas
- [ ] Entiendo los 4 Golden Signals

---

# FASE 7: COST OPTIMIZATION (30 min)

## 🎓 Conceptos Clave

### Dónde se gasta dinero en AKS

```
┌─────────────────────────────────────────────────────────────┐
│                    COSTOS AKS                               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  GRATIS:                                                    │
│  ├── Control plane (AKS)                                    │
│  └── Kubernetes API                                         │
│                                                             │
│  PAGADO:                                                    │
│  ├── VMs de los nodos ($$$) ← 70-80% del costo             │
│  ├── Storage (discos, PVC)                                  │
│  ├── Networking (Load Balancer, egress)                     │
│  ├── Container Registry (ACR)                               │
│  └── Log Analytics (ingestion por GB)                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Paso 7.1: Analizar Costos Actuales

```powershell
# Ver el costo del Resource Group este mes
az consumption usage list `
    --start-date (Get-Date).AddDays(-30).ToString("yyyy-MM-dd") `
    --end-date (Get-Date).ToString("yyyy-MM-dd") `
    --query "[?contains(instanceName, 'votingapp')].{Name:instanceName, Cost:pretaxCost}" `
    --output table
```

---

## Paso 7.2: Optimizaciones que ya aplicaste

| Optimización | Implementado | Ahorro |
|--------------|--------------|--------|
| B-series VMs (burstable) | ✅ Standard_B2s | ~60% vs D-series |
| Cluster autoscaler | ✅ min:1, max:3 | Solo escala cuando necesario |
| ACR Basic tier | ✅ | ~80% vs Premium |
| Destroy cuando no usas | ✅ | 100% fuera de horario |

---

## Paso 7.3: Optimizaciones adicionales (para mencionar en entrevista)

### Spot Instances (hasta 90% ahorro)

```hcl
# En Terraform, para workloads tolerantes a interrupciones
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

### Reserved Instances (hasta 72% ahorro)

Para workloads predecibles, comprar reserva de 1-3 años.

### Right-sizing

```powershell
# Ver uso real de recursos
kubectl top pods -n voting-app

# Si un pod usa 50m CPU pero tiene limit de 500m,
# reduce el limit para permitir más pods por nodo
```

---

## ✅ Checklist Fase 7

- [ ] Entiendo dónde está el costo en AKS
- [ ] Sé explicar B-series vs D-series
- [ ] Puedo mencionar Spot Instances y Reserved
- [ ] Entiendo cluster autoscaler

---

# FASE 8: TROUBLESHOOTING PRÁCTICO (1.5h)

## 🎓 El Método de Troubleshooting

```
1. OBSERVE     →  kubectl get, describe, logs
2. ANALYZE     →  ¿Qué está mal? ¿Desde cuándo?
3. HYPOTHESIZE →  ¿Qué podría causar esto?
4. TEST        →  Probar la hipótesis
5. FIX         →  Aplicar la solución
6. VERIFY      →  Confirmar que funciona
```

---

## Escenario 1: Pod en CrashLoopBackOff (20 min)

### Simular el problema

```powershell
# Cambia el comando del container a algo que falla
kubectl patch deployment dev-frontend -n voting-app --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/command", "value": ["python", "noexiste.py"]}]'

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
```

### Resolver

```powershell
# Revertir el cambio
kubectl rollout undo deployment/dev-frontend -n voting-app

# Verificar
kubectl rollout status deployment/dev-frontend -n voting-app
```

---

## Escenario 2: ImagePullBackOff (20 min)

### Simular el problema

```powershell
# Cambia la imagen a una que no existe
kubectl set image deployment/dev-frontend frontend=votingappdevacr.azurecr.io/noexiste:v999 -n voting-app

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
kubectl rollout undo deployment/dev-frontend -n voting-app
```

---

## Escenario 3: Service sin External IP (15 min)

### Diagnosticar

```powershell
kubectl get svc -n voting-app

# Si EXTERNAL-IP está <pending> por mucho tiempo:
kubectl describe svc dev-frontend -n voting-app

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
# Ver uso de recursos
kubectl top pods -n voting-app
kubectl top nodes

# Si CPU cerca de límite:
kubectl describe pod -l app=frontend -n voting-app | Select-String "Limits|Requests"

# Ver si hay throttling
kubectl describe pod -l app=frontend -n voting-app | Select-String "cpu throttl"

# Ver HPA
kubectl get hpa -n voting-app
```

### Resolver

```powershell
# Aumentar recursos temporalmente
kubectl patch deployment dev-frontend -n voting-app -p '{"spec":{"template":{"spec":{"containers":[{"name":"frontend","resources":{"limits":{"cpu":"1000m"}}}]}}}}'

# O forzar scaling manual
kubectl scale deployment dev-frontend --replicas=3 -n voting-app
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

- [ ] Practiqué CrashLoopBackOff y sé cómo diagnosticarlo
- [ ] Practiqué ImagePullBackOff y sé la causa común
- [ ] Entiendo cómo diagnosticar problemas de Service
- [ ] Sé usar kubectl top, describe, logs, exec
- [ ] Puedo hacer rollback de un deployment

---

# 💡 Al Terminar Domingo

```powershell
cd "c:\Users\Daniel Matapi\cloud-practice\azure-voting-app-redis\terraform"
terraform destroy -auto-approve

# También el resource group del tfstate (opcional, si no lo usarás más)
az group delete --name tfstate-rg --yes
```

---

# 🎤 Preguntas de Entrevista - Operations

**P: ¿Cuáles son los 4 Golden Signals?**
> "Latency, Traffic, Errors, y Saturation. Son las métricas clave que todo sistema debería monitorear según Google SRE. Latency es tiempo de respuesta, Traffic es throughput, Errors es tasa de fallos, y Saturation es qué tan cerca estamos de los límites de recursos."

**P: ¿Cómo diagnosticas un pod en CrashLoopBackOff?**
> "Primero kubectl describe pod para ver eventos y el exit code. Luego kubectl logs --previous para ver qué pasó antes del crash. Causas comunes: la app falla al iniciar por config incorrecta, falta una variable de entorno requerida, o el probe falla. Puedo hacer rollback con kubectl rollout undo si es urgente."

**P: ¿Cómo optimizas costos en AKS?**
> "Varias estrategias: usar B-series VMs para dev que son burstable y más baratas. Cluster autoscaler para escalar nodos basado en demanda. Spot instances para workloads tolerantes a interrupciones. Reserved instances para workloads predecibles. Right-sizing basado en kubectl top. Y siempre destruir recursos dev/staging cuando no se usan."

**P: Un cliente reporta que la app está lenta. ¿Qué haces?**
> "Primero verifico los 4 Golden Signals en el dashboard. Luego kubectl top pods para ver consumo de recursos. Si hay throttling de CPU, considero aumentar limits o escalar réplicas. Verifico el HPA - si está al máximo de réplicas, puede ser un problema de capacidad del cluster. También reviso latencia hacia dependencias como la base de datos."

---

# 📋 Resumen: Plan Lunes y Martes

**Lunes:**
- Leer las 4 consolidaciones (PHASE1, PHASE2, PHASE3, COMPLETE_RECAP)
- Repasar las preguntas de entrevista de cada fase
- Practicar explicar verbalmente cada concepto

**Martes:**
- Simulación de entrevista (pide a alguien que te pregunte o usa las preguntas)
- Repaso de comandos clave (terraform, docker, kubectl)
- Descansar bien para el miércoles

¡Éxito en la entrevista! 🚀
