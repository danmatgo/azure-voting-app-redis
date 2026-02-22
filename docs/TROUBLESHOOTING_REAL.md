# 🔧 Troubleshooting Real: Problemas Resueltos en Práctica

> **Contexto**: Este documento captura problemas REALES que surgieron durante la implementación del proyecto VotingApp.
> **Valor para entrevista**: "Cuéntame un problema que hayas tenido y cómo lo resolviste"

---

## Problema 1: OIDC Federated Credential - Sin permisos en Entra ID

### 📋 Síntomas
```
az ad app create --display-name "github-actions-votingapp"
ERROR: Insufficient privileges to complete the operation.
```

### 🔍 Diagnóstico
- La cuenta de trabajo (estebanmatapi@exsis.com.co) no tiene rol "Application Developer" ni "Global Admin" en Azure AD/Entra ID
- No podemos crear App Registrations ni Federated Credentials

### ✅ Solución
**Arquitectura Cross-Account:**
1. Crear cuenta Azure personal con trial (macapixes1@hotmail.com) → Global Admin
2. En cuenta personal: crear App Registration + OIDC + ACR
3. En cuenta trabajo: mantener AKS
4. GitHub Actions: 
   - Job BUILD usa OIDC → cuenta personal → ACR
   - Job DEPLOY usa kubeconfig secret → cuenta trabajo → AKS

### 🎯 Para entrevista
> "Tuve un escenario donde no tenía permisos de Entra ID en la cuenta corporativa para crear federated credentials. Implementé una arquitectura cross-account: OIDC para el registry en una suscripción, y kubeconfig como secret para el cluster en otra. Esto es común en empresas con separación de responsabilidades entre equipos."

---

## Problema 2: Trivy bloqueando pipeline por CVEs sin fix

### 📋 Síntomas
```
CRITICAL: libssl3 CVE-2024-XXXX (debian:bookworm)
Pipeline: FAILED ❌
```

### 🔍 Diagnóstico
- La imagen base de Debian tiene vulnerabilidades en OpenSSL
- No hay parche disponible aún (unfixed)
- Pipeline configurado con `exit-code: '1'` falla obligatoriamente

### ✅ Solución
```yaml
- name: Trivy vulnerability scan
  uses: aquasecurity/trivy-action@master
  with:
    exit-code: '0'          # Solo reportar, no bloquear
    severity: 'CRITICAL,HIGH'
    ignore-unfixed: true    # Ignorar CVEs sin fix disponible
```

### 🎯 Para entrevista
> "Trivy detectó una vulnerabilidad crítica en OpenSSL de la imagen base Debian que no tenía fix disponible. Configuré el scanner para reportar pero no bloquear, documentando el riesgo aceptado. En un caso real, también evaluaría cambiar a una imagen base más segura como Alpine o Distroless."

---

## Problema 3: GitHub Actions workflow no se ejecutaba

### 📋 Síntomas
- Push a `master` no disparaba el workflow
- Ni errores, simplemente no corría

### 🔍 Diagnóstico
- Workflow configurado para branch `main`
- Repositorio usa branch `master`

### ✅ Solución
```yaml
# Antes (incorrecto)
on:
  push:
    branches: [main]

# Después (correcto)
on:
  push:
    branches: [master]
```

### 🎯 Para entrevista
> "El pipeline no se ejecutaba por una discrepancia entre el branch configurado y el real. Parece trivial pero es un error común cuando copias templates. Ahora siempre verifico el branch default del repo antes de configurar triggers."

---

## Problema 4: Deploy a AKS desde otra suscripción

### 📋 Síntomas
- No podemos usar OIDC para autenticar al AKS
- El cluster está en tenant diferente al de la App Registration

### 🔍 Diagnóstico
- OIDC requiere que App Registration y recurso estén en el mismo tenant
- AKS está en cuenta de trabajo, OIDC está en cuenta personal

