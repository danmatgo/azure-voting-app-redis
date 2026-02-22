# 📚 MASTER GUIDE PART 6: Operations, FinOps & Lecciones Aprendidas
## Fases 6-8: Domingo 1 de Febrero, 2026

> **Objetivo**: Consolidar todo lo aprendido en monitoring enterprise, FinOps, y las lecciones críticas de arquitectura cross-account.

---

# 🎯 Resumen Ejecutivo

| Fase | Completado | Componentes Clave |
|------|------------|-------------------|
| **Fase 6: Monitoring Enterprise** | ✅ | Azure Monitor, Prometheus Managed, Grafana Managed, PromQL, KQL |
| **Fase 7: FinOps** | ✅ | Cost Analysis, Budgets, Alerts, Tags, Advisor |
| **Lecciones Cross-Account** | ✅ | Patrones de autenticación, Pause vs Destroy, Context switching |

---

# 💰 FINOPS EN PROFUNDIDAD

## Budgets en Azure: Explicación Completa

### ¿Qué es un Budget?

Un presupuesto que defines para un scope (suscripción, resource group, etc.) con **alertas automáticas** cuando se acerca o supera.

```
┌─────────────────────────────────────────────────────────────┐
│                    ANATOMÍA DE UN BUDGET                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  SCOPE (dónde aplica):                                      │
│  ├── Suscripción completa                                   │
│  ├── Resource Group específico                              │
│  ├── Management Group (multi-suscripción)                   │
│  └── Recurso individual                                     │
│                                                             │
│  MONTO ($):                                                 │
│  └── El límite mensual/trimestral/anual                     │
│                                                             │
│  RESET PERIOD:                                              │
│  ├── Monthly (más común)                                    │
│  ├── Quarterly                                              │
│  └── Annually (para presupuestos anuales)                   │
│                                                             │
│  ALERTAS (% del budget):                                    │
│  ├── 50% → "Vamos a mitad, todo normal"                    │
│  ├── 80% → "Atención, revisa qué está gastando"            │
│  ├── 100% → "Llegaste al límite, actúa"                    │
│  └── 120% → "Sobrepasaste, urgente"                        │
│                                                             │
│  ACCIONES:                                                  │
│  ├── Email a admins                                         │
│  ├── Email a stakeholders/finance                           │
│  └── Action Groups (automation)                             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Crear Budget desde el Portal (Paso a Paso)

1. **Navegar**: Azure Portal → Cost Management + Billing → Cost Management → Budgets
2. **Click**: + Add
3. **Configurar**:

| Campo | Descripción | Ejemplo |
|-------|-------------|---------|
| **Name** | Nombre descriptivo | `votingapp-dev-monthly` |
| **Scope** | Dónde aplica | Resource Group: votingapp-dev-rg |
| **Reset period** | Cuándo se reinicia | Monthly |
| **Creation date** | Inicio del budget | Primer día del mes |
| **Expiration date** | Cuándo deja de aplicar | 1 año después |
| **Budget amount** | Límite mensual | $100 |

4. **Configurar Alertas**:

| Tipo | % | Recipients | Acción sugerida |
|------|---|------------|-----------------|
| Actual | 50% | tu-email@company.com | Info: vas a mitad |
| Actual | 80% | tu-email@company.com, manager@company.com | Warning: cerca del límite |
| Actual | 100% | tu-email@company.com, finance@company.com | Alert: llegaste al límite |
| Forecasted | 110% | tu-email@company.com | Predicción: vas a pasarte |

### Tipos de Alertas

```
ACTUAL vs FORECASTED:

ACTUAL (basado en gasto real):
├── Día 15 del mes: gastaste $50 de $100
├── Alerta 50%: "Has gastado la mitad del budget"
└── REACTIVO: te enteras DESPUÉS de gastar

FORECASTED (basado en predicción):
├── Día 10 del mes: gastaste $40
├── Azure predice: "Si sigues así, gastarás $120"
├── Alerta 110% forecasted: "Vas a pasarte del budget"
└── PROACTIVO: te enteras ANTES de pasarte
```

### Automatización con Action Groups

Además de emails, puedes ejecutar acciones automáticas:

```
ACTION GROUP → Qué puede hacer:

├── Email/SMS: Notificar personas
├── Azure Function: Ejecutar código
│   └── Ejemplo: Apagar VMs de dev automáticamente
├── Logic App: Workflow automation
│   └── Ejemplo: Crear ticket en ServiceNow
├── Webhook: Llamar API externa
│   └── Ejemplo: Notificar a Slack/Teams
└── ITSM: Integración con sistemas de tickets
```

**Ejemplo enterprise real**:
```
Al 100% del budget:
1. Email a todos los dueños de recursos
2. Logic App crea ticket en Jira
3. Azure Function escala down los AKS node pools a mínimo
4. Webhook notifica canal de Slack #cloud-costs
```

### Qué NO puede hacer un Budget (limitaciones)

| Limitación | Alternativa |
|------------|-------------|
| ❌ No puede **detener recursos** automáticamente | Usa Azure Automation + Action Group |
| ❌ No puede **bloquear creación** de recursos | Usa Azure Policy con cost limits |
| ❌ No tiene granularidad por hora | Es diario/mensual |
| ❌ No aplica a todos los tipos de costo | Algunos costos (Support, Reservations) no se incluyen |

---

## Cost Alerts vs Budget Alerts

```
┌─────────────────────────────────────────────────────────────┐
│            TIPOS DE ALERTAS DE COSTO                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  BUDGET ALERTS (lo que acabamos de ver):                    │
│  └── "Llegaste al X% de tu presupuesto mensual"            │
│                                                             │
│  ANOMALY ALERTS:                                            │
│  └── "Gasto inusual detectado" (ML-based)                  │
│      Ejemplo: normalmente gastas $5/día                     │
│               hoy gastaste $50 → ALERTA                     │
│                                                             │
│  CREDIT ALERTS (para Enterprise Agreements):                │
│  └── "Tu crédito Azure está por agotarse"                  │
│                                                             │
│  DEPARTMENT ALERTS (para organizaciones):                   │
│  └── "El departamento X superó su quota"                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

# 🔐 LECCIONES CRÍTICAS: ARQUITECTURA CROSS-ACCOUNT

## El Problema: 3 Horas Recreando Infraestructura

### ¿Qué pasó?

```
TIMELINE DEL PROBLEMA:

Viernes (setup inicial):
├── Creamos App Registration + OIDC en cuenta personal
├── Creamos ACR en cuenta personal
├── Creamos AKS en cuenta trabajo
├── Todo funcionando ✅
└── terraform destroy en ambas cuentas

Domingo (recreación):
├── Terraform apply... pero ¿con qué cuenta?
├── az login... cuenta personal
├── Terraform apply... error: AKS en otra cuenta
├── az logout; az login... cuenta trabajo
├── Terraform apply... pero ACR está en otra cuenta
├── Error de permisos OIDC... necesito cuenta personal
├── az logout; az login... (loop infinito)
├── 50+ logins durante 3 horas 😩
└── Finalmente funciona... agotados
```

### El Anti-Patrón (lo que hicimos mal)

```
┌─────────────────────────────────────────────────────────────┐
│              ❌ ANTI-PATRÓN: DESTRUIR TODO                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  DESTROY al terminar el día:                                │
│  ├── terraform destroy (cuenta trabajo)                    │
│  ├── terraform destroy (cuenta personal)                   │
│  └── Todos los recursos eliminados                         │
│                                                             │
│  PROBLEMAS:                                                 │
│  ├── Recrear toma tiempo (provisioning)                    │
│  ├── Re-configurar OIDC/federation                         │
│  ├── Re-establecer role assignments                        │
│  ├── Re-generar kubeconfig                                 │
│  └── Context switching entre cuentas = errores             │
│                                                             │
│  COSTO DE RECREAR:                                          │
│  ├── 3 horas de tiempo perdido                             │
│  ├── Frustración y errores                                 │
│  └── El costo del tiempo > costo de Azure                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### El Patrón Correcto: Pause vs Destroy

```
┌─────────────────────────────────────────────────────────────┐
│              ✅ PATRÓN: PAUSE SMART, DESTROY SMART          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  RECURSOS CAROS (VMs/AKS):                                  │
│  └── PAUSAR, no destruir                                   │
│      az aks stop --name votingapp-dev-aks --resource-group  │
│      Costo cuando pausado: ~$0 (solo storage mínimo)        │
│                                                             │
│  RECURSOS BARATOS (ACR, Storage, Log Analytics):            │
│  └── DEJAR ACTIVOS                                          │
│      Costo: $5-10/mes - no vale la pena destruir           │
│                                                             │
│  CUÁNDO SÍ DESTRUIR:                                        │
│  ├── Fin del proyecto (completamente)                       │
│  ├── Trial expira                                           │
│  └── Cambio de arquitectura fundamental                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Comandos para Pause vs Destroy

