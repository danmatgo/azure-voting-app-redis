# 🧠 GUÍA MAESTRA - PARTE 2
## Terraform (continuación) y Docker

---

# TERRAFORM CONTINUACIÓN

## main.tf - Recursos de Red

### ¿Por qué necesitamos una red?

En Azure (y cualquier nube), los recursos no se comunican mágicamente. Necesitan:
1. **Virtual Network (VNet)**: Una red privada virtual
2. **Subnets**: Divisiones de la VNet
3. **Network Security Groups (NSG)**: Firewalls

**Analogía**: 
- VNet = Tu edificio de oficinas
- Subnet = Un piso del edificio
- NSG = El guardia de seguridad que dice quién puede entrar

### Virtual Network

```hcl
resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space  # ["10.0.0.0/16"]
  tags                = local.common_tags
}
```

**¿Qué es `address_space = ["10.0.0.0/16"]`?**

Esto define qué direcciones IP puede usar la red. Explicación:

- `10.0.0.0/16` significa:
  - Empieza en 10.0.0.0
  - los primeros 16 bits son fijos (10.0)
  - los últimos 16 bits pueden variar (0.0 hasta 255.255)
  - Resultado: IPs desde 10.0.0.0 hasta 10.0.255.255 (65,536 direcciones)

**¿Por qué 10.x.x.x?**

Son direcciones "privadas" - no se usan en internet. Por convención:
- `10.0.0.0/8` - Privada
- `172.16.0.0/12` - Privada
- `192.168.0.0/16` - Privada (la típica de tu casa)

**Referencia a otro recurso**: `azurerm_resource_group.main.location`

Esto significa: "usa el valor de `location` del recurso `azurerm_resource_group` que llamamos `main`".

Beneficio: Si cambias la location del resource group, automáticamente todos los recursos que lo referencian cambian también.

### Subnet

```hcl
resource "azurerm_subnet" "aks" {
  name                 = "${local.name_prefix}-aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_prefix]  # ["10.0.1.0/24"]
}
```

**¿Qué es una Subnet?**

Una subdivisión de la VNet. Diferentes subnets para diferentes propósitos:
- Subnet para AKS (Kubernetes)
- Subnet para bases de datos
- Subnet para VMs internas
- etc.

**¿Por qué separar?**

Seguridad. Puedes poner reglas que digan "la subnet de bases de datos solo acepta conexiones desde la subnet de aplicaciones".

**`address_prefixes = ["10.0.1.0/24"]`**

- Subnet dentro de la VNet (10.0.0.0/16)
- `/24` = 256 direcciones (10.0.1.0 a 10.0.1.255)
- Suficiente para cientos de pods en Kubernetes

### Network Security Group (NSG)

```hcl
resource "azurerm_network_security_group" "aks" {
  name                = "${local.name_prefix}-aks-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.common_tags
}
```

**¿Qué es un NSG?**

Un firewall a nivel de red. Define qué tráfico puede entrar y salir.

**Anatomía de una regla**:

| Campo | Valor | Significado |
|-------|-------|-------------|
| `priority` | 100 | Orden de evaluación (menor = primero) |
| `direction` | "Inbound" | Tráfico entrando (vs "Outbound" saliendo) |
| `access` | "Allow" | Permitir (vs "Deny" bloquear) |
| `protocol` | "Tcp" | Solo TCP (no UDP) |
| `source_port_range` | "*" | Cualquier puerto de origen |
| `destination_port_ranges` | ["80","443"] | Solo puertos 80 (HTTP) y 443 (HTTPS) |
| `source_address_prefix` | "*" | Desde cualquier IP |
| `destination_address_prefix` | "*" | A cualquier IP de la subnet |

**¿Cómo se evalúan las reglas?**

```
Llega un paquete
       │
       ▼
Prioridad 100: ¿Coincide? 
       │
   Sí ─┴─ No
   │       │
   ▼       ▼
Allow    Prioridad 200: ¿Coincide?
         ...
         
Si ninguna regla coincide → DENY (por defecto)
```

---

## main.tf - Azure Kubernetes Service (AKS)

### ¿Qué es AKS?

AKS = Azure Kubernetes Service

**Kubernetes** es un sistema para manejar muchos contenedores. Pero Kubernetes tiene muchas partes:
- Control plane (el "cerebro")
- etcd (la base de datos de Kubernetes)
- Nodes (las máquinas que corren contenedores)

