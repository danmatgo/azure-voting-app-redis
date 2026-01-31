# 📚 FASE 2: Consolidación del Conocimiento
## Docker y Containerización

---

## ✅ Revisión de tu Código

| Archivo | Estado | Observaciones |
|---------|--------|---------------|
| `Dockerfile` | ✅ Perfecto | Multi-stage, non-root user, healthcheck |
| `requirements.txt` | ✅ Perfecto | Versiones pinned (Flask 3.0, redis 5.0) |
| `main.py` | ✅ Perfecto | Actualizado con host='0.0.0.0', port=80 |

**Pequeño ajuste**: Usaste Flask 3.0.0 y Werkzeug 3.0.1 (más nuevas que la guía) - está bien, son versiones estables.

---

## 🐳 Lo que Construiste

```
┌────────────────────────────────────────────────────────────────┐
│                    MULTI-STAGE BUILD                           │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│   STAGE 1: builder                    STAGE 2: runtime         │
│   ┌─────────────────────┐            ┌─────────────────────┐   │
│   │ python:3.11-slim    │            │ python:3.11-slim    │   │
│   │ + gcc               │            │ (sin gcc)           │   │
│   │ + pip install deps  │───COPY───▶│ + deps instaladas   │   │
│   │                     │            │ + código app        │   │
│   │ ~300MB              │            │ + non-root user     │   │
│   └─────────────────────┘            │ ~150MB              │   │
│        (descartado)                  └─────────────────────┘   │
│                                            │                    │
│                                            ▼                    │
│                                      ┌─────────────┐           │
│                                      │ ACR         │           │
│                                      │ (pushed)    │           │
│                                      └─────────────┘           │
└────────────────────────────────────────────────────────────────┘
```

---

## 📖 Recapitulación: ¿Qué significa cada línea?

### Dockerfile Línea por Línea

```dockerfile
FROM python:3.11-slim as builder
```
| Elemento | Significado |
|----------|-------------|
| `FROM` | Imagen base desde la cual construir |
| `python:3.11-slim` | Python 3.11 en Debian minimalista (~45MB vs ~900MB de full) |
| `as builder` | Nombra este stage para referenciar después |

---

```dockerfile
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
```
| Variable | Efecto |
|----------|--------|
| `PYTHONDONTWRITEBYTECODE=1` | No crea archivos `.pyc` (reduce tamaño) |
| `PYTHONUNBUFFERED=1` | Logs aparecen inmediatamente (importante para Docker/K8s) |

---

```dockerfile
WORKDIR /app
```
- Crea el directorio `/app` y lo usa como working directory
- Todos los comandos siguientes se ejecutan desde aquí

