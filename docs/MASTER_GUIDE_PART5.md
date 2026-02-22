# 🧠 GUÍA MAESTRA - PARTE 5
## Problemas encontrados, soluciones, y cómo explicarlo todo

---

# 🔧 PROBLEMAS Y SOLUCIONES

Esta sección documenta todos los problemas que encontramos y cómo los resolvimos. Esto es EXACTAMENTE lo que te van a preguntar en entrevistas: "Cuéntame un problema técnico que hayas enfrentado y cómo lo resolviste."

---

## Problema 1: Sin permisos para crear App Registration

### Situación

Queríamos configurar OIDC para que GitHub Actions se autentique con Azure sin passwords. Pero OIDC requiere crear una App Registration en Entra ID (Azure AD).

### El error

```
az ad app create --display-name "github-actions-votingapp"
ERROR: Insufficient privileges to complete the operation.
```

### ¿Por qué pasó?

En organizaciones empresariales, crear App Registrations está restringido. Necesitas roles como:
- Application Administrator
- Cloud Application Administrator
- Global Administrator

La cuenta de trabajo no tenía ninguno de estos roles.

### Cómo lo resolvimos

Usamos una arquitectura **cross-account**:

```
CUENTA PERSONAL (Trial con Global Admin)     CUENTA TRABAJO
├── App Registration + OIDC                   └── AKS Cluster
├── Azure Container Registry (ACR)
└── Terraform state storage

GITHUB ACTIONS:
├── OIDC → Cuenta Personal → ACR (push imágenes)
└── Kubeconfig secret → Cuenta Trabajo → AKS (deploy)
```

**¿Qué aprendimos?**

En empresas reales esto es común. Diferentes equipos manejan diferentes recursos:
- Equipo de Identidad → maneja App Registrations
- Equipo de Plataforma → maneja AKS
- Equipo de Dev → usa ambos

La solución es coordinar con los equipos o usar cuentas de servicio con permisos adecuados.

---

## Problema 2: Trivy bloqueando el pipeline

### Situación

Configuramos Trivy para escanear imágenes antes de push. Queremos detectar vulnerabilidades.

### El error

```
CRITICAL: libssl3 CVE-2024-XXXX (no fix available)
CRITICAL: openssl CVE-2024-YYYY (no fix available)

Pipeline: FAILED ❌
```

### ¿Por qué pasó?

La imagen base (`python:3.11-slim`, basada en Debian) tiene vulnerabilidades en librerías del sistema operativo. PERO no hay parche disponible todavía.

### El dilema

```
Opción A: Bloquear hasta que haya parche
          → Podrían pasar semanas/meses
          → No puedes deployar features nuevos

Opción B: Ignorar y pushear
          → Vulnerabilidad potencial en producción
          → Si hay exploit, es tu responsabilidad
```

### Cómo lo resolvimos

Configuramos Trivy para **reportar sin bloquear**:

```yaml
- name: Trivy scan
  uses: aquasecurity/trivy-action@master
  with:
    exit-code: '0'          # No fallar
    severity: 'CRITICAL,HIGH'
```

Y documentamos la decisión:

```
# Decisión de Riesgo: CVE-2024-XXXX
Fecha: 2026-01-31
Severidad: CRITICAL
Afecta: libssl3 en Debian Bookworm
Fix disponible: NO
Decisión: Aceptar riesgo temporal
Justificación: 
  - No hay parche disponible
  - La vulnerabilidad requiere acceso local
  - Nuestros pods tienen Network Policies
  - Monitorearemos para parchear cuando esté disponible
Próxima revisión: 2026-02-15
```

**¿Qué aprendimos?**

La seguridad no es blanco o negro. A veces hay que balancear:
- Riesgo de la vulnerabilidad
- Impacto de no deployar
- Contexto (¿es explotable en TU ambiente?)

Lo importante es **documentar la decisión** y **dar seguimiento**.

---

## Problema 3: La rama se llama master, no main

### Situación

Configuramos el workflow de CI/CD. Hicimos push. El pipeline no se ejecutó.

### El error

No había error visible. Simplemente no pasaba nada.

### ¿Por qué pasó?

El workflow estaba configurado para `main`:

```yaml
on:
  push:
    branches: [main]  # ← Incorrecto
```

Pero nuestro repo usa `master` (el nombre histórico default de Git).

### Cómo lo resolvimos

Cambiamos todas las referencias de `main` a `master`:

```yaml
on:
  push:
    branches: [master]  # ← Correcto
```

Y en la condición del job de deploy:

```yaml
if: github.ref == 'refs/heads/master'  # ← Correcto
```

**¿Qué aprendimos?**

- Siempre verificar la configuración contra tu repo real
- GitHub cambió el default de `master` a `main` en 2020
- Repos viejos pueden usar `master`, nuevos usan `main`
- Leer los logs de Actions para ver por qué no se ejecutó

---

## Problema 4: ImagePullBackOff en Kubernetes

### Situación

Hicimos deploy. Los pods no arrancan.

### El error

```
kubectl get pods -n voting-app
NAME                        READY   STATUS             RESTARTS   AGE
frontend-abc123             0/1     ImagePullBackOff   0          2m
```