### ✅ Solución
**Exportar kubeconfig como secret:**
```powershell
# Obtener kubeconfig
az aks get-credentials --name votingapp-dev-aks --file ./kubeconfig-temp

# Convertir a base64
$KUBECONFIG_B64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes("./kubeconfig-temp"))

# Guardar en GitHub Secrets como KUBE_CONFIG
```

**En workflow:**
```yaml
- name: Setup Kubeconfig
  run: |
    mkdir -p $HOME/.kube
    echo "${{ secrets.KUBE_CONFIG }}" | base64 -d > $HOME/.kube/config
    chmod 600 $HOME/.kube/config
```

### 🎯 Para entrevista
> "Implementé autenticación híbrida: OIDC para el registry que tenía integración nativa, y kubeconfig como secret para el cluster en otra suscripción. La alternativa enterprise sería Azure Lighthouse para cross-tenant management o un service principal con permisos cross-tenant."

---

## Problema 5: `kustomize edit set image` no encontraba la imagen

### 📋 Síntomas
```
error: no image with name found
```

### 🔍 Diagnóstico
- El nombre de imagen en kustomization.yaml no coincidía exactamente
- Kustomize requiere match exacto del prefijo de imagen

### ✅ Solución
```bash
# Usar el nombre COMPLETO como aparece en kustomization.yaml
kustomize edit set image votingappdevacr.azurecr.io/azure-vote-front=votingappdevacr.azurecr.io/azure-vote-front:abc1234
```

### 🎯 Para entrevista
> "Kustomize es estricto con el matching de nombres de imagen. El error 'no image found' usualmente significa que el prefijo no coincide exactamente con lo que está en el kustomization.yaml."

---

## Problema 6: Recreación de infraestructura cross-account (3 horas perdidas)

### 📋 Síntomas
- Recrear toda la infraestructura tomó 3+ horas
- 50+ re-autenticaciones entre cuentas
- Confusión constante sobre qué cuenta usar para qué
- Errores de permisos intermitentes

### 🔍 Causa raíz profunda

**Anti-patrón 1: Destruir todo en ambas cuentas**
```
VIERNES (lo que hicimos):
├── terraform destroy en cuenta trabajo
├── terraform destroy en cuenta personal  
├── Eliminar App Registration
└── "Mañana lo recreo desde cero"

DOMINGO (las consecuencias):
├── 20 min: terraform apply (crear AKS)
├── 30 min: crear App Registration de nuevo
├── 30 min: configurar Federated Credentials
├── 20 min: asignar roles ACR
├── 30 min: regenerar kubeconfig
├── 60 min: debug de errores de contexto
└── TOTAL: 3+ horas 😩
```

**Anti-patrón 2: Una sola terminal para dos cuentas**
```
CICLO VICIOSO:
az login → cuenta personal
terraform apply → "error: AKS subscription not found"
az logout; az login → cuenta trabajo
terraform apply → "error: ACR permission denied"
az logout; az login → cuenta personal
... REPETIR 50 VECES ...
```

### ✅ Patrón correcto: Pause + Multi-sesión

**Patrón 1: PAUSAR en lugar de destruir**
```powershell
# FIN DEL DÍA - PAUSAR (costo ~$0 mientras duermes)
az aks stop --name votingapp-dev-aks --resource-group votingapp-dev-rg

# INICIO DEL DÍA - RESUMIR (5 minutos)
az aks start --name votingapp-dev-aks --resource-group votingapp-dev-rg
```

**Patrón 2: MÚLTIPLES TERMINALES**
```
TERMINAL 1 (Personal):        TERMINAL 2 (Trabajo):
$env:AZURE_CONFIG_DIR =       $env:AZURE_CONFIG_DIR = 
  ".azure-personal"             ".azure-work"
az login                      az login
# NUNCA logout                # NUNCA logout
# Trabajo con ACR/OIDC        # Trabajo con AKS/kubectl
```

### 📊 Comparación de tiempo

| Escenario | Tiempo Setup | Tiempo Resume |
|-----------|-------------|---------------|
| Destruir todo + recrear | 3+ horas | N/A |
| Pausar AKS + resumir | N/A | 5-10 minutos |
| Pausar + multi-terminal | N/A | 5 minutos |

