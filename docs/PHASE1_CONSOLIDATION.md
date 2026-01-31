# 📚 FASE 1: Consolidación del Conocimiento
## Terraform Infrastructure as Code - Azure

---

## ✅ Revisión de tu Código

| Archivo | Estado | Observaciones |
|---------|--------|---------------|
| `providers.tf` | ✅ Perfecto | Provider Azure 3.x configurado correctamente |
| `variables.tf` | ✅ Perfecto | Validación de environment, tipos correctos |
| `main.tf` | ✅ Perfecto | Todos los recursos encadenados correctamente |
| `outputs.tf` | ✅ Perfecto | Outputs útiles para siguiente fase |

**Nota menor**: En `variables.tf` línea 29 dice "Enviroment" (typo), pero es solo un valor de tag, no afecta funcionalidad.

---

## 🏗️ Lo que Construiste (Arquitectura)

```
┌─────────────────────────────────────────────────────────────┐
│                    Resource Group                            │
│                    votingapp-dev-rg                          │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                 Virtual Network                      │    │
│  │                 10.0.0.0/16                          │    │
│  │  ┌─────────────────────────────────────────────┐    │    │
│  │  │            Subnet AKS                        │    │    │
│  │  │            10.0.1.0/24                       │    │    │
│  │  │  ┌───────────────────────────────────────┐  │    │    │
│  │  │  │         AKS Cluster                   │  │    │    │
│  │  │  │  ┌─────────┐                          │  │    │    │
│  │  │  │  │ Node B2s│ ◄── Autoscaling 1-3      │  │    │    │
│  │  │  │  └─────────┘                          │  │    │    │
│  │  │  │       │                               │  │    │    │
│  │  │  │       ▼ Managed Identity (AcrPull)    │  │    │    │
│  │  │  └───────────────────────────────────────┘  │    │    │
│  │  │              │ NSG: 80, 443, VNet            │    │    │
│  │  └─────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌──────────────┐  ┌──────────────────┐                     │
│  │  ACR Basic   │  │  Log Analytics   │                     │
│  │  (imágenes)  │  │  (monitoring)    │                     │
│  └──────────────┘  └──────────────────┘                     │
└─────────────────────────────────────────────────────────────┘
```

---

## 📖 Recapitulación: ¿Qué hace cada cosa?