```
kubectl describe pod frontend-abc123 -n voting-app
Events:
  Failed to pull image "votingappdevacr.azurecr.io/azure-vote-front:latest":
  unauthorized: authentication required
```

### ¿Por qué pasó?

AKS no tiene permisos para descargar imágenes del ACR.

### Proceso de debugging

1. **Verificar que la imagen existe**:
```bash
az acr repository show-tags --name votingappdevacr --repository azure-vote-front
# Resultado: ["abc123d", "latest"]  ← La imagen SÍ existe
```

2. **Verificar permisos**:
```bash
az role assignment list --scope /subscriptions/X/resourceGroups/Y/providers/Microsoft.ContainerRegistry/registries/votingappdevacr
# Resultado: No hay assignment para el AKS
```

3. **Problema encontrado**: El role assignment no se creó.

### Cómo lo resolvimos

Creamos el role assignment manualmente (porque Terraform no lo había aplicado):

```bash
az role assignment create \
  --assignee [AKS_KUBELET_IDENTITY] \
  --role AcrPull \
  --scope [ACR_ID]
```

Después verificamos:
```bash
kubectl delete pod frontend-abc123 -n voting-app
# El Deployment crea uno nuevo automáticamente
kubectl get pods -n voting-app
# STATUS: Running ✅
```

**¿Qué aprendimos?**

El flujo de debugging para ImagePullBackOff:
1. ¿La imagen existe en el registry? (nombre correcto, tag correcto)
2. ¿Tengo acceso al registry? (permisos, authentication)
3. ¿La imagen está corrupta? (raro pero posible)

---

## Problema 5: Pod en CrashLoopBackOff

### Situación

El pod arranca pero se reinicia constantemente.

### El error

```
kubectl get pods -n voting-app
NAME                        READY   STATUS             RESTARTS   AGE
frontend-xyz789             0/1     CrashLoopBackOff   4          3m
```

### Proceso de debugging

1. **Ver logs del pod**:
```bash
kubectl logs frontend-xyz789 -n voting-app
# Error: Cannot connect to Redis at 'redis:6379'
```

2. **Verificar que Redis existe**:
```bash
kubectl get pods -n voting-app
# redis-abc123    1/1     Running
kubectl get svc -n voting-app
# redis          ClusterIP   10.0.1.5    6379/TCP
```

3. **El servicio existe, ¿por qué no conecta?**

4. **Verificar DNS**:
```bash
kubectl run debug --rm -it --image=busybox -- nslookup redis.voting-app.svc.cluster.local
# Returns: 10.0.1.5   ← DNS funciona
```

5. **Verificar conectividad**:
```bash
kubectl run debug --rm -it --image=busybox -- nc -zv redis.voting-app.svc.cluster.local 6379
# Connection refused  ← Problema encontrado!
```

6. **Verificar que Redis está respondiendo**:
```bash
kubectl logs redis-abc123 -n voting-app
# Error: permission denied, cannot write to /data
```

### ¿Por qué pasó?

Redis no podía escribir en su volumen por problemas de permisos.

### Cómo lo resolvimos

Agregamos security context al pod de Redis:

```yaml
securityContext:
  fsGroup: 1000
  runAsUser: 1000
```

**¿Qué aprendimos?**

Debugging sistemático:
1. **Ver logs** del pod que falla
2. **Verificar dependencias** (¿Redis está corriendo?)
3. **Verificar red** (¿DNS resuelve? ¿Puerto accesible?)
4. **Ver logs de dependencias** (¿Redis tiene errores?)

---

## Problema 6: Federated Credential no matchea

### Situación

Configuramos OIDC. El workflow falla en Azure Login.

### El error

```
Error: AADSTS700212: No matching federated identity record found for presented assertion
```

### ¿Por qué pasó?

El "subject" del token de GitHub no coincide con lo configurado en Azure.

El error típico: configuramos para `main` pero el repo usa `master`.

### Cómo lo resolvimos

1. Ver qué subject envía GitHub:
```
repo:danmatgo/azure-voting-app-redis:ref:refs/heads/master
```

2. Ver qué tenemos configurado en Azure:
```bash
az ad app federated-credential list --id $APP_ID
# subject: repo:danmatgo/azure-voting-app-redis:ref:refs/heads/main  ← MAL
```

3. Actualizar al subject correcto:
```bash
az ad app federated-credential delete --id $APP_ID --federated-credential-id "github-main"
az ad app federated-credential create --id $APP_ID --parameters '{
  "name": "github-master",
  "subject": "repo:danmatgo/azure-voting-app-redis:ref:refs/heads/master"
}'
```

**¿Qué aprendimos?**

El subject DEBE coincidir EXACTAMENTE:
- Nombre del repo (case sensitive)
- Nombre de la rama (case sensitive)
- Tipo de evento (branch, environment, tag, etc.)

---

# 🎤 CÓMO EXPLICAR TODO ESTO EN UNA ENTREVISTA

## Sobre tu background