```powershell
# ✅ PAUSAR AKS (recursos caros)
az aks stop --name votingapp-dev-aks --resource-group votingapp-dev-rg
# Costo: ~$0 mientras pausado

# ✅ RESUMIR AKS (cuando vuelvas a trabajar)
az aks start --name votingapp-dev-aks --resource-group votingapp-dev-rg
# Toma ~5 minutos vs 20+ minutos de terraform apply

# ❌ NO DESTRUIR a menos que sea final de proyecto
# terraform destroy  <- evitar si vas a volver mañana
```

### Decision Tree: ¿Pausar o Destruir?

```
¿Voy a usar esto mañana/esta semana?
├── SÍ → PAUSAR (az aks stop)
│        Costo: ~$0, tiempo de resume: 5 min
│
└── NO → ¿Es un trial/lab temporal?
         ├── SÍ → DESTRUIR (terraform destroy)
         │        Liberar recursos del trial
         │
         └── NO → ¿Cuánto cuesta mantenerlo?
                  ├── <$20/mes → DEJAR (no vale el esfuerzo)
                  └── >$100/mes → DESTRUIR (con documentación)
```

---

## Context Switching: El Problema de Multi-Account

### ¿Por qué tantos logins?

```
EL PROBLEMA DE UNA SOLA TERMINAL:

Terminal 1:
├── az login → cuenta personal
├── terraform apply → crea ACR ✅
├── Necesito kubectl → pero AKS está en cuenta trabajo
├── az logout; az login → cuenta trabajo
├── kubectl get nodes ✅
├── Necesito verificar ACR → pero ahora estoy en cuenta trabajo
├── az logout; az login → cuenta personal
├── ... y así 50 veces 😩
```

### El Patrón Correcto: Múltiples Sesiones

```
✅ PATRÓN: DOS TERMINALES, DOS CUENTAS

Terminal 1 (Personal - ACR/OIDC):              Terminal 2 (Trabajo - AKS):
├── az login (cuenta personal)                  ├── az login (cuenta trabajo)
├── az account show → personal ✅               ├── az account show → trabajo ✅
├── Trabajo con ACR, App Registration           ├── Trabajo con AKS, kubectl
└── NUNCA hacer logout                          └── NUNCA hacer logout

BENEFICIOS:
├── Sin confusion de contexto
├── Sin re-autenticación
├── Cada terminal tiene su identidad clara
└── Productividad: 30 min vs 3 horas
```

### Cómo Implementar Múltiples Sesiones

**Opción 1: Múltiples terminales PowerShell**
```powershell
# Terminal 1 - Cuenta Personal
$env:AZURE_CONFIG_DIR = "C:\Users\Daniel\.azure-personal"
az login # cuenta personal
# Esta terminal SIEMPRE es cuenta personal

# Terminal 2 - Cuenta Trabajo  
$env:AZURE_CONFIG_DIR = "C:\Users\Daniel\.azure-work"
az login # cuenta trabajo
# Esta terminal SIEMPRE es cuenta trabajo
```

**Opción 2: Usar --subscription explícito**
```powershell
# Siempre especificar la suscripción
az acr list --subscription "Personal-Subscription-ID"
az aks list --subscription "Work-Subscription-ID"
```

