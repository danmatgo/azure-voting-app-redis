# 🧠 GUÍA MAESTRA: ENTENDIMIENTO PROFUNDO
## Todo lo que necesitas saber sobre DevSecOps - Desde cero hasta producción

---

# 📖 ANTES DE EMPEZAR: ¿QUÉ VAMOS A ENTENDER?

## El Problema que Resolvemos

Imagina que tienes una aplicación web. En el mundo antiguo (hace 5-10 años):

1. **Desarrollo**: Un desarrollador escribe código en su laptop
2. **"Funciona en mi máquina"**: Lo pasa a operaciones
3. **Operaciones**: Intenta instalarlo en un servidor... y falla
4. **Finger pointing**: "Tu código está mal" vs "Tu servidor está mal"
5. **Horas/días de debugging**
6. **Finalmente funciona** (o no)
7. **3 meses después**: Hay que actualizarlo... repetir todo

**¿Cuál es el resultado?**
- Deploys dolorosos (una vez al mes, con miedo)
- Errores frecuentes
- Infraestructura "artesanal" (cada servidor es un copo de nieve único)
- Seguridad como afterthought

## La Solución Moderna: DevSecOps

```
ANTES:                           AHORA:
Dev ──────▶ Ops                  Dev ◀──────▶ Ops
   (muros)                          (colaboración)
                                        │
                                        ▼
                                    Seguridad
                                  (integrada)
```

**DevSecOps** = Development + Security + Operations trabajando juntos desde el inicio.

**¿Cómo se logra esto?**
- **Infrastructure as Code (Terraform)**: La infraestructura se define como código
- **Containers (Docker)**: La aplicación se empaqueta con TODO lo que necesita
- **Orquestación (Kubernetes)**: Manejo automático de muchos containers
- **CI/CD (GitHub Actions)**: Automatización de todo el proceso
- **Security (Trivy, etc.)**: Seguridad integrada en cada paso

---

# 🎯 LA APLICACIÓN: VOTING APP

## ¿Qué es?

Una aplicación web simple donde los usuarios pueden votar entre dos opciones (ej: Gatos vs Perros).

## ¿Por qué esta aplicación?

Es simple pero tiene todos los elementos de una aplicación real:
- **Frontend**: Lo que ve el usuario (interfaz web)
- **Backend**: Donde se procesan los votos
- **Base de datos**: Donde se guardan los votos (Redis)

## Arquitectura de la aplicación

```
USUARIO (navegador web)
        │
        │  HTTP Request
        ▼
┌───────────────────┐
│    FRONTEND       │
│   (Python/Flask)  │
│                   │
│  - Muestra página │
│  - Recibe votos   │
│  - Muestra total  │
└───────────────────┘
        │
        │  Guarda/Lee votos
        ▼
┌───────────────────┐
│      REDIS        │
│   (Base de datos) │
│                   │
│  Almacena:        │
│  - Cats: 150      │
│  - Dogs: 89       │
└───────────────────┘
```

**¿Por qué Redis y no MySQL/PostgreSQL?**

Redis es una base de datos "in-memory" (todo en RAM):
- **Ventaja**: Extremadamente rápida (microsegundos)
- **Desventaja**: Si se apaga, pierde los datos
- **Uso típico**: Contadores, caches, sesiones

Para una app de votación en tiempo real, Redis es perfecto porque:
1. Los votos deben contarse instantáneamente
2. No necesitamos datos históricos complejos
3. Es más simple de operar que una DB tradicional

---

# 🏗️ FASE 1: TERRAFORM - LA INFRAESTRUCTURA

## ¿Qué es "Infraestructura"?

Todo lo que tu aplicación necesita para correr que NO es el código de la aplicación:
- Servidores (máquinas virtuales)
- Redes (cómo se comunican los servidores)
- Bases de datos
- Balanceadores de carga
- Firewalls
- DNS
- Certificados SSL
- etc.

## El Problema: Infraestructura Manual

**Escenario**: Tu jefe dice "necesito un ambiente nuevo para testing".

**Sin IaC (Infrastructure as Code)**:
1. Abres el portal de Azure
2. Click, click, click... crear Resource Group
3. Click, click, click... crear Virtual Network
4. Click, click, click... crear AKS
5. Documentas todo en un Word (o no)
6. 2 horas después, terminas

**Problemas**:
- ¿Qué pasa si lo tienes que hacer 10 veces?
- ¿Qué pasa si alguien más lo tiene que replicar?
- ¿Cómo sabes que el ambiente de testing es IGUAL al de producción?
- ¿Cómo reviertes si algo sale mal?

## La Solución: Terraform

Terraform es un programa que:
1. Lee archivos de configuración (`.tf`)
2. Compara lo que QUIERES con lo que EXISTE
3. Crea, modifica, o elimina recursos para que coincidan

**Con IaC**:
1. Escribes un archivo de texto describiendo lo que quieres
2. Ejecutas `terraform apply`
3. 10 minutos después, todo está creado
4. ¿Quieres otro ambiente? Cambias una variable y repites
5. ¿Algo salió mal? `terraform destroy` y empiezas de nuevo

## Los Archivos de Terraform

### ¿Por qué múltiples archivos?

Podrías poner todo en un solo archivo, pero sería un caos. Lo separamos por función:

```
terraform/
│
├── providers.tf      # DÓNDE crear recursos
│                     # (Azure, AWS, GCP...)
│                     # También: dónde guardar el estado
│
├── variables.tf      # QUÉ PUEDE CAMBIAR
│                     # (nombre del proyecto, tamaño de VMs, etc.)
│
├── main.tf           # QUÉ CREAR
│                     # (los recursos reales)
│
├── outputs.tf        # QUÉ VALORES EXPORTAR
│                     # (para usar después)
│
└── environments/
    ├── dev.tfvars    # Valores para desarrollo
    └── prod.tfvars   # Valores para producción
```

---

## providers.tf - EXPLICACIÓN LÍNEA POR LÍNEA

```hcl
terraform {
```
**¿Qué es?**: Abre el bloque de configuración de Terraform mismo (no de los recursos).

```hcl
  required_version = ">= 1.0"
```
**¿Qué hace?**: Dice "este código necesita Terraform versión 1.0 o superior".
**¿Por qué?**: Si alguien tiene Terraform 0.12, el código podría no funcionar. Esto previene errores raros.

```hcl
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatevoting2390"
    container_name       = "tfstate"
    key                  = "votingapp-dev.tfstate"
  }
```
**¿Qué es un backend?**: Donde Terraform guarda el "estado" (state).

**¿Qué es el estado?**: Un archivo JSON que dice "estos recursos existen y tienen estas propiedades". Terraform lo compara con tu código para saber qué tiene que crear, modificar, o eliminar.

**¿Por qué en Azure Storage y no local?**:
- **Local**: Solo tú tienes el archivo. Si otra persona hace `terraform apply`, no sabe qué existe.
- **Remoto**: Todos comparten el mismo archivo. Azure Storage además tiene "locking" - si tú estás modificando, nadie más puede al mismo tiempo.

**Analogía**: Es como Google Docs vs un archivo Word en tu computadora. Google Docs todos ven lo mismo, Word cada quien tiene su copia.

```hcl
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}
```
**¿Qué es un provider?**: Un plugin que sabe cómo crear recursos en una plataforma específica (Azure, AWS, GCP, etc.).

**¿Qué significa `~> 3.0`?**: "Aceptar versión 3.x pero NO 4.x". La notación `~>` significa "aceptar actualizaciones menores".
- `3.0` ✅
- `3.117` ✅
- `4.0` ❌

**¿Por qué limitar la versión?**: Las versiones mayores (3→4) suelen tener "breaking changes" - cosas que funcionaban podrían dejar de funcionar.

```hcl
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
```
**¿Qué hace?**: Configura el provider de Azure.

**¿Qué son `features {}`?**: Configuraciones específicas de Azure. Aquí decimos "permitir borrar resource groups aunque tengan recursos dentro". Por defecto Azure protege contra esto.

**¿Por qué `false`?**: En desarrollo queremos poder hacer `terraform destroy` limpiamente. En producción pondrías `true` para proteger contra borrados accidentales.

---

## variables.tf - EXPLICACIÓN LÍNEA POR LÍNEA

```hcl
variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
  default     = "votingapp"
}
```

**¿Qué es una variable?**: Un valor que puede cambiar sin modificar el código principal.

**¿Por qué usarlas?**: Imagina que hardcodeas "votingapp" en 50 lugares. Luego cambias el nombre a "pollapp". Tendrías que cambiar 50 líneas. Con variables, cambias en UN solo lugar.

**Partes de una variable**:
- `description`: Documentación para humanos
- `type`: ¿Es un string? ¿Un número? ¿Una lista?
- `default`: Valor si nadie especifica otro

```hcl
variable "environment" {
  description = "Ambiente"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "El ambiente debe ser dev, staging, o prod."
  }
}
```

**¿Qué es `validation`?**: Una regla que verifica que el valor es válido ANTES de crear recursos.

**¿Por qué validar?**: Si alguien escribe `environment = "produccion"` (en español), no habrá error de Terraform pero los nombres de recursos serán inconsistentes. La validación falla inmediatamente con un mensaje claro.

**¿Cómo funciona `contains()`?**: Verifica si el valor está en la lista. `contains(["a", "b", "c"], "b")` = true.

---

## main.tf - LOS RECURSOS

### ¿Qué es un "recurso" en Terraform?

Un recurso es algo que Terraform crea y administra. Puede ser:
- Una máquina virtual
- Una base de datos
- Una red
- Un usuario
- Un permiso
- etc.

### locals - Variables Internas

```hcl
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(var.tags, {
    Environment = var.environment
  })
}
```

**¿Qué son `locals`?**: Variables que solo existen dentro de Terraform. No se pueden pasar desde afuera como `variables`.

**¿Por qué usarlas?**: Para evitar repetir cálculos. `"${var.project_name}-${var.environment}"` se usa en muchos recursos. En vez de escribirlo 10 veces, lo guardamos como `local.name_prefix`.

**¿Qué hace `merge()`?**: Combina dos mapas (diccionarios). Si tenemos:
- `var.tags = {Project = "VotingApp", Owner = "Daniel"}`
- `{Environment = "dev"}`

El resultado es: `{Project = "VotingApp", Owner = "Daniel", Environment = "dev"}`

### Resource Group

```hcl
resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.common_tags
}
```

**¿Qué es un Resource Group?**: En Azure, es un contenedor lógico para recursos relacionados. No tiene costo, es solo organización.

**¿Por qué es importante?**: 
1. Puedes borrar todo un proyecto borrando el Resource Group
2. Puedes ver costos agrupados por Resource Group
3. Puedes aplicar permisos a nivel de Resource Group

**Anatomía del recurso**:
- `resource`: Keyword de Terraform
- `"azurerm_resource_group"`: Tipo de recurso (del provider azurerm)
- `"main"`: Nombre interno en Terraform (para referenciarlo)