> "He estado trabajando con infraestructura cloud y pipelines de CI/CD. Mi stack principal es Azure con Terraform para IaC, Kubernetes para orquestación, y GitHub Actions para automatización. Me enfoco mucho en seguridad integrada desde el inicio del desarrollo."

## Sobre un proyecto reciente

> "Implementé un pipeline completo de CI/CD para una aplicación containerizada. La arquitectura usa AKS para el runtime, ACR como registry privado, y GitHub Actions con autenticación OIDC para evitar manejar secrets. Incluí escaneo de vulnerabilidades con Trivy antes de cada push al registry."

## Cuando pregunten sobre Terraform

> "Uso Terraform con remote backend en Azure Storage para el state, lo cual me da locking automático cuando trabajo en equipo. Estructuro el código con variables separadas por ambiente usando tfvars, así el mismo código despliega a dev, staging y prod con configuraciones diferentes. Para seguridad, uso Managed Identity en vez de service principals con passwords."

## Cuando pregunten sobre Docker

> "Siempre uso multi-stage builds para minimizar el tamaño de imagen - he reducido imágenes de más de un GB a menos de 200MB. Los contenedores corren con usuario no-root por principio de least privilege. Pineo las versiones de todas las dependencias para garantizar reproducibilidad."

## Cuando pregunten sobre Kubernetes

> "Estructuro los manifests con Kustomize para manejar ambientes. Cada Deployment tiene liveness y readiness probes diferenciados - liveness para detectar procesos muertos, readiness para control de tráfico durante inicialización lenta. Uso HPA para escalar automáticamente basado en CPU, con PDBs para garantizar disponibilidad durante mantenimiento."

## Cuando pregunten sobre CI/CD

> "Mi pipeline típico es: build de imagen, escaneo de seguridad antes de push, y deploy a Kubernetes con Kustomize. Uso OIDC para autenticación con Azure - no hay passwords almacenados, solo tokens de corta duración. El deploy usa rolling updates para zero downtime."

## Cuando pregunten sobre un problema técnico

> "Tuve un caso donde el escaneo de seguridad bloqueaba el pipeline por vulnerabilidades en la imagen base sin parche disponible. El dilema era: bloquear indefinidamente o aceptar riesgo. La solución fue configurar el escaneo como reporteo sin bloqueo, documentar la decisión de riesgo con justificación, y crear un proceso de revisión semanal. Cuando salió el parche, lo aplicamos inmediatamente."

## Cuando pregunten sobre seguridad

> "Implemento shift-left security: escaneo de contenedores antes de push, análisis estático de código, y Dependabot para dependencias. En Kubernetes uso Network Policies para microsegmentación - por ejemplo, solo ciertos pods pueden hablar con la base de datos. También aplico Pod Security Standards para evitar contenedores privilegiados."

---

# ✅ CHECKLIST FINAL DE CONOCIMIENTO

Para cada tema, pregúntate: ¿Puedo explicar el por qué, no solo el cómo?

## Terraform
- [ ] ¿Por qué usar remote backend?
- [ ] ¿Cuál es la diferencia entre variables y locals?
- [ ] ¿Por qué Managed Identity en vez de service principal con password?
- [ ] ¿Qué es el state locking y por qué importa?

## Docker
- [ ] ¿Por qué multi-stage build?
- [ ] ¿Por qué usuario no-root?
- [ ] ¿Por qué copiar requirements.txt antes que el código?
- [ ] ¿Cuál es la diferencia entre ENTRYPOINT y CMD?

## Kubernetes
- [ ] ¿Cuál es la diferencia entre Pod, Deployment y ReplicaSet?
- [ ] ¿Cuándo usar cada tipo de Service?
- [ ] ¿Cuál es la diferencia entre liveness y readiness probes?
- [ ] ¿Qué son requests vs limits?
- [ ] ¿Para qué sirve un PodDisruptionBudget?

## CI/CD
- [ ] ¿Por qué OIDC es mejor que passwords en secrets?
- [ ] ¿Por qué escanear antes de push, no después?
- [ ] ¿Cómo fluye un cambio desde commit hasta producción?

## DevSecOps
- [ ] ¿Qué significa shift-left security?
- [ ] ¿Qué detecta Trivy vs CodeQL vs Dependabot?
- [ ] ¿Por qué usar Network Policies?

---

# 📁 ARCHIVOS CREADOS EN ESTA GUÍA

```
docs/
├── MASTER_GUIDE_PART1.md    # Intro + Terraform básico
├── MASTER_GUIDE_PART2.md    # Terraform red/AKS + Docker
├── MASTER_GUIDE_PART3.md    # Kubernetes profundo
├── MASTER_GUIDE_PART4.md    # Kustomize, CI/CD, DevSecOps
└── MASTER_GUIDE_PART5.md    # Problemas + Cómo explicar (este archivo)
```

---

**Recuerda**: En una entrevista técnica, lo que buscan es:
1. Que entiendas los CONCEPTOS, no solo los comandos
2. Que puedas explicar el POR QUÉ de las decisiones
3. Que hayas resuelto problemas reales
4. Que puedas comunicar claramente

¡Buena suerte! 🚀
