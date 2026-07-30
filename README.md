# Centinela

Motor de detección de fraude transaccional sobre Azure: ingesta desacoplada por eventos,
scoring por reglas con historial por cuenta, casos con auditoría inmutable, explicaciones
deterministas y trazabilidad de extremo a extremo.

```
cliente ──► API (Container App) ──► Blob crudo ──► Event Grid ──► Motor de scoring
                 │ 202 inmediato                                      │ reglas + historial (Cosmos)
                 │                                                    ▼
            API de consulta ◄── PostgreSQL (casos) ◄── consumidor ◄── Storage Queue
                                      ▲
                            explicador (asíncrono, escala a cero)
```

El cliente recibe su acuse **antes** de que exista ningún análisis; todo lo demás ocurre
detrás, de forma asíncrona y trazada con contexto W3C que viaja **dentro de los mensajes**.

> **Toda la documentación del sistema está consolidada en [`GUIA_TECNICA.md`](GUIA_TECNICA.md)**:
> arquitectura, componentes, relación con el banco de pruebas, despliegue desde cero,
> CI/CD, pruebas y operación. Este README es solo el arranque rápido.

---

## Requisitos

| Para | Necesitas |
|---|---|
| Entorno local | Docker Desktop (Compose v2) y Bash (Git Bash en Windows) |
| Desarrollo | Java 21, Maven 3.9+ |
| Despliegue en Azure | Azure CLI con sesión activa, `psql`, y un `.env` (ver `.env.example`) |

---

## Inicio rápido — entorno local (un comando)

```bash
bash start.sh      # levanta todo y espera a que la API responda
bash stop.sh       # desmonta todo: contenedores, red y volúmenes
```

Levanta Azurite (Blob + Queue), PostgreSQL, Mongo (doble local de Cosmos), la **API** en
`http://localhost:8080` y el **explicador**. En el perfil local no hay autenticación —
`LocalSecurityConfiguration` lo anuncia a gritos en el log y documenta sus salvaguardas.

### Flujo completo en local

```bash
# 1. Ingresar una transacción (responde 202 al instante)
curl -X POST http://localhost:8080/api/v1/transactions \
  -H "Content-Type: application/json" \
  -d '{"transactionId":"tx-demo-1","accountId":"acc-1","amount":4200000,"currency":"COP",
       "occurredAt":"2026-07-29T12:00:00Z",
       "location":{"countryCode":"ES","city":"Madrid","latitude":40.41,"longitude":-3.70},
       "merchant":{"name":"Joyería Serrano","category":"jewelry"}}'

# 2. Simular el tramo que no existe en local (Event Grid + motor)
bash scripts/local/simulate-scoring.sh tx-demo-1

# 3. Consultar el caso con su explicación
curl http://localhost:8080/api/v1/cases/tx-demo-1
```

**Límite declarado:** no existe emulador local de Event Grid, así que el salto API → motor
se simula. El simulador reproduce exactamente los dos efectos observables del motor
(registro de scoring + mensaje `flagged-case-v1`), pero **no ejecuta las reglas** — la
detección se valida con las suites del motor (`scoring-function/`).

---

## Despliegue en Azure (un comando)

```bash
cp .env.example .env     # completar SUBSCRIPTION_ID, LOCATION, RESOURCE_GROUP, NAME_PREFIX
az login
CENTINELA_ALERT_EMAIL="tu@correo" bash scripts/deploy-platform.sh --yes --with-lab
```

Aprovisiona la infraestructura completa (red privada, Storage, Cosmos, PostgreSQL,
Key Vault, Event Grid, identidades, Entra, ACR, Container Apps), construye las imágenes
**dentro de Azure** (`az acr build`, sin Docker local), despliega las tres aplicaciones y
el banco de pruebas, y verifica la salud. Es idempotente: si un paso falla, se corrige la
causa y se vuelve a ejecutar. El paso a paso comentado, los requisitos y la configuración
del CI/CD están en [`GUIA_TECNICA.md` §12](GUIA_TECNICA.md#12-despliegue-desde-cero).

### Control de crédito

```bash
bash scripts/shutdown-daily.sh          # apaga lo que factura por tiempo
bash scripts/shutdown-daily.sh --start  # lo enciende de vuelta
bash scripts/destroy-week1.sh --wait    # elimina todo el grupo de recursos
```

---

## CI/CD

GitHub Actions con **OIDC federado — cero credenciales almacenadas**:

- `.github/workflows/ci.yml` — construcción y pruebas de los dos módulos, barrido de
  secretos (árbol **y** historial de Git), shellcheck bloqueante.
- `.github/workflows/cd.yml` — al integrar a `main`: pruebas → imágenes → verificación de
  secretos capa por capa → publicación en ACR → despliegue → sonda de salud. Interruptor:
  variable de repositorio `AZURE_DEPLOY_ENABLED=true`.

Aprovisionamiento de la identidad del pipeline (una vez, para ambos repositorios):

```bash
CENTINELA_GITHUB_REPO="Centinela-App/Centinela,Centinela-App/centinela-lab" \
  bash scripts/provision-github-oidc.sh
```

---

## Verificación

```bash
bash scripts/verify/verify-deployment-health.sh   # ¿responde de verdad?
bash scripts/verify/run-e2e-fraud.sh              # transacción → caso, extremo a extremo
bash scripts/verify/verify-trace.sh <txId>        # traza individual con tiempos por etapa
bash scripts/verify/verify-practices.sh           # estructura, migraciones, secretos
```

---

## Estructura del repositorio

```
src/                    aplicación principal (hexagonal: domain / application / infrastructure)
  ├─ transactioningestion/   ingesta y publicación del evento
  ├─ casemanagement/         casos, auditoría inmutable, consumidor de cola
  ├─ caseexplanation/        explicador determinista por plantilla
  ├─ caseinquiry/            API de consulta (análisis y caso)
  ├─ documentstorage/        carga de documentos
  ├─ documentverification/   extracción con manejo de fallos
  ├─ scoringrecord/          lectura del registro del motor (Cosmos)
  └─ shared/                 contratos, traza W3C, telemetría por etapas
scoring-function/       motor de scoring (Azure Functions en contenedor, módulo independiente)
scripts/                aprovisionamiento, despliegue, verificación y apagado
docs/contracts/         contratos ejecutables: OpenAPI y esquemas de mensajería
GUIA_TECNICA.md         LA guía: arquitectura, despliegue, CI/CD, pruebas y operación
docker-compose.yml      entorno local completo
Dockerfile              imagen multietapa de la aplicación (la misma para API y explicador)
```

La app de pruebas (un botón por causal de alerta) vive en un **repositorio aparte**:
[`centinela-lab`](https://github.com/Centinela-App/centinela-lab) — cliente externo puro,
sin código compartido.
