# Runbook — cierre verificable de Semana 1 (ISS-S1-010, 012 y 014)

Este runbook ejecuta las pruebas Azure que faltan sin aceptar advertencias como éxito.
El cierre comprende Queue Storage, alta disponibilidad, destrucción, reconstrucción,
despliegue de la aplicación, validaciones y limpieza final.

## Advertencias obligatorias

1. `test-destroy-rebuild-cleanup.sh` elimina **todo el Resource Group confirmado**, lo
   reconstruye y finalmente vuelve a eliminarlo. No lo ejecutes sobre un RG que contenga
   recursos de Semana 2 que deban conservarse.
2. Storage tiene acceso público deshabilitado. El ejecutor debe tener conectividad con la
   VNet: una VM/jumpbox conectada o Cloud Shell inyectado en la VNet. Cloud Shell público
   normal no demuestra el flujo privado.
3. El token `SERVICE` se pasa por variable de sesión o mediante un comando que lo genere.
   Nunca se guarda en `.env`, logs ni evidencias.
4. El cierre debe ejecutarse sobre una rama basada en la entrega estable de Semana 1 para
   que `mvn clean verify` no quede bloqueado por trabajo incompleto de semanas posteriores.

## 1. Preparar parámetros

```bash
chmod +x scripts/*.sh scripts/tests/*.sh

export SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export LOCATION="eastus2"
export RESOURCE_GROUP="rg-centinela-week1-cierre"
export NAME_PREFIX="cent"
export APP_SERVICE_SKU="S1"
az account set --subscription "$SUBSCRIPTION_ID"
```

Usa un RG exclusivo y desechable para la prueba final. El nombre usado en
`--confirm-resource-group` debe coincidir exactamente con `RESOURCE_GROUP`.

## 2. Proporcionar el token SERVICE

Opción A, token vigente solo en memoria:

```bash
export CENTINELA_SERVICE_TOKEN="<bearer-service-sin-prefijo-Bearer>"
```

Opción B, comando local que imprime un token nuevo después del despliegue:

```bash
export CENTINELA_SERVICE_TOKEN_COMMAND='bash /ruta/privada/obtener-token-service.sh'
```

El comando no debe imprimir mensajes adicionales: únicamente el token.

## 3. Ejecutar el cierre completo

```bash
bash scripts/tests/test-destroy-rebuild-cleanup.sh \
  --confirm-resource-group "$RESOURCE_GROUP"
```


Si la App Registration `${NAME_PREFIX}-api-week1` ya es utilizada por Semana 2, conserva
solo ese recurso tenant-level y documenta la excepción:

```bash
bash scripts/tests/test-destroy-rebuild-cleanup.sh \
  --confirm-resource-group "$RESOURCE_GROUP" \
  --keep-entra-final
```

El Resource Group se elimina igualmente. No uses esta opción para ocultar una limpieza
pendiente; su propósito es no romper una identidad compartida que sigue activa.

El orquestador realiza en orden:

1. inventario y destrucción inicial con espera verificable;
2. reconstrucción completa de Semana 1;
3. `mvn clean verify`;
4. despliegue del artefacto al slot y swap a producción;
5. health check y validadores de Storage, App Service, red, Entra, RBAC,
   Managed Identity, documentación y alcance;
6. roles temporales mínimos para Queue y Blob;
7. roundtrip de Queue en staging y producción;
8. prueba HA con reconciliación de cada HTTP `202` contra Blob;
9. revocación de los roles creados por la prueba;
10. comprobación de una instancia final y eliminación completa del RG; Entra también
    se elimina salvo la excepción explícita `--keep-entra-final`.

Las evidencias se guardan en:

- `docs/evidence/queue/run-*/`
- `docs/evidence/ha/run-*/`
- `docs/evidence/final/run-drc-*/`

## 4. Ejecuciones aisladas para diagnóstico

Queue, desde un ejecutor conectado a la VNet y con roles `Storage Queue Data Message
Sender` y `Storage Queue Data Message Processor`:

```bash
export STAGING_STORAGE_ACCOUNT="<storage-account>"
export PRODUCTION_STORAGE_ACCOUNT="<storage-account>"
bash scripts/validate-queue.sh staging
bash scripts/validate-queue.sh production
```

Alta disponibilidad, con token SERVICE y permiso temporal `Storage Blob Data Contributor`
sobre `raw-transactions-production` para reconciliar y limpiar datos sintéticos:

```bash
export CENTINELA_API_BASE_URL="https://<webapp>.azurewebsites.net"
export CENTINELA_STORAGE_ACCOUNT="<storage-account>"
export CENTINELA_RAW_TRANSACTIONS_CONTAINER="raw-transactions-production"
bash scripts/test-ha.sh
```

## 5. Criterio de aprobación

El cierre solo pasa cuando todos los comandos terminan con código `0`, las dos colas no
conservan el mensaje técnico de la corrida, todos los `202` de HA tienen Blob, la capacidad
queda en `1`, los roles temporales creados se revocan y el Resource Group final no existe.
La App Registration también se elimina, salvo una excepción `--keep-entra-final` registrada.
Antes de versionar evidencia se ejecuta `bash scripts/tests/scan-repository.sh` y se revisa
que no haya tokens, secretos, connection strings o identificadores no sanitizados.