En AKS, Azure maneja el control plane por ti. Tú solo te preocupas por los nodes.

```
KUBERNETES AUTOINSTALADO:          AKS (MANAGED):
┌─────────────────────────┐        ┌─────────────────────────┐
│ Tú manejas:             │        │ Azure maneja:           │
│ - Control plane         │        │ - Control plane ✓       │
│ - etcd                  │        │ - etcd ✓                │
│ - Updates               │        │ - HA del control plane ✓│
│ - HA                    │        │                         │
│ - Nodes                 │        │ Tú manejas:             │
│                         │        │ - Nodes                 │
│ Costo: MUCHO tiempo     │        │ - Aplicaciones          │
└─────────────────────────┘        └─────────────────────────┘
```

### El Recurso AKS

```hcl
resource "azurerm_kubernetes_cluster" "main" {
  name                = "${local.name_prefix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${local.name_prefix}-aks"
  kubernetes_version  = "1.32.0"
```

**`dns_prefix`**: AKS genera un nombre DNS para acceder al cluster. El prefijo + un hash aleatorio. Ej: `votingapp-dev-aks-a1b2c3d4.hcp.eastus.azmk8s.io`

**`kubernetes_version`**: Qué versión de Kubernetes usar. Es importante especificarla porque:
1. AKS actualiza versiones automáticamente si no especificas
2. Updates pueden romper cosas
3. Quieres control sobre cuándo actualizar

```hcl
  default_node_pool {
    name                = "system"
    vm_size             = var.aks_node_vm_size
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = var.aks_enable_autoscaling
    node_count          = var.aks_enable_autoscaling ? null : var.aks_node_count
    min_count           = var.aks_enable_autoscaling ? var.aks_min_nodes : null
    max_count           = var.aks_enable_autoscaling ? var.aks_max_nodes : null
    tags                = local.common_tags
  }
```

**¿Qué es un node pool?**

Un grupo de máquinas virtuales idénticas que corren tus contenedores.

Puedes tener múltiples node pools:
- `system`: Para componentes de Kubernetes
- `app`: Para tus aplicaciones
- `gpu`: Para cargas que necesitan GPU

**`vm_size`**: El tamaño de las VMs. Opciones comunes:

| Tamaño | CPU | RAM | Uso típico |
|--------|-----|-----|------------|
| Standard_B2s | 2 | 4GB | Dev/test (barato) |
| Standard_D2s_v3 | 2 | 8GB | Producción pequeña |
| Standard_D4s_v3 | 4 | 16GB | Producción media |
| Standard_D8s_v3 | 8 | 32GB | Producción grande |

**B-series** = "Burstable". CPU barato que puede "explotar" temporalmente cuando necesita potencia.
**D-series** = Propósito general, CPU consistente.

**La expresión condicional**: `var.aks_enable_autoscaling ? null : var.aks_node_count`

Esto es un "ternario" (if-else en una línea):
- Si `aks_enable_autoscaling` es true → usar `null` (no fijar número)
- Si es false → usar `var.aks_node_count` (número fijo)

**¿Por qué `null`?**: Cuando autoscaling está habilitado, no puedes tener un número fijo de nodos. Tiene que ser `null` o Terraform da error.

```hcl
  identity {
    type = "SystemAssigned"
  }
```

**¿Qué es Managed Identity?**

Una identidad (como un usuario) que Azure crea y maneja automáticamente.

**Tipos**:
- **System-assigned**: Nace y muere con el recurso. Si borras el AKS, se borra la identidad.
- **User-assigned**: Tú la creas, la asignas a recursos, y la manejas.

**¿Por qué usarla?**

Sin identidad, AKS necesitaría un Service Principal con password. Passwords son inseguros:
- Hay que rotarlos
- Hay que guardarlos en algún lugar
- Pueden filtrarse

Con Managed Identity:
- No hay password
- Azure maneja todo
- Más seguro

```hcl
  network_profile {
    network_plugin = "kubenet"
    network_policy = "calico"
    pod_cidr       = "10.244.0.0/16"
    service_cidr   = "10.0.2.0/24"
    dns_service_ip = "10.0.2.10"
  }
```

**`network_plugin`**: Cómo los pods obtienen IPs.