**Opción 3: Service Principals (producción)**
```powershell
# Para cada cuenta, crear SP y autenticar sin interacción
az login --service-principal -u $SP_PERSONAL -p $SECRET --tenant $TENANT_PERSONAL
az login --service-principal -u $SP_WORK -p $SECRET --tenant $TENANT_WORK
```

---

## Lección para Entrevista

**P: "¿Has trabajado con arquitecturas multi-cuenta/multi-tenant?"**

> "Sí, implementé un pipeline CI/CD donde el container registry estaba en una suscripción y el cluster AKS en otra, debido a restricciones de permisos de Entra ID en la cuenta corporativa. 
>
> Aprendí que el manejo de contexto es crítico - mantener sesiones separadas por cuenta evita errores y re-autenticaciones constantes. También aprendí que para workloads de desarrollo, es más eficiente pausar recursos costosos (az aks stop) que destruirlos completamente, porque el tiempo de recreación puede ser mayor que el costo de mantenerlos pausados.
>
> En producción usaría Service Principals con permisos cross-tenant o Azure Lighthouse para gestión centralizada."

---

# 📊 MONITORING ENTERPRISE: PROMETHEUS + GRAFANA

## Stack Implementado

```
┌─────────────────────────────────────────────────────────────┐
│              OBSERVABILITY STACK COMPLETO                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  CAPA 1: Infraestructura (Azure Nativo)                     │
│  ├── Container Insights → Métricas de nodos/pods           │
│  ├── Log Analytics → Logs centralizados (KQL)              │
│  └── Azure Monitor → Alertas y dashboards Azure            │
│                                                             │
│  CAPA 2: Aplicación (Prometheus)                            │
│  ├── Azure Managed Prometheus                               │
│  ├── PromQL para queries                                    │
│  └── Recording rules para agregaciones                      │
│                                                             │
│  CAPA 3: Visualización (Grafana)                            │
│  ├── Azure Managed Grafana                                  │
│  ├── Dashboards unificados                                  │
│  └── Multi-datasource (Prometheus + Azure Monitor)         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Cuándo usar cada herramienta

| Pregunta | Herramienta | Razón |
|----------|-------------|-------|
| ¿Cuánta CPU usa mi nodo? | Azure Monitor | Métrica de infraestructura |
| ¿Cuántas requests/segundo? | Prometheus | Métrica de aplicación |
| ¿Por qué crasheó el pod? | Log Analytics + KQL | Análisis de logs |
| ¿Dashboard para el CTO? | Grafana | Visualización bonita |
| ¿Alerta cuando hay error? | Grafana o Azure Monitor | Ambos funcionan |

## Queries Esenciales

### PromQL (Prometheus)
```promql
# CPU por pod
rate(container_cpu_usage_seconds_total{namespace="voting-app"}[5m])

# Memoria en MB
container_memory_working_set_bytes{namespace="voting-app"} / 1024 / 1024

# Restarts (indica problemas)
kube_pod_container_status_restarts_total{namespace="voting-app"}
```

### KQL (Log Analytics)
```kusto
// Logs del frontend última hora
ContainerLogV2
| where ContainerName == "frontend"
| where TimeGenerated > ago(1h)
| project TimeGenerated, LogMessage