### 1. providers.tf - Configuración del Provider

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers { azurerm = { source = "hashicorp/azurerm", version = "~> 3.0" } }
}
provider "azurerm" { features { ... } }
```

| Elemento | Qué es | Por qué importa |
|----------|--------|-----------------|
| `required_version` | Versión mínima de Terraform CLI | Evita incompatibilidades si alguien usa versión vieja |
| `required_providers` | Plugins necesarios (Azure en este caso) | Terraform descarga el plugin de HashiCorp Registry |
| `version = "~> 3.0"` | Cualquier versión 3.x | El `~>` permite patches pero no major versions |
| `features {}` | Bloque obligatorio de azurerm | Configura comportamiento del provider |

**Keyword para entrevista**: "Provider locking" - el archivo `.terraform.lock.hcl` guarda versiones exactas para reproducibilidad.

---

### 2. variables.tf - Parametrización

```hcl
variable "environment" {
  type    = string
  default = "dev"
  validation { condition = contains(["dev", "staging", "prod"], var.environment) }
}
```

| Concepto | Qué es | Uso real |
|----------|--------|----------|
| `type` | Tipo de dato (string, number, bool, list, map) | Terraform valida en plan time |
| `default` | Valor si no se especifica otro | Puedes sobrescribir con `-var` o `.tfvars` |
| `validation` | Regla de validación personalizada | Falla el plan si el valor no es válido |
| `map(string)` | Diccionario clave-valor | Usado para tags |

**Uso en producción**: Cada ambiente tiene su archivo `.tfvars`:
```bash
terraform apply -var-file="prod.tfvars"
```

---

### 3. main.tf - Recursos de Infraestructura

#### locals
```hcl
locals {
  name_prefix = "${var.project_name}-${var.environment}"  # "votingapp-dev"
  common_tags = merge(var.tags, { Environment = var.environment })
}
```
- **Propósito**: Variables computadas, evita repetir código
- **`merge()`**: Combina dos maps

#### Resource Group
```hcl
resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.location
}
```
- **Propósito**: Contenedor lógico de todos los recursos
- **Por qué?**: Eliminar el RG elimina todo (cleanup fácil)
- **Best practice**: Un RG por proyecto/ambiente

#### Container Registry (ACR)
```hcl
resource "azurerm_container_registry" "main" {
  sku           = "Basic"
  admin_enabled = false  # ← IMPORTANTE para seguridad
}
```
- **SKUs**: Basic ($5), Standard ($20), Premium ($167)
- **`admin_enabled = false`**: No usa passwords, usa Managed Identity
- **Nombre sin guiones**: ACR names son globalmente únicos y solo alfanuméricos

#### Virtual Network + Subnet
```hcl
address_space    = ["10.0.0.0/16"]   # 65,536 IPs disponibles
address_prefixes = ["10.0.1.0/24"]   # 256 IPs para AKS
```
- **VNet**: Red privada aislada
- **Subnet**: Segmento donde viven los nodos AKS
- **CIDR Notation**: `/16` = 65k IPs, `/24` = 256 IPs

#### Network Security Group (NSG)
```hcl
security_rule {
  name      = "AllowHTTP"
  priority  = 100          # Menor número = mayor prioridad
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"
  destination_port_ranges = ["80", "443"]
}
```
- **Propósito**: Firewall a nivel de subnet
- **Priority**: Reglas se evalúan de menor a mayor
- **Default**: Azure permite outbound, bloquea inbound

#### Log Analytics Workspace
```hcl
sku               = "PerGB2018"  # Pay-as-you-go
retention_in_days = 30
```
- **Propósito**: Almacena logs y métricas de AKS
- **Free tier**: 5GB/mes incluido
- **Container Insights**: Usa este workspace

#### AKS Cluster
```hcl
identity { type = "SystemAssigned" }

network_profile {
  network_plugin = "kubenet"
  network_policy = "calico"
}