---

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends gcc && rm -rf /var/lib/apt/lists/*
```
| Parte | Por qué |
|-------|---------|
| `apt-get update` | Actualiza índice de paquetes |
| `--no-install-recommends` | Solo instala lo mínimo necesario |
| `gcc` | Compilador C, necesario para algunas dependencias Python |
| `rm -rf /var/lib/apt/lists/*` | Limpia cache para reducir tamaño de imagen |

**Best Practice**: Todo en un solo RUN para crear una sola layer.

---

```dockerfile
COPY azure-vote/requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt
```
| Técnica | Beneficio |
|---------|-----------|
| Copiar solo `requirements.txt` primero | Docker cache: si no cambian deps, no reinstala |
| `--no-cache-dir` | No guarda cache de pip (menos espacio) |
| `--user` | Instala en directorio del usuario, no system-wide |

---

```dockerfile
FROM python:3.11-slim
```
- **SEGUNDO STAGE**: Imagen final limpia
- No tiene gcc ni cache de apt
- Solo tendrá lo que copiemos explícitamente

---

```dockerfile
LABEL maintainer="Daniel Matapi" \
    version="1.0.0" \
    description="Azure Vote Frontend"
```
- Metadata de la imagen
- Visible con `docker inspect`
- Best practice para trazabilidad

---

```dockerfile
RUN groupadd --gid 1000 appgroup && \
    useradd --uid 1000 --gid appgroup --shell /bin/bash --create-home appuser
```
| Comando | Efecto |
|---------|--------|
| `groupadd --gid 1000` | Crea grupo con ID específico |
| `useradd --uid 1000` | Crea usuario con ID específico |
| `--create-home` | Crea directorio home para el usuario |

**¿Por qué IDs específicos?**: Consistencia con sistemas host, algunos clusters requieren rangos específicos.

---

```dockerfile
COPY --from=builder /root/.local /home/appuser/.local
```
| Parte | Significado |
|-------|-------------|
| `--from=builder` | Copia desde el stage anterior |
| `/root/.local` | Donde pip --user instaló las dependencias |
| `/home/appuser/.local` | Nuevo home del usuario non-root |

**Esto es el corazón del multi-stage**: Solo traes las dependencias compiladas, sin gcc ni cache.

---

```dockerfile
COPY azure-vote/ /app/
RUN chown -R appuser:appgroup /app
USER appuser
```
| Línea | Propósito |
|-------|-----------|
| `COPY` | Copia código de la app |
| `chown` | Cambia ownership al usuario non-root |
| `USER appuser` | Todos los comandos siguientes corren como este usuario |

**Seguridad**: El proceso ya no corre como root.

---

```dockerfile
EXPOSE 80
```
- Documenta que el container escucha en puerto 80
- No abre el puerto, solo metadata
- El puerto se mapea con `-p` o en K8s Service

---

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:80/')" || exit 1
```
| Parámetro | Valor | Significado |
|-----------|-------|-------------|
| `--interval` | 30s | Cada 30 segundos verifica |
| `--timeout` | 3s | Si no responde en 3s, falla |
| `--start-period` | 40s | Espera 40s antes de iniciar checks (tiempo de startup) |
| `--retries` | 3 | Después de 3 fallos, marca como unhealthy |

---

```dockerfile
CMD ["python", "main.py"]
```
- Comando que se ejecuta al iniciar el container
- Formato exec (array) vs shell - exec es preferido
- Se puede sobrescribir con `docker run ... <otro_comando>`

---

### requirements.txt

```
Flask==3.0.0
redis==5.0.1
gunicorn==21.2.0
Werkzeug==3.0.1
```

| Dependencia | Para qué |
|-------------|----------|
| `Flask` | Framework web Python |
| `redis` | Cliente para conectar a Redis |
| `gunicorn` | Servidor WSGI para producción (alternativa al server dev de Flask) |
| `Werkzeug` | Base de Flask, version pinned para evitar conflictos |

**Best Practice**: Versiones exactas (`==`) para reproducibilidad, no `>=` o `~=`.

---

### main.py - Cambio Clave

```python
if __name__ == "__main__":
    app.run(host='0.0.0.0', port=80)
```

| Parámetro | Por qué |
|-----------|---------|
| `host='0.0.0.0'` | Escucha en todas las interfaces (necesario en containers) |
| `port=80` | Puerto HTTP estándar |

Sin `0.0.0.0`, Flask solo escucha en localhost y el container no sería accesible.

---

## 🏷️ Tags de Imágenes

Cuando hiciste push al ACR, usaste dos tags:

```powershell
docker tag azure-vote-front:local "${ACR}/azure-vote-front:${SHA}"
docker tag azure-vote-front:local "${ACR}/azure-vote-front:latest"
```

| Tag | Propósito | En producción |
|-----|-----------|---------------|
| `SHA (abc123...)` | Inmutable, única para cada build | ✅ Siempre usar en deployments |
| `latest` | Mutable, apunta a "la más reciente" | ⚠️ Solo para dev/convenience |

**Problema con latest**: Si haces deploy con `latest`, no sabes qué versión exacta está corriendo.

---

## 🎤 Preguntas de Entrevista - Docker/Containers

### Básicas

**P: ¿Qué es un container vs una VM?**
> "Un container comparte el kernel del host, es más liviano y arranca en segundos. Una VM tiene su propio kernel y OS completo, más aislamiento pero más overhead. Containers son ideales para microservicios donde necesitas escalar rápido."

**P: ¿Qué es multi-stage build y por qué lo usas?**
> "Es cuando tienes múltiples FROM en un Dockerfile. El primer stage tiene herramientas de build como gcc, el segundo stage es la imagen final limpia que solo copia los artefactos compilados. Reduce el tamaño de imagen significativamente y elimina herramientas que podrían ser vectores de ataque."

**P: ¿Por qué usas usuario non-root?**
> "Si un atacante explota una vulnerabilidad en la app, obtiene los permisos del proceso. Con root, podría modificar el filesystem, instalar malware, o intentar escapar del container. Con un usuario sin privilegios, el impacto está contenido. Además, muchos clusters Kubernetes tienen Pod Security Policies que bloquean containers root."

### Intermedias

**P: ¿Cuál es la diferencia entre CMD y ENTRYPOINT?**
> "ENTRYPOINT define el ejecutable principal del container y no se sobrescribe fácilmente. CMD define argumentos por defecto que sí se pueden sobrescribir. Típicamente uso ENTRYPOINT para el comando fijo y CMD para argumentos configurables. Por ejemplo, ENTRYPOINT ['python'] y CMD ['app.py']."

**P: ¿Por qué pones COPY requirements.txt antes del código?**
> "Para aprovechar el cache de Docker layers. Si el código cambia pero las dependencias no, Docker reutiliza la layer de pip install y solo reconstruye la layer del código. Esto acelera significativamente los builds en CI/CD."

**P: ¿Qué son las layers en Docker?**
> "Cada instrucción del Dockerfile (RUN, COPY, etc.) crea una layer. Las layers son inmutables y se cachean. Por eso es importante ordenar las instrucciones de menos cambiantes (dependencias) a más cambiantes (código). También por eso uso && para combinar comandos en un solo RUN - menos layers, imagen más pequeña."

### Avanzadas

**P: ¿Cómo escaneas vulnerabilidades en imágenes?**
> "Uso Trivy en el pipeline de CI/CD. Escanea la imagen después del build y antes del push al registry. Puede configurarse para fallar el pipeline si encuentra vulnerabilidades críticas. También ACR tiene scanning integrado con Defender for Containers."

**P: ¿Qué es distroless y cuándo lo usarías?**
> "Son imágenes de Google que no tienen shell ni package manager - solo el runtime necesario. Reducen la superficie de ataque dramáticamente. Las usaría para producción en entornos de alta seguridad. La desventaja es que no puedes hacer exec into the container para debug."

**P: ¿Cómo manejas secrets en containers?**
> "Nunca en el Dockerfile o imagen - cualquiera con acceso a la imagen puede verlos. En Kubernetes uso Secrets montados como environment variables o archivos. En desarrollo local, uso archivos .env que están en .gitignore. Los secrets sensibles vienen de Azure Key Vault integrado con AKS."

---

## 🔑 Keywords para la Entrevista

| Keyword | Cómo usarla naturalmente |
|---------|--------------------------|
| **Image layer** | "Optimizo el orden de instrucciones para aprovechar cache de layers" |
| **Multi-stage build** | "Uso multi-stage para separar build-time de runtime" |
| **Non-root user** | "Siempre corro como non-root por security best practice" |
| **Immutable tag** | "En producción uso SHA tags, no latest, para reproducibilidad" |
| **Distroless** | "Para máxima seguridad consideraría imágenes distroless" |
| **Attack surface** | "Multi-stage reduce la superficie de ataque al eliminar herramientas de build" |
| **OCI** | "Los containers siguen el estándar OCI (Open Container Initiative)" |
| **Registry** | "Las imágenes se guardan en un registry privado como ACR" |

---

## 📋 Comandos que Ejecutaste

```bash
# Build local
docker build -t azure-vote-front:local .

# Ver SHA de la imagen
docker inspect --format='{{.Id}}' azure-vote-front:local

# Login a ACR (usa Managed Identity o Azure CLI creds)
az acr login --name votingappdevacr

# Tag para ACR
docker tag azure-vote-front:local votingappdevacr.azurecr.io/azure-vote-front:abc123
docker tag azure-vote-front:local votingappdevacr.azurecr.io/azure-vote-front:latest

# Push a ACR
docker push votingappdevacr.azurecr.io/azure-vote-front:abc123
docker push votingappdevacr.azurecr.io/azure-vote-front:latest

# Verificar en ACR
az acr repository list --name votingappdevacr
az acr repository show-tags --name votingappdevacr --repository azure-vote-front
```

---

## 🔧 Troubleshooting Docker (para entrevista)

| Problema | Comando de diagnóstico | Solución típica |
|----------|----------------------|-----------------|
| Container no arranca | `docker logs <container>` | Ver error en logs |
| Imagen muy grande | `docker history <image>` | Identificar layers grandes |
| Build falla | Leer output del build | Dependencia faltante o path incorrecto |
| No conecta a servicio | `docker exec -it <c> sh` | Debug desde dentro del container |
| Permission denied | `ls -la` dentro del container | Chequear ownership de archivos |

---

## ✅ Checklist Conocimiento Fase 2

- [ ] Puedo explicar qué es multi-stage build y su beneficio
- [ ] Entiendo por qué usar non-root user en containers
- [ ] Sé la diferencia entre CMD y ENTRYPOINT
- [ ] Puedo explicar el orden óptimo de instrucciones (cache de layers)
- [ ] Entiendo por qué usar SHA tags vs latest
- [ ] Sé cómo funciona HEALTHCHECK y para qué sirve
- [ ] Puedo explicar ENV PYTHONUNBUFFERED y su importancia en containers
