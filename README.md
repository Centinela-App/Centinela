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

### Ensayo del escenario de fallo (obligatorio en la sustentación)

```bash
docker compose stop explainer    # los casos siguen abriéndose, en estado PENDING
docker compose start explainer   # el backlog pendiente se explica solo
```

---

## Despliegue en Azure

La guía completa y reproducible es
[`docs/4_Infraestructura_y_Despliegue/5_Runbook_Despliegue_Completo.md`](docs/4_Infraestructura_y_Despliegue/5_Runbook_Despliegue_Completo.md).
Resumen del orden para la topología final (Container Apps, sin App Service — ver `ADR-009`):

```bash
cp .env.example .env                                   # completar valores
bash scripts/provision-network-containerapps.sh        # VNet + subredes + DNS privado
bash scripts/provision-cosmos.sh                       # almacén de transacciones (PE)
bash scripts/provision-postgres.sh                     # almacén de casos (PE)
bash scripts/provision-keyvault.sh                     # secretos
bash scripts/provision-containerapps-identity.sh       # identidad de datos + roles
bash scripts/provision-eventgrid.sh --publisher-principal <oid> \
     --consumer-principal <oid> --function-principal <oid>
bash scripts/provision-entra-app.sh                    # registro OAuth2 + app roles
bash scripts/configure-postgres-managed-identity.sh    # principal de BD (ventana temporal)
bash scripts/provision-container-registry.sh           # ACR + pull sin credenciales
bash scripts/provision-container-apps.sh               # entorno integrado a la VNet
bash scripts/provision-observability.sh                # App Insights + alerta
bash scripts/deploy-containers.sh --tag <sha>          # las tres aplicaciones
bash scripts/verify/verify-deployment-health.sh        # ¿responde de verdad?
```

Todos los scripts son idempotentes y admiten `--validate-only` donde crear tiene costo.
**No existe ninguna credencial en el repositorio**: Managed Identity para datos, OIDC
federado para el pipeline, Key Vault para lo inevitablemente secreto.

### Control de crédito

```bash
bash scripts/shutdown-daily.sh          # apaga lo que factura por tiempo
bash scripts/shutdown-daily.sh --start  # lo enciende de vuelta
```

---

## CI/CD

GitHub Actions con **OIDC federado — cero credenciales almacenadas** (`ADR-008`):

- `.github/workflows/ci.yml` — construcción, pruebas de los dos módulos, barrido de
  secretos (árbol **y** historial de Git), shellcheck. Sin acceso a ninguna credencial:
  un *fork* malicioso no obtiene nada.
- `.github/workflows/cd.yml` — al integrar a `main`: pruebas → imágenes → verificación de
  secretos **capa por capa** → publicación en ACR → despliegue → sonda de salud. El
  encadenamiento con `needs` garantiza que una prueba fallida detiene todo antes de que
  exista imagen alguna.

Aprovisionamiento de la identidad del pipeline: `bash scripts/provision-github-oidc.sh`.

### Activar el despliegue automático

Las etapas de `cd.yml` que tocan Azure están detrás de un interruptor, para que un
*merge* a `main` sin OIDC configurado ejecute CI y se detenga limpio en lugar de fallar.
Para activarlo, una sola vez, tras registrar los *secrets* que imprime
`provision-github-oidc.sh`:

```
# Settings → Secrets and variables → Actions → Variables
AZURE_DEPLOY_ENABLED = true
```

Desde ese momento, cada integración a `main` despliega sola. Para un primer despliegue
controlado antes de activarlo, usa el disparo manual (`workflow_dispatch`), que ignora el
interruptor a propósito.

---

## Verificación

```bash
bash scripts/verify/verify-practices.sh          # estructura, migraciones, instrumentación, secretos
bash scripts/tests/capture-week3-evidence.sh     # evidencia reproducible por issue
bash scripts/verify/verify-trace.sh <txId>       # traza individual con tiempos por etapa
bash scripts/verify/verify-scaling.sh            # réplicas bajo carga, en vivo
bash scripts/verify/verify-explainer-correspondence.sh <txId>
```

Además, siete agentes de auditoría en `.claude/agents/` (`verify-infra`, `verify-secrets`,
`verify-containers`, `verify-cicd`, `verify-observability`, `verify-explainer`,
`verify-practices`) que ejecutan estos mismos scripts y emiten veredicto razonado — el
veredicto siempre se apoya en salida de comando reproducible sin IA.

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
docs/                   requisitos, arquitectura, ADR, issues, evidencias, consultas KQL
docker-compose.yml      entorno local completo
Dockerfile              imagen multietapa de la aplicación (la misma para API y explicador)
```

La app de pruebas (un botón por causal de alerta) vive en un **repositorio aparte**:
[`centinela-lab`](../centinela-lab) — cliente externo puro, sin código compartido.

## Documentación clave

| Documento | Qué contiene |
|---|---|
| `docs/2_Arquitectura/2_ADR_Decisiones_Arquitectura.md` | Las 14 decisiones, cerradas, con sus contrapartidas |
| `docs/5_Issues_y_Trazabilidad/7_Historias_Issues_Semana3.md` | Backlog de la semana 3 con estados reales |
| `docs/observabilidad/consultas-kql.md` | Las cinco preguntas de operación, ejecutables |
| `docs/evidence/INDEX-semana3.md` | Cómo se genera y lee la evidencia |
| `docs/SECURITY-remediacion-env-leak.md` | Historial de incidentes de secretos y su remediación |