oms_agent { log_analytics_workspace_id = ... }
```

| Configuración | Qué hace | Alternativa |
|---------------|----------|-------------|
| `SystemAssigned` | Azure crea identidad automática | UserAssigned (tú la creas) |
| `kubenet` | Plugin de red simple | Azure CNI (más IP pero más caro) |
| `calico` | Network policies entre pods | azure (menos features) |
| `oms_agent` | Envía métricas a Log Analytics | Sin monitoring |

#### Role Assignment (Zero Trust)
```hcl
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
```
- **Propósito**: Permite que AKS haga pull sin password
- **kubelet_identity**: La identidad que usan los nodos para pull
- **Zero Trust**: Sin secrets, Azure valida la identidad

---

### 4. outputs.tf - Valores de Salida

```hcl
output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}
```
- **Propósito**: Exponer valores para scripts/pipelines
- **Uso**: `terraform output -raw acr_login_server`

---

## 🎤 Preguntas de Entrevista - Terraform

### Básicas (las van a preguntar seguro)

**P: ¿Cuál es la diferencia entre Terraform y ARM Templates?**
> "Terraform es multi-cloud y usa HCL que es más legible que JSON. ARM solo funciona con Azure. Además, Terraform tiene `plan` para ver cambios antes de aplicar, y un ecosistema de módulos más grande. En Exsis elegí Terraform porque teníamos algunos recursos en AWS también."

**P: ¿Qué es el state file de Terraform?**
> "Es un archivo JSON que guarda el estado actual de la infraestructura. Terraform lo compara con el código para saber qué crear, modificar o eliminar. Es crítico protegerlo porque contiene datos sensibles. En producción lo guardo en Azure Storage con locking y encryption."

**P: ¿Cómo manejas diferentes ambientes (dev/staging/prod)?**
> "Uso una combinación de workspaces y archivos tfvars. Cada ambiente tiene su propio archivo como prod.tfvars con valores específicos como más nodos o VMs más grandes. También uso la variable environment para condicionales en el código."

### Intermedias

**P: ¿Qué es una Managed Identity y por qué la usas?**
> "Es una identidad que Azure asigna a recursos para autenticarse con otros servicios de Azure sin usar passwords o secrets. Hay dos tipos: System-assigned que vive junto al recurso, y User-assigned que es independiente. La uso porque implementa Zero Trust - no hay credentials que puedan ser robadas o rotadas."

**P: ¿Cuál es la diferencia entre Kubenet y Azure CNI?**
> "Kubenet es más simple - los pods tienen IPs internas y usan NAT para comunicación externa. Azure CNI da a cada pod una IP de la subnet, permitiendo comunicación directa con otros recursos Azure. Kubenet es más económico para clusters pequeños, Azure CNI es mejor cuando necesitas integración profunda con VNet peering o políticas granulares."

**P: ¿Por qué disabled admin en ACR?**
> "El admin account usa username/password que son credentials estáticas. Si se comprometen, hay que rotarlas manualmente. Con Managed Identity, Azure valida la identidad del servicio que hace pull, no hay secret que pueda filtrarse. Es parte del modelo Zero Trust."

### Avanzadas (menos probable pero impresiona)

**P: ¿Cómo harías rollback de infraestructura?**
> "Terraform guarda el state anterior. Puedo hacer `terraform state pull` para ver el estado, y si tengo el código anterior en Git, simplemente hago checkout de esa versión y `terraform apply`. También puedo usar `terraform import` para sincronizar recursos manuales. En casos críticos, tenemos snapshots del state file en Azure Storage con versioning."

**P: ¿Cómo evitas drift entre el código y la realidad?**
> "Ejecutamos `terraform plan` en CI/CD periódicamente para detectar cambios manuales. También tenemos políticas de Azure Policy que previenen ciertos cambios. En Exsis implementé un job nocturno que reporta drift al canal de Slack del equipo."

---

## 🔑 Keywords para la Entrevista

Menciona estas palabras naturalmente:

| Keyword | Contexto donde usarla |
|---------|----------------------|
| **IaC (Infrastructure as Code)** | "Todo nuestro infra está en código versionado" |
| **Idempotent** | "Terraform es idempotente - puedo aplicar múltiples veces y el resultado es el mismo" |
| **Declarative** | "Es declarativo - describo el estado final, no los pasos" |
| **State management** | "El state se guarda en backend remoto con locking" |
| **Zero Trust** | "Usamos Managed Identity para Zero Trust" |
| **Principle of Least Privilege** | "El ACR role es solo AcrPull, no administrador" |
| **Network segmentation** | "Cada tier tiene su subnet con NSG específico" |
| **Tagging strategy** | "Los tags nos permiten cost tracking y ownership" |

---

## 📋 Comandos que Ejecutaste

```bash
terraform init      # Descarga providers, inicializa backend
terraform validate  # Valida sintaxis HCL
terraform plan      # Muestra cambios sin aplicar
terraform apply     # Aplica los cambios
terraform output    # Muestra valores de outputs
terraform destroy   # Elimina todo (lo siguiente que harás)
```

---

## 🚀 Siguiente Paso

Ejecuta esto para destruir y ahorrar costos:

```powershell
cd "c:\Users\Daniel Matapi\cloud-practice\azure-voting-app-redis\terraform"
terraform destroy -auto-approve
```

Esta noche continúas con Fases 2 y 3 (Docker + Kubernetes).

---

## ✅ Checklist Conocimiento Fase 1

- [ ] Puedo explicar qué es IaC y por qué usar Terraform
- [ ] Entiendo la estructura: providers, variables, main, outputs
- [ ] Sé qué es Managed Identity y por qué es mejor que passwords
- [ ] Puedo explicar la diferencia entre Kubenet y Azure CNI
- [ ] Entiendo el flujo: init → validate → plan → apply
- [ ] Sé qué es el state file y por qué protegerlo
- [ ] Puedo hablar de Zero Trust en contexto de AKS-ACR