// Errores
ContainerLogV2
| where LogMessage contains "error"
| summarize count() by bin(TimeGenerated, 5m)
```

---

# 🎯 PATRONES vs ANTI-PATRONES ENTERPRISE

## Infraestructura (Terraform)

| ❌ Anti-Patrón | ✅ Patrón Correcto | Por qué importa |
|----------------|-------------------|-----------------|
| State local en laptop | Remote backend (Azure Storage) | Colaboración, locking, no perderlo |
| Hardcodear valores | tfvars por ambiente | Mismo código, múltiples ambientes |
| Un solo state gigante | Separar por componente/ambiente | Blast radius limitado |
| `terraform destroy` diario | `az aks stop` para dev | Tiempo > costo |
| Copiar código entre ambientes | Modules reutilizables | DRY, menos bugs |

## Contenedores (Docker)

| ❌ Anti-Patrón | ✅ Patrón Correcto | Por qué importa |
|----------------|-------------------|-----------------|
| Imagen base `latest` | Tag específico (python:3.9-slim) | Reproducibilidad |
| Un solo stage | Multi-stage build | Imagen final más pequeña y segura |
| Sin .dockerignore | .dockerignore estricto | Build más rápido, sin leaks |
| Root user en container | USER non-root | Seguridad |
| Secretos en Dockerfile | Secretos en runtime (env vars) | No exponer en imagen |

## Kubernetes

| ❌ Anti-Patrón | ✅ Patrón Correcto | Por qué importa |
|----------------|-------------------|-----------------|
| Solo Deployment sin HPA | HPA + resource limits | Autoscaling, predictibilidad |
| Sin PodDisruptionBudget | PDB definido | Disponibilidad durante upgrades |
| NetworkPolicy permisiva | Deny-by-default | Seguridad, least privilege |
| Manifests duplicados | Kustomize base/overlays | Mantenibilidad |
| Sin health checks | Liveness + Readiness probes | Self-healing, rolling updates |

## CI/CD

| ❌ Anti-Patrón | ✅ Patrón Correcto | Por qué importa |
|----------------|-------------------|-----------------|
| Secretos hardcodeados | GitHub Secrets + OIDC | Rotación, no expuestos |
| Build sin scan de seguridad | Trivy en pipeline | Vulnerabilidades antes de deploy |
| Deploy manual | GitOps / Pipeline automatizado | Consistencia, auditoría |
| Branch `main` sin protección | Branch protection + PR | Review, quality gates |
| Sin tests | Tests + security gates | Confianza en deploys |

## Monitoring & Operations

| ❌ Anti-Patrón | ✅ Patrón Correcto | Por qué importa |
|----------------|-------------------|-----------------|
| Solo métricas básicas | 4 Golden Signals (Latency, Traffic, Errors, Saturation) | SRE best practice |
| Sin alertas | Alertas escalonadas (warning → critical) | Tiempo de respuesta |
| Una sola herramienta | Stack completo (Prometheus + Grafana + Logs) | Diferentes necesidades |
| Logs en container | Logs centralizados (Log Analytics) | Debugging post-mortem |
| Sin budgets | Budgets con alertas | Control de costos |

## Multi-Tenant / Multi-Account

| ❌ Anti-Patrón | ✅ Patrón Correcto | Por qué importa |
|----------------|-------------------|-----------------|
| Una terminal, múltiples logins | Terminal por cuenta (AZURE_CONFIG_DIR) | Sin confusión |
| az logout/login constantemente | Sesiones separadas persistentes | Productividad |
| Mismos permisos everywhere | Least privilege por suscripción | Seguridad |
| Sin documentar qué cuenta para qué | Runbook documentado | Onboarding, disaster recovery |

---

# 🏆 ANTI-PATRONES EN LOS QUE CAÍSTE (para mencionar en entrevista)

> **Tip**: En entrevistas, admitir errores y explicar cómo los solucionaste demuestra madurez y experiencia real.

## 1. "Destruí todo pensando ahorrar dinero"

**Lo que hice mal**: `terraform destroy` en ambas cuentas al terminar el viernes.

**Consecuencia**: 3 horas recreando el domingo, más costoso que haberlo dejado pausado.

**Lección**: "Aprendí que el costo del tiempo de ingeniería supera el costo de recursos pausados. Ahora uso `az aks stop` para dev y solo destruyo cuando es fin de proyecto."

## 2. "Una terminal para todo"

**Lo que hice mal**: Hacer `az logout; az login` 50+ veces entre cuentas.

**Consecuencia**: Errores constantes de contexto, confusión, frustración.

**Lección**: "Ahora uso terminales separadas con `AZURE_CONFIG_DIR` diferente para cada cuenta. En producción usaría Service Principals."

## 3. "Trivy bloqueando pipeline por CVEs sin fix"

**Lo que hice mal**: Configurar Trivy con `exit-code: 1` para todas las vulnerabilidades.

**Consecuencia**: Pipeline bloqueado por CVE en imagen base sin parche disponible.

**Lección**: "Ahora uso `ignore-unfixed: true` y tengo un proceso de aceptación de riesgo documentado. Para CVEs críticos con fix, sí bloqueo."

## 4. "Workflow para branch incorrecto"

**Lo que hice mal**: Copiar template de GitHub Actions sin verificar el branch default.

**Consecuencia**: Pipeline no se ejecutaba, sin errores visibles.

**Lección**: "Siempre verifico el branch default del repo antes de configurar triggers. También uso workflow_dispatch para testing manual."

---

# 💡 COSAS QUE QUIZÁS OLVIDAMOS

## ✅ Lo que SÍ tienes implementado:
- [x] Terraform con remote backend y tfvars
- [x] Docker multi-stage con .dockerignore
- [x] Kubernetes con HPA, PDB, NetworkPolicy
- [x] CI/CD con OIDC y Trivy
- [x] Dependabot + CodeQL
- [x] Prometheus + Grafana managed
- [x] Budgets configurados

## ⚠️ Cosas adicionales para mencionar en entrevista (aunque no las implementaste completamente):

| Concepto | Qué decir |
|----------|-----------|
| **Helm** | "Usé Kustomize para este proyecto, pero también trabajo con Helm para charts más complejos. La diferencia es que Helm usa templating y tiene releases, mientras Kustomize es patching declarativo." |
| **ArgoCD/Flux** | "Para GitOps más avanzado usaría ArgoCD o Flux. En este proyecto el deploy es push-based desde GitHub Actions, pero el patrón pull-based de ArgoCD es mejor para producción." |
| **Service Mesh** | "Para observability avanzada y mTLS agregaría Istio o Linkerd. En este proyecto usé NetworkPolicies básicas, pero un service mesh da más control de tráfico." |
| **Vault/External Secrets** | "Los secretos están en GitHub Secrets, pero en producción usaría HashiCorp Vault o Azure Key Vault con External Secrets Operator para rotación automática." |

---

# 📅 Resumen del Proyecto Completo

## Lo que construiste en 3 días:

| Día | Fases | Logros |
|-----|-------|--------|
| **Viernes** | 1-3 | Terraform, Docker, Kubernetes, Kustomize |
| **Sábado** | 4-5 | CI/CD, OIDC, Trivy, Dependabot, CodeQL, Network Policies |
| **Domingo** | 6-8 | Prometheus, Grafana, FinOps, Cross-account lessons |

## Arquitectura Final:

```
┌─────────────────────────────────────────────────────────────┐
│                 ARQUITECTURA VOTINGAPP                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  CUENTA PERSONAL:                   CUENTA TRABAJO:          │
│  ├── App Registration (OIDC)        ├── Resource Group      │
│  ├── ACR (container images)         ├── AKS Cluster         │
│  └── Prometheus Workspace           ├── Log Analytics       │
│                                     └── Grafana             │
│                                                             │
│  GITHUB:                                                     │
│  ├── CI/CD Pipeline                                         │
│  │   ├── Build: OIDC → ACR (push)                          │
│  │   └── Deploy: kubeconfig → AKS                          │
│  ├── Trivy (container scan)                                 │
│  ├── CodeQL (code scan)                                     │
│  └── Dependabot (dependencies)                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Skills demostrados (para entrevista):

1. **Infrastructure as Code**: Terraform con modules, tfvars, remote backend
2. **Containers**: Docker multi-stage, .dockerignore, registry
3. **Kubernetes**: Deployments, Services, HPA, PDB, Kustomize, Network Policies
4. **CI/CD**: GitHub Actions, OIDC, cross-account deployment
5. **Security**: Trivy, CodeQL, Dependabot, secrets management
6. **Monitoring**: Prometheus, Grafana, Azure Monitor, alerting
7. **FinOps**: Budgets, cost allocation, optimization strategies
8. **Troubleshooting**: Real-world problem solving, multi-tenant challenges