| Plugin | Descripción | Cuándo usar |
|--------|-------------|-------------|
| kubenet | Pods tienen IPs de un rango separado | Mayoría de casos, más simple |
| azure | Pods tienen IPs de la VNet | Cuando necesitas que pods sean accesibles directamente desde la VNet |

**`network_policy`**: Motor para Network Policies (reglas de firewall entre pods).

- `calico`: El más popular, muchas features
- `azure`: Más simple, menos features

**`pod_cidr`**: Rango de IPs para pods. Solo aplica con `kubenet`.
**`service_cidr`**: Rango de IPs para Services de Kubernetes.
**`dns_service_ip`**: IP del servicio DNS interno de Kubernetes.

```hcl
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }
```

**¿Qué es OMS Agent?**

OMS = Operations Management Suite (ahora se llama Azure Monitor).

Este agente corre en cada nodo y envía:
- Logs de contenedores
- Métricas de CPU/memoria
- Eventos de Kubernetes

A Log Analytics Workspace donde puedes buscar, analizar, y crear alertas.

---

## Role Assignment - Permisos

```hcl
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
```

**¿Qué hace esto?**

Da permiso al AKS para descargar imágenes del ACR (Azure Container Registry).

**Componentes**:
- `scope`: ¿Sobre qué recurso aplica el permiso? (el ACR)
- `role_definition_name`: ¿Qué permiso? (AcrPull = solo leer imágenes)
- `principal_id`: ¿Quién recibe el permiso? (la identidad del AKS)

**¿Por qué `kubelet_identity[0]`?**

AKS tiene dos identidades:
1. **Cluster identity**: Para operaciones del cluster (crear Load Balancers, etc.)
2. **Kubelet identity**: Para operaciones de los nodos (descargar imágenes)

Usamos la kubelet identity porque es la que descarga imágenes.

**¿Por qué `AcrPull` y no `Contributor`?**

Principio de **Least Privilege** (mínimo privilegio):
- `Contributor`: Puede hacer TODO (leer, escribir, borrar)
- `AcrPull`: Solo puede leer

Si alguien compromete el AKS, con AcrPull solo puede leer imágenes. Con Contributor podría borrar todo el ACR.

---

# 📦 FASE 2: DOCKER - EMPAQUETANDO LA APLICACIÓN

## ¿Qué problema resuelve Docker?

**Sin Docker**:
```
Desarrollador:                  Servidor:
- Python 3.11                   - Python 3.8
- Flask 2.3                     - Flask 2.0 (o no instalado)
- Redis client 4.5              - Redis client ???
- Ubuntu 22.04                  - CentOS 7

Resultado: "Funciona en mi máquina" 🤷
```

**Con Docker**:
```
Desarrollador crea imagen:
┌─────────────────────────┐
│ Python 3.11             │
│ Flask 2.3               │
│ Redis client 4.5        │
│ Ubuntu 22.04            │
│ Mi aplicación           │
└─────────────────────────┘
         │
         ▼
Exactamente lo mismo corre en:
- La laptop del dev
- El servidor de testing
- Producción
```

## ¿Qué es una imagen de Docker?

Es un "snapshot" de un sistema de archivos con todo lo necesario para correr una aplicación.

**Analogía**: Una imagen es como un DVD de instalación. El contenedor es lo que queda cuando instalas el DVD.

## ¿Qué es un contenedor?

Una instancia en ejecución de una imagen. Puedes tener:
- 1 imagen
- 100 contenedores corriendo desde esa imagen

## El Dockerfile - Línea por Línea

### Etapa 1: Build

```dockerfile
FROM python:3.11-slim AS builder
```

**`FROM`**: Punto de partida. Usamos una imagen base que ya tiene Python instalado.

**`python:3.11-slim`**: 
- `python`: Imagen oficial de Python
- `3.11`: Versión específica
- `slim`: Variante minimalista (sin herramientas de compilación)

**¿Por qué `slim` y no la normal?**
- `python:3.11` ≈ 900 MB
- `python:3.11-slim` ≈ 120 MB

Menos tamaño = descarga más rápida = deploys más rápidos.

**`AS builder`**: Le damos un nombre a esta etapa para referenciarla después.

```dockerfile
WORKDIR /app
```

**¿Qué hace?**: "Desde ahora, todos los comandos se ejecutan en /app".