### 🧠 Decision Tree para el futuro

```
¿Termino por hoy o por el fin de semana?
│
├── VOY A VOLVER EN 1-3 DÍAS:
│   └── PAUSAR (az aks stop)
│       └── Costo: ~$0
│       └── Resume: 5 min
│
├── NO VUELVO EN 2+ SEMANAS:
│   └── ¿Cuánto cuesta mantener pausado?
│       ├── <$10/mes → DEJAR PAUSADO
│       └── >$50/mes → DESTRUIR (y documentar recreación)
│
└── ES FIN DEL PROYECTO:
    └── DESTRUIR TODO
        └── Documentar el proceso de setup completo
```

### 💡 Lección clave

**El costo de tu tiempo > el costo de Azure pausado**

Mantener AKS pausado: ~$0/día
Recrear toda la arquitectura cross-account: 3 horas de tiempo

A $50/hora (rate conservador), esas 3 horas = $150
Podrías haber dejado todo corriendo 1-2 meses por ese costo.

### 🎯 Para entrevista

> "Aprendí que en arquitecturas multi-cuenta, pausar recursos costosos (como AKS con az aks stop) es más eficiente que destruirlos si vas a volver en días. Destruí todo pensando ahorrar, pero la recreación tomó 3 horas entre configurar OIDC, crear permisos cross-tenant, y el context switching entre cuentas. Ahora uso terminales separadas por cuenta y pauso en lugar de destruir para desarrollo."

---

## Problema 7: Azure Managed Prometheus/Grafana - Permisos de Grafana

### 📋 Síntomas
- Grafana no podía leer métricas de Prometheus
- Dashboards vacíos

### 🔍 Diagnóstico
- Faltaba asignar rol "Monitoring Reader" a la identidad de Grafana
- Role assignment no incluía el Prometheus workspace

### ✅ Solución
```powershell
# Asignar rol de lector sobre Prometheus workspace
az role assignment create `
    --assignee-object-id $(az grafana show --name "votingapp-grafana" --resource-group $RG --query "identity.principalId" -o tsv) `
    --assignee-principal-type ServicePrincipal `
    --role "Monitoring Reader" `
    --scope $PROMETHEUS_WORKSPACE_ID
```

### 🎯 Para entrevista
> "Managed Grafana necesita identity assignments explícitos para cada datasource. Es un patrón común en Azure: los servicios managed usan identidades que requieren RBAC específico."

---

# 📝 Resumen: Patrones de Problemas

| Categoría | Patrón Común | Prevención |
|-----------|--------------|------------|
| **Autenticación** | Permisos insuficientes, wrong tenant | Documentar qué cuenta para qué |
| **CI/CD** | Branch mismatch, triggers incorrectos | Verificar configuración vs repo |
| **Seguridad** | CVEs sin fix, secrets mal configurados | Políticas de aceptación de riesgo |
| **Kubernetes** | Nombres no coinciden, RBAC faltante | Verificar manifests vs realidad |
| **Multi-account** | Complejidad operacional | Scripts de setup, documentación |

---

# 🎤 La pregunta de entrevista

**"Cuéntame sobre un problema técnico difícil que hayas resuelto recientemente"**

> "Implementé un pipeline CI/CD para una aplicación en AKS donde tuve que manejar arquitectura cross-account - el registry en una suscripción y el cluster en otra. El desafío principal fue la autenticación: usé OIDC con Federated Credentials para el ACR ya que tenía permisos de App Registration, pero para el AKS tuve que usar kubeconfig como secret porque estaba en otro tenant.
>
> También configuré security scanning con Trivy que inicialmente bloqueaba el pipeline por CVEs sin fix en la imagen base de Debian. Documenté el riesgo y ajusté la configuración para reportar sin bloquear, mientras evaluábamos alternativas como imágenes Alpine.
>
> Lo más importante que aprendí es que en arquitecturas multi-cuenta, la documentación del 'quién hace qué con cuál identidad' es crítica para que el equipo pueda operar el sistema."