Equivalente a hacer `cd /app` pero además:
- Crea el directorio si no existe
- Lo establece como directorio de trabajo para los siguientes comandos

```dockerfile
COPY azure-vote/requirements.txt .
```

**¿Por qué copiar solo requirements.txt primero?**

Docker usa "capas" (layers). Cada instrucción crea una capa que se cachea.

```
Capa 1: FROM python:3.11-slim     [cached]
Capa 2: WORKDIR /app              [cached]
Capa 3: COPY requirements.txt     [cambió? si no, cached]
Capa 4: RUN pip install           [si capa 3 cached, esta también]
Capa 5: COPY . .                  [probablemente cambió]
```

Si copiáramos todo junto, cualquier cambio en el código invalidaría el cache de `pip install`, que toma tiempo.

Copiando requirements primero:
- Si código cambia pero requirements no → pip install usa cache
- Build mucho más rápido

```dockerfile
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt
```

**`RUN`**: Ejecuta un comando durante el build.

**`--no-cache-dir`**: No guardar cache de pip (reduce tamaño de imagen).

**`--prefix=/install`**: Instalar en /install en vez de la ubicación normal. Lo copiamos después a la imagen final.

### Etapa 2: Runtime

```dockerfile
FROM python:3.11-slim
```

Empezamos de nuevo con una imagen limpia. La etapa anterior (builder) se descarta.

**¿Cuál es el beneficio de multi-stage?**

```
Etapa builder (se descarta):
- Python + herramientas de build
- Código fuente
- Cache de compilación
- TOTAL: 500MB+

Etapa final (imagen real):
- Python runtime mínimo
- Solo los paquetes instalados
- Código de la app
- TOTAL: 180MB
```

```dockerfile
LABEL maintainer="Daniel Matapi" \
      version="1.0" \
      description="Azure Voting App Frontend"
```

**`LABEL`**: Metadatos de la imagen. No afectan el comportamiento pero ayudan a:
- Saber quién mantiene la imagen
- Filtrar imágenes por etiquetas
- Documentar propósito

```dockerfile
WORKDIR /app

RUN useradd --create-home --shell /bin/bash appuser
```

**¿Por qué crear un usuario?**

Por defecto Docker corre todo como `root`. Problemas:
1. Si un atacante explota la app, tiene acceso root
2. En Kubernetes, algunas configuraciones prohiben root
3. Es mala práctica de seguridad

Creamos un usuario normal (`appuser`) para correr la app.

```dockerfile
COPY --from=builder /install /usr/local
```

**`COPY --from=builder`**: Copia desde la etapa anterior.

Esto es lo especial de multi-stage: traemos SOLO lo que necesitamos (los paquetes instalados) desde la etapa de build.

```dockerfile
COPY azure-vote/ .
```

Copia el código de la aplicación al directorio actual (/app).

```dockerfile
RUN chown -R appuser:appuser /app
USER appuser
```

**`chown`**: Cambiar owner de archivos a appuser.
**`USER appuser`**: A partir de aquí, todo se ejecuta como appuser, no root.

```dockerfile
EXPOSE 8080
```

**¿Qué hace?**: Documenta que la aplicación escucha en puerto 8080.

**Importante**: NO abre el puerto. Es solo documentación. El puerto real se abre cuando corres el contenedor con `-p`.

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/')" || exit 1
```

**¿Qué es un healthcheck?**

Un comando que verifica si la aplicación está "sana".

**Parámetros**:
- `--interval=30s`: Revisar cada 30 segundos
- `--timeout=5s`: Si no responde en 5s, considerar fallido
- `--start-period=5s`: Esperar 5s antes de empezar a revisar
- `--retries=3`: 3 fallos consecutivos = unhealthy

**¿Cómo funciona el comando?**

```python
urllib.request.urlopen('http://localhost:8080/')
```
Hace un HTTP GET a localhost:8080. Si responde OK, la app está sana. Si falla, exit code 1.

```dockerfile
CMD ["python", "main.py"]
```

**¿Qué hace?**: Define el comando que corre cuando inicias un contenedor.

**Diferencia CMD vs ENTRYPOINT**:
- `CMD`: Se puede sobrescribir al correr el contenedor
- `ENTRYPOINT`: Más difícil de sobrescribir, define el ejecutable principal

Generalmente para aplicaciones web se usa CMD.
