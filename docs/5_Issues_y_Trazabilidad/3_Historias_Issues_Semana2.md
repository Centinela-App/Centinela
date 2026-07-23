# 07 — Backlog implementable de Semana 2

## Propósito

Este documento traduce `0_Vision/4_Alcance_Semana2.md` a **14 issues implementables**, con la
misma estructura que Semana 1: descripción técnica, archivos, criterios de aceptación, pruebas
por nivel, Gherkin, Definition of Done, comandos y evidencia.

No autoriza contenedores, CI/CD, IA, explicador de casos ni observabilidad instrumentada
(alcance de Semana 3).

### Stack fijado por la célula

- Almacén no relacional: **Cosmos DB for MongoDB** · Almacén relacional: **PostgreSQL Flexible Server**
- Evento: **Event Grid** · Cola de casos: **Storage Queue** (reutiliza Semana 1)
- Motor de scoring: **Azure Functions (Java)** · Secretos: **Key Vault** · Rate limiting: **en la app**

## Distribución consecutiva para cinco personas

| Persona | Issues asignadas | Entrega principal | Puede depender de |
|---|---|---|---|
| Persona 1 | `ISS-S2-001` a `ISS-S2-003` | Almacenes de datos y Key Vault | Semana 1 completa. |
| Persona 2 | `ISS-S2-004` a `ISS-S2-006` | Contratos, mensajería e integración de la API | Semana 1 + `001–003`. |
| Persona 3 | `ISS-S2-007` a `ISS-S2-009` | Motor de scoring serverless | `001`, `003`, `004`, `005`. |
| Persona 4 | `ISS-S2-010` a `ISS-S2-011` | Almacén de casos y consumidor | `002`, `003`, `005`. |
| Persona 5 | `ISS-S2-012` a `ISS-S2-014` | Pipeline E2E, desacoplamiento, costos y cierre | `001–011`. |

La asignación es consecutiva para reducir conflictos. Persona 5 también realiza revisión
cruzada durante la semana.

### Regla obligatoria de dependencias

- Ninguna issue puede depender de una issue con número mayor.
- Un archivo compartido se modifica solo después del traspaso del bloque anterior.
- Las pruebas posteriores de integración no convierten una issue futura en dependencia para
  iniciar o cerrar una issue temprana.

## Jerarquía del backlog

### EPIC-S2-001 — Motor de scoring y arquitectura orientada a eventos

Objetivo: puntuar cada transacción contra su historial y abrir casos de fraude de forma
**automática y desacoplada**, sin que el cliente espere por el análisis.

| Feature | Historia | Resultado de negocio | Issues |
|---|---|---|---|
| FEAT-S2-001 Almacenes de datos | HU-S2-001 Como equipo quiero el almacén correcto para cada tipo de dato. | Escala y trazabilidad. | ISS-S2-001, 002, 010 |
| FEAT-S2-002 Motor de scoring | HU-S2-002 Como sistema quiero puntuar cada transacción por evento. | Detección automática. | ISS-S2-007, 008, 009 |
| FEAT-S2-003 Mensajería desacoplada | HU-S2-003 Como equipo quiero separar ingesta de análisis. | Resiliencia y no-bloqueo. | ISS-S2-004, 005, 011 |
| FEAT-S2-004 Integración y protección de la API | HU-S2-004 Como equipo quiero publicar el evento y proteger la ingesta. | Pipeline y control de costo. | ISS-S2-006 |
| FEAT-S2-005 Seguridad y cierre | HU-S2-005 Como equipo quiero cero secretos y control de crédito. | Seguridad y costo. | ISS-S2-003, 012, 013, 014 |

## Mapa de ejecución

| ID | Persona | Título | Dependencias para iniciar | Resultado verificable |
|---|---|---|---|---|
| ISS-S2-001 | 1 | Provisionar Cosmos DB for MongoDB (partición, consistencia, TTL) | Semana 1 | Almacén de transacciones con clave de partición y TTL. |
| ISS-S2-002 | 1 | Provisionar PostgreSQL Flexible Server privado + respaldo | Semana 1 | Servidor relacional aislado de internet. |
| ISS-S2-003 | 1 | Provisionar Key Vault + migrar secretos + auditar historial | ISS-S2-001, 002 | Cero secretos; acceso por Managed Identity. |
| ISS-S2-004 | 2 | Definir contratos de evento y de mensaje de caso | Semana 1 (ISS-S1-007) | Esquemas versionados y validados. |
| ISS-S2-005 | 2 | Provisionar Event Grid + cola de casos | Semana 1, ISS-S2-004 | Tópico + suscripción + cola de casos. |
| ISS-S2-006 | 2 | Publicar evento en la API + limitación de tasa | ISS-S2-003, 004, 005 | Evento publicado tras persistir; `429` al exceder. |
| ISS-S2-007 | 3 | Esqueleto de la Function + lectura de historial por cuenta | ISS-S2-001, 003, 005 | Function por evento que lee una sola partición. |
| ISS-S2-008 | 3 | Cuatro reglas + umbral configurable + detalle de activación | ISS-S2-007 | Reglas evaluadas; umbral sin redespliegue. |
| ISS-S2-009 | 3 | Persistir score y publicar caso si supera umbral | ISS-S2-007, 008 | Score en Cosmos; caso encolado. |
| ISS-S2-010 | 4 | Esquema relacional de casos con auditoría | ISS-S2-002, 003 | Modelo Caso/Estado/Asignación/Resolución/Auditoría. |
| ISS-S2-011 | 4 | Consumidor de la cola de casos (idempotente) | ISS-S2-005, 010 | Caso insertado + auditoría; procesa backlog. |
| ISS-S2-012 | 5 | Pipeline de extremo a extremo | ISS-S2-006, 009, 011 | Transacción → score → caso, sin intervención. |
| ISS-S2-013 | 5 | Prueba de desacoplamiento y de umbral | ISS-S2-006, 009, 011 | Consumidor caído sin pérdida; umbral en caliente. |
| ISS-S2-014 | 5 | Reporte de crédito + ADR + cierre documental | ISS-S2-001..013 | Crédito < 40 USD; decisiones documentadas. |

## Tipos de prueba utilizados

- **Estático:** estructura, contrato, secretos, documentación y alcance.
- **Unitario:** una clase/función aislada con mocks/fakes.
- **Contrato:** coherencia de esquemas de evento/mensaje y persistencia.
- **Integración:** interacción entre componentes o con un recurso real controlado.
- **E2E:** recorrido completo sobre el pipeline desplegado.

---

## ISS-S2-001 — Provisionar Cosmos DB for MongoDB (partición, consistencia, TTL)

### Metadatos

- **Historia:** HU-S2-001 · **Feature:** FEAT-S2-001
- **Responsable principal:** Persona 1 · **Revisor:** Persona 3
- **Dependencias para iniciar:** Semana 1 completa (Resource Group, red, scripts base)
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S2-001
- **Requisitos:** RD-S2-001, RD-S2-002, RD-S2-003, RNF-S2-002
- **Pruebas catalogadas:** TEST-S2-001, TEST-S2-024, TEST-S2-025

### 1. Objetivo

Aprovisionar una cuenta **Cosmos DB for MongoDB** (nivel gratuito) con la colección de
transacciones, su **clave de partición**, el **nivel de consistencia** y la **política de
expiración (TTL)** definidos antes de la primera escritura.

### 2. Contexto y razón técnica

La clave de partición **no admite modificación posterior sin migración completa**. La consulta
dominante es "obtener las transacciones recientes de una cuenta". Elegir mal la partición hace
que esa consulta recorra varias particiones y falle en volumen aunque funcione en pruebas.

### 3. Descripción técnica

- Crear una cuenta Cosmos DB (API MongoDB) con **Free Tier** habilitado, en la misma región.
- Crear la base `centinela` y la colección `transactions`.
- Definir la **shard key** = `accountId` (agrupa el historial de una cuenta en una partición).
- Configurar el **nivel de consistencia** de cuenta y justificar la elección (ver §13).
- Configurar **TTL** en la colección alineado a la ventana más larga de las reglas (documentar
  el periodo elegido; p. ej. cubrir la ventana de "monto atípico"/"velocidad" + margen).
- Deshabilitar acceso público del data plane donde el nivel gratuito lo permita; en caso
  contrario, restringir por red/firewall a la subred de la aplicación (documentar la limitación).
- Idempotente: reejecutar converge al mismo estado sin duplicar recursos.
- **No** escribir datos de negocio ni definir el modelo de score (eso es ISS-S2-009).

### 4. Fuera de alcance

- Adaptador Java de lectura/escritura (ISS-S2-007/009).
- Modelo de score y detalle de activación (ISS-S2-008/009).
- Cambiar la clave de partición después de la primera escritura.

### 5. Archivos que deben crearse

```text
scripts/provision-cosmos.sh
scripts/tests/validate-cosmos.sh
docs/evidence/iss-s2-001/.gitkeep
```

### 6. Archivos que pueden modificarse

```text
scripts/deploy-week2.sh (registrar el paso)
scripts/destroy-week1.sh (solo si requiere limpieza específica; el RG ya cubre el borrado)
docs/2_Arquitectura/2_ADR_Decisiones_Arquitectura.md (agregar ADR de partición/consistencia/TTL)
```

### 7. Archivos prohibidos

```text
cualquier connection string o key de Cosmos versionada
scripts que fijen región o SKU rígidos fuera de parámetros
```

### 8. Criterios de aceptación

- [ ] Existe una cuenta Cosmos (API MongoDB) con Free Tier habilitado.
- [ ] La colección `transactions` usa `accountId` como shard key.
- [ ] El nivel de consistencia está configurado y justificado por escrito.
- [ ] El TTL está configurado y su periodo justificado en función de las ventanas de reglas.
- [ ] Reejecutar el script no duplica recursos.

### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S2-001` | Obligatoria para cerrar | Integración | Datos | Validar cuenta, shard key, consistencia y TTL |
| `TEST-S2-024` | Posterior de integración | E2E | Costo | Verificar que se mantiene en nivel gratuito |
| `TEST-S2-025` | Posterior de integración | Estático | Documentación | ADR de partición/consistencia/TTL presente |

### 10. Escenarios Gherkin

```gherkin
Escenario: Colección con shard key correcta
  Dado una cuenta Cosmos for MongoDB en nivel gratuito
  Cuando se ejecuta provision-cosmos.sh
  Entonces existe la colección transactions con shard key accountId y TTL configurado

Escenario: Reejecución idempotente
  Dado los recursos ya existen con la configuración aprobada
  Cuando se reejecuta el script
  Entonces termina sin duplicar recursos

Escenario: Partición inmutable
  Dado la colección ya tiene datos
  Cuando se intenta cambiar la shard key
  Entonces la operación se rechaza y se documenta la necesidad de migración
```

### 11. Definition of Done específica

- [ ] Criterios de aceptación demostrados.
- [ ] Solo archivos autorizados creados/modificados.
- [ ] Pruebas obligatorias disponibles pasaron.
- [ ] Evidencia reproducible y sanitizada (sin keys ni connection strings).
- [ ] ADR de partición/consistencia/TTL redactado.
- [ ] Revisión cruzada aprobada.

### 12. Comandos de validación

```bash
bash -n scripts/provision-cosmos.sh scripts/tests/validate-cosmos.sh
./scripts/provision-cosmos.sh
./scripts/tests/validate-cosmos.sh
```

### 13. Evidencia esperada

- Salida de creación de cuenta/colección (sanitizada).
- Configuración de shard key, consistencia y TTL.
- ADR con: qué consulta optimiza `accountId`, cuál sacrifica, y por qué se descartó particionar
  por `transactionId` o por fecha.

### 14. Instrucción para una IA o integrante

Antes de implementar, resumir objetivo, dependencias, archivos, criterios, pruebas, riesgos y
fuera de alcance. Después, listar archivos modificados, pruebas ejecutadas, evidencias y
desviaciones. No declarar `DONE` solo por código escrito.

---

## ISS-S2-002 — Provisionar PostgreSQL Flexible Server privado + respaldo

### Metadatos

- **Historia:** HU-S2-001 · **Feature:** FEAT-S2-001
- **Responsable principal:** Persona 1 · **Revisor:** Persona 4
- **Dependencias para iniciar:** Semana 1 completa (VNet, `snet-private-endpoints`)
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S2-002
- **Requisitos:** RD-S2-005, RD-S2-006, RNF-S2-002
- **Pruebas catalogadas:** TEST-S2-002, TEST-S2-024

### 1. Objetivo

Aprovisionar un **PostgreSQL Flexible Server** (nivel gratuito) accesible **solo desde la VNet**
(Private Endpoint o integración de VNet), con estrategia de respaldo documentada.

### 2. Contexto y razón técnica

Los casos de fraude requieren integridad referencial, transacciones ACID y trazabilidad legal.
El requisito no negociable de Semana 1 (almacenes no alcanzables desde internet) aplica aquí.

### 3. Descripción técnica

- Crear el servidor PostgreSQL Flexible Server con SKU **Burstable B1ms** (free) y storage mínimo.
- **Networking privado**: acceso privado por Private Endpoint/inyección de VNet en la subred
  de la app; **acceso público deshabilitado**.
- Vincular la zona DNS privada del servicio para resolución interna.
- Preferir **autenticación Entra ID / Managed Identity** para la app (sin password de conexión).
  Si se requiere admin password inicial, guardarlo en Key Vault (ISS-S2-003), nunca en el repo.
- Documentar la **estrategia de respaldo**: periodicidad, retención (según free tier) y RPO.
- Idempotente y con tags de trazabilidad.
- **No** crear tablas ni el esquema de casos (eso es ISS-S2-010).

### 4. Fuera de alcance

- Modelo de datos y migraciones (ISS-S2-010).
- Consumidor de casos (ISS-S2-011).

### 5. Archivos que deben crearse

```text
scripts/provision-postgres.sh
scripts/tests/validate-postgres.sh
docs/evidence/iss-s2-002/.gitkeep
docs/4_Infraestructura_y_Despliegue/3_Estrategia_Respaldo.md
```

### 6. Archivos que pueden modificarse

```text
scripts/deploy-week2.sh
scripts/provision-network.sh (solo si requiere una subred/zona DNS adicional)
```

### 7. Archivos prohibidos

```text
password o connection string de Postgres versionada
apertura de acceso público del servidor
```

### 8. Criterios de aceptación

- [ ] El servidor existe en SKU de nivel gratuito.
- [ ] `public network access` deshabilitado; solo alcanzable desde la subred de la app.
- [ ] Zona DNS privada vinculada y resolución interna verificada.
- [ ] Estrategia de respaldo documentada (periodicidad, retención, RPO).
- [ ] Ninguna credencial versionada.

### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S2-002` | Obligatoria para cerrar | Integración | Red y datos | Validar servidor privado y resolución DNS |
| `TEST-S2-024` | Posterior de integración | E2E | Costo | Verificar nivel gratuito |

### 10. Escenarios Gherkin

```gherkin
Escenario: Servidor privado operativo
  Dado la VNet de Semana 1
  Cuando se ejecuta provision-postgres.sh
  Entonces el servidor existe sin acceso público y resuelve por DNS privado

Escenario: Acceso público bloqueado
  Dado el servidor desplegado
  Cuando se intenta conectar desde fuera de la VNet
  Entonces la conexión es rechazada

Escenario: Respaldo documentado
  Dado el servidor creado
  Cuando se revisa la documentación
  Entonces existen periodicidad, retención y RPO definidos
```

### 11. Definition of Done específica

- [ ] Criterios demostrados; solo archivos autorizados.
- [ ] Pruebas obligatorias pasaron; evidencia sanitizada.
- [ ] Estrategia de respaldo redactada.
- [ ] Revisión cruzada aprobada.

### 12. Comandos de validación

```bash
bash -n scripts/provision-postgres.sh scripts/tests/validate-postgres.sh
./scripts/provision-postgres.sh
./scripts/tests/validate-postgres.sh
```

### 13. Evidencia esperada

- Propiedades del servidor (sanitizadas): SKU, `publicNetworkAccess=Disabled`.
- Prueba de resolución DNS privada y de conexión rechazada desde internet.
- Documento de respaldo.

### 14. Instrucción para una IA o integrante

Resumir antes; reportar archivos, pruebas, evidencias y desviaciones después. No declarar
`DONE` solo por código escrito.

---

## ISS-S2-003 — Provisionar Key Vault + migrar secretos + auditar historial

### Metadatos

- **Historia:** HU-S2-005 · **Feature:** FEAT-S2-005
- **Responsable principal:** Persona 1 · **Revisor:** Persona 5
- **Dependencias para iniciar:** ISS-S2-001, ISS-S2-002
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S2-001
- **Requisitos:** RS-S2-001, RS-S2-002
- **Pruebas catalogadas:** TEST-S2-003, TEST-S2-026

### 1. Objetivo

Crear un **Azure Key Vault**, migrar a él toda cadena de conexión/clave requerida por Semana 2,
otorgar acceso por **Managed Identity**, y **auditar el historial de git** para confirmar
ausencia de secretos.

### 2. Contexto y razón técnica

Semana 1 difirió Key Vault (ADR-005) por no existir secretos inevitables. Cosmos for MongoDB
requiere una key/connection string: ahora **sí** existe un secreto real, por lo que Key Vault
se crea. La app se autentica al vault por identidad gestionada (no hay "credencial para obtener
credenciales").

### 3. Descripción técnica

- Crear el Key Vault (RBAC data plane) con soft-delete y purge protection.
- Guardar como secretos: la key/connection string de Cosmos y, si aplica, credenciales de
  Postgres/Event Grid. Preferir Managed Identity siempre que el servicio lo soporte.
- Otorgar **`Key Vault Secrets User`** a las identidades gestionadas de la Web App, el slot y
  la Function.
- Configurar la app para leer secretos por referencia a Key Vault (App Settings `@Microsoft.KeyVault(...)`)
  o por SDK con `DefaultAzureCredential`.
- **Auditar el historial de git** con `gitleaks` y `scan-repository.sh`; remediar cualquier
  hallazgo (ver `docs/SECURITY-remediacion-env-leak.md`).
- Actualizar `assign-rbac.sh` con los roles nuevos.

### 4. Fuera de alcance

- Reescritura del historial de git (procedimiento coordinado aparte, ya documentado).
- Lógica de negocio que consume los secretos (issues de sus dueños).

### 5. Archivos que deben crearse

```text
scripts/provision-keyvault.sh
scripts/tests/validate-keyvault.sh
scripts/tests/audit-git-secrets.sh
docs/evidence/iss-s2-003/.gitkeep
```

### 6. Archivos que pueden modificarse

```text
scripts/assign-rbac.sh
scripts/deploy-week2.sh
src/main/resources/application.yml (referencias a Key Vault, sin valores)
docs/2_Arquitectura/2_ADR_Decisiones_Arquitectura.md (revisar/derogar ADR-005)
```

### 7. Archivos prohibidos

```text
cualquier secreto en texto plano en repo o variables manuales
un secreto para autenticarse contra Key Vault (debe ser Managed Identity)
```

### 8. Criterios de aceptación

- [ ] Existe el Key Vault con soft-delete/purge protection.
- [ ] Los secretos de Semana 2 viven en el vault, no en el repo.
- [ ] Web App, slot y Function acceden por Managed Identity (rol Secrets User).
- [ ] `scan-repository.sh` y `audit-git-secrets.sh` salen limpios (o con remediación registrada).
- [ ] No existe ninguna credencial para obtener credenciales.

### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S2-003` | Obligatoria para cerrar | Integración | Seguridad | Validar Key Vault + acceso por Managed Identity |
| `TEST-S2-026` | Obligatoria para cerrar | Estático | Seguridad | Auditar historial de git sin secretos |

### 10. Escenarios Gherkin

```gherkin
Escenario: Acceso por identidad gestionada
  Dado el Key Vault y la Managed Identity de la app
  Cuando la app solicita un secreto
  Entonces lo obtiene sin usar ninguna credencial almacenada

Escenario: Historial sin secretos
  Dado el repositorio completo
  Cuando se ejecuta la auditoría de secretos sobre la historia
  Entonces no se encuentran credenciales, o se registra su remediación

Escenario: Secreto ausente del repo
  Dado la configuración de la app
  Cuando se inspecciona el repositorio
  Entonces no aparece ningún valor de secreto, solo referencias al vault
```

### 11. Definition of Done específica

- [ ] Criterios demostrados; solo archivos autorizados.
- [ ] Pruebas obligatorias pasaron; evidencia sanitizada.
- [ ] ADR-005 revisado (se documenta por qué ahora sí hay Key Vault).
- [ ] Revisión cruzada aprobada.

### 12. Comandos de validación

```bash
./scripts/provision-keyvault.sh
./scripts/tests/validate-keyvault.sh
./scripts/tests/audit-git-secrets.sh
bash scripts/tests/scan-repository.sh
```

### 13. Evidencia esperada

- Listado de secretos por nombre (nunca su valor) y de asignaciones RBAC.
- Salida de la auditoría de historial.
- App leyendo un secreto por Managed Identity (log sanitizado).

### 14. Instrucción para una IA o integrante

Resumir antes; reportar después. No declarar `DONE` solo por código escrito.

---

## ISS-S2-004 — Definir contratos de evento y de mensaje de caso

### Metadatos

- **Historia:** HU-S2-003 · **Feature:** FEAT-S2-003
- **Responsable principal:** Persona 2 · **Revisor:** Persona 3
- **Dependencias para iniciar:** ISS-S1-007 (contrato de transacción de Semana 1)
- **Estimación orientativa:** 0,5–1 día
- **Flujo:** FM-S2-001, FM-S2-002
- **Requisitos:** RM-S2-001, RM-S2-002
- **Pruebas catalogadas:** TEST-S2-005

### 1. Objetivo

Definir y versionar los **dos contratos de mensaje** que cruzan el pipeline: el **evento de
transacción** (API → Event Grid → Function) y el **mensaje de caso marcado** (Function → cola →
consumidor).

### 2. Contexto y razón técnica

El enunciado exige que la forma de los eventos esté definida y documentada por la célula desde
el inicio: de eso depende que las piezas encajen. El contrato debe ser estable y **no** incluir
campos que aún no existen.

### 3. Descripción técnica

- Definir `transaction-event-v1` con: `transactionId`, `accountId`, `occurredAt`, `blobPath`
  (ubicación del JSON crudo) y metadatos mínimos. **No** incluye score.
- Definir `flagged-case-v1` con: `transactionId`, `accountId`, `score`, `triggeredRules`
  (resumen), `occurredAt`, `scoredAt`. Es el disparador de apertura de caso.
- Publicar los esquemas como **JSON Schema versionados** y como **records Java** que ambos
  módulos (app y Function) deben cumplir, validados por pruebas de contrato.
- Documentar la política de versionado (campos aditivos, compatibilidad hacia atrás).

### 4. Fuera de alcance

- Publicación real del evento (ISS-S2-006) y consumo (ISS-S2-011).
- Campos de Semana 3 (explicación en lenguaje natural, verificación de identidad).

### 5. Archivos que deben crearse

```text
docs/1_Requisitos_y_Contrato/4_Contrato_Evento_Transaccion.md
docs/1_Requisitos_y_Contrato/schemas/transaction-event-v1.json
docs/1_Requisitos_y_Contrato/schemas/flagged-case-v1.json
src/main/java/com/centinela/shared/event/TransactionEvent.java
src/main/java/com/centinela/shared/event/FlaggedCaseMessage.java
src/test/java/com/centinela/shared/event/EventContractTest.java
```

### 6. Archivos que pueden modificarse

```text
docs/1_Requisitos_y_Contrato/2_Contrato_Transaccion.md (referencia cruzada)
```

### 7. Archivos prohibidos

```text
campos score/decision en transaction-event-v1
campos de explicación de IA o verificación de identidad (Semana 3)
```

### 8. Criterios de aceptación

- [ ] `transaction-event-v1` NO contiene score ni decisión.
- [ ] `flagged-case-v1` contiene score y resumen de reglas activadas.
- [ ] Los esquemas JSON y los records Java coinciden (prueba de contrato).
- [ ] Política de versionado documentada.

### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S2-005` | Obligatoria para cerrar | Contrato | Mensajería | Validar coherencia esquema ↔ record Java |

### 10. Escenarios Gherkin

```gherkin
Escenario: Contrato de evento sin score
  Dado el esquema transaction-event-v1
  Cuando se valida contra el record Java
  Entonces coinciden y no existe un campo score

Escenario: Contrato de caso con score
  Dado el esquema flagged-case-v1
  Cuando se valida
  Entonces incluye score y el resumen de reglas activadas
```

### 11. Definition of Done específica

- [ ] Criterios demostrados; solo archivos autorizados.
- [ ] Prueba de contrato en verde; documentación coherente.
- [ ] Revisión cruzada aprobada.

### 12. Comandos de validación

```bash
mvn -Dtest=EventContractTest test
npx @redocly/cli lint docs/1_Requisitos_y_Contrato/schemas/*.json || true
```

### 13. Evidencia esperada

- Esquemas versionados y su prueba de contrato en verde.
- Documento de contrato con la política de versionado.

### 14. Instrucción para una IA o integrante

Resumir antes; reportar después. No declarar `DONE` solo por código escrito.

---

## ISS-S2-005 — Provisionar Event Grid + cola de casos

### Metadatos

- **Historia:** HU-S2-003 · **Feature:** FEAT-S2-003
- **Responsable principal:** Persona 2 · **Revisor:** Persona 1
- **Dependencias para iniciar:** Semana 1 (Storage), ISS-S2-004
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S2-001, FM-S2-002
- **Requisitos:** RM-S2-001, RM-S2-002
- **Pruebas catalogadas:** TEST-S2-006

### 1. Objetivo

Aprovisionar el **Event Grid Topic** (distribución del evento) y asegurar la **Storage Queue de
casos** (garantía de procesamiento), dejando la suscripción que enlazará la Function en ISS-S2-007.

### 2. Contexto y razón técnica

Son **dos mecanismos con propósitos distintos**: Event Grid **notifica** la ocurrencia de un
evento (la API no espera); la cola **garantiza** que ningún caso se pierda si el consumidor está
caído. Esta distinción es un entregable documental.

### 3. Descripción técnica

- Crear un **Event Grid Topic** (custom topic) para `transaction-event`.
- Crear/asegurar la **Storage Queue** `flagged-cases-{staging,production}` (o reutilizar la cola
  de Semana 1 renombrando su propósito; documentar la decisión).
- Otorgar rol **`EventGrid Data Sender`** a la Managed Identity de la Web App (publicar) y
  **`Storage Queue Data Message Processor/Sender`** según corresponda a Function y consumidor.
- Dejar la **suscripción** del tópico documentada como paso de ISS-S2-007 (la crea quien conecta
  la Function), para evitar dependencia circular.
- Idempotente y con tags.

### 4. Fuera de alcance

- Publicar el evento desde la API (ISS-S2-006).
- Trigger de la Function (ISS-S2-007).

### 5. Archivos que deben crearse

```text
scripts/provision-eventgrid.sh
scripts/tests/validate-eventgrid.sh
docs/evidence/iss-s2-005/.gitkeep
docs/2_Arquitectura/6_Mensajeria_Eventos_vs_Colas.md
```

### 6. Archivos que pueden modificarse

```text
scripts/provision-storage.sh (cola de casos, si se separa de la de Semana 1)
scripts/assign-rbac.sh
scripts/deploy-week2.sh
```

### 7. Archivos prohibidos

```text
consumidor de negocio de la cola (ISS-S2-011)
lógica de scoring (ISS-S2-008)
```

### 8. Criterios de aceptación

- [ ] Existe el Event Grid Topic para el evento de transacción.
- [ ] Existe la cola de casos con nombres por ambiente.
- [ ] Las identidades tienen los roles mínimos (publicar evento / operar cola).
- [ ] La distinción evento vs. cola está documentada.
- [ ] Reejecutar el script no duplica recursos.

### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S2-006` | Obligatoria para cerrar | Integración | Mensajería | Validar tópico, cola y RBAC de mensajería |

### 10. Escenarios Gherkin

```gherkin
Escenario: Tópico y cola creados
  Dado el Storage de Semana 1
  Cuando se ejecuta provision-eventgrid.sh
  Entonces existen el Event Grid Topic y la cola de casos con RBAC mínimo

Escenario: Distinción documentada
  Dado el documento de mensajería
  Cuando se revisa
  Entonces explica notificar-la-ocurrencia (evento) vs garantizar-el-procesamiento (cola)
```

### 11. Definition of Done específica

- [ ] Criterios demostrados; solo archivos autorizados.
- [ ] Pruebas obligatorias pasaron; evidencia sanitizada.
- [ ] Documento de mensajería redactado.
- [ ] Revisión cruzada aprobada.

### 12. Comandos de validación

```bash
./scripts/provision-eventgrid.sh
./scripts/tests/validate-eventgrid.sh
```

### 13. Evidencia esperada

- Listado de tópico, cola y asignaciones RBAC (sanitizado).
- Documento evento-vs-cola.

### 14. Instrucción para una IA o integrante

Resumir antes; reportar después. No declarar `DONE` solo por código escrito.

---

## ISS-S2-006 — Publicar evento en la API + limitación de tasa

### Metadatos

- **Historia:** HU-S2-004 · **Feature:** FEAT-S2-004
- **Responsable principal:** Persona 2 · **Revisor:** Persona 5
- **Dependencias para iniciar:** ISS-S2-003, ISS-S2-004, ISS-S2-005
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S2-001
- **Requisitos:** RF-S2-004, RM-S2-001, RS-S2-003, RNF-S2-001
- **Pruebas catalogadas:** TEST-S2-007, TEST-S2-008, TEST-S2-022

### 1. Objetivo

Incorporar a la API la **publicación del evento** de transacción tras persistir (paso 4 de la
secuencia), y añadir **limitación de tasa por origen** con el código de estado correcto.

### 2. Contexto y razón técnica

Es el punto de extensión que Semana 1 dejó preparado. La API **no** debe invocar el motor de
scoring ni esperar su resultado: publica el evento y responde. Sin rate limiting, un atacante
puede saturar la API y disparar una ejecución del motor por cada petición (consumo de crédito).

### 3. Descripción técnica

- Crear un **puerto de salida** `TransactionEventPublisherPort` en `transactioningestion` y un
  **adaptador Event Grid** que publique `transaction-event-v1` usando Managed Identity.
- Modificar `IngestTransactionService`: **persistir → publicar evento → responder `202`**. La
  publicación no debe bloquear más allá de confirmar el envío; ante fallo de publicación, aplicar
  la política acordada (fallar la petición vs. registrar para reintento — documentar la elección).
- Implementar **rate limiting** en la app (p. ej. filtro con Bucket4j por IP/origen) con límites
  configurables; responder **`429 Too Many Requests`** al exceder.
- No introducir score, reglas ni consulta de historial en la API.

### 4. Fuera de alcance

- Motor de scoring (Persona 3).
- API Management dedicado.

### 5. Archivos que deben crearse

```text
src/main/java/com/centinela/transactioningestion/application/port/out/TransactionEventPublisherPort.java
src/main/java/com/centinela/transactioningestion/infrastructure/messaging/EventGridTransactionEventPublisher.java
src/main/java/com/centinela/shared/web/RateLimitingFilter.java
src/test/java/com/centinela/transactioningestion/application/service/IngestPublishesEventTest.java
src/test/java/com/centinela/shared/web/RateLimitingFilterTest.java
```

### 6. Archivos que pueden modificarse

```text
src/main/java/com/centinela/transactioningestion/application/service/IngestTransactionService.java
src/main/java/com/centinela/transactioningestion/infrastructure/config/TransactionIngestionConfiguration.java
src/main/resources/application.yml (límites de tasa y endpoint del tópico, no secretos)
pom.xml (dependencia de rate limiting y SDK de Event Grid, si faltan)
```

### 7. Archivos prohibidos

```text
invocación directa o síncrona del motor de scoring desde la API
score/reglas/consulta de historial en el módulo de ingesta
```

### 8. Criterios de aceptación

- [ ] La API publica el evento **después** de persistir y **antes** de responder.
- [ ] La respuesta `202` no espera al scoring (demostrable por diseño y timestamps).
- [ ] Al exceder el límite de tasa, la API responde `429`.
- [ ] Los límites de tasa son configurables (sin recompilar).
- [ ] La API no ejecuta lógica de scoring.

### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S2-007` | Obligatoria para cerrar | Unitario | Integración API | Persistir → publicar evento → responder |
| `TEST-S2-008` | Obligatoria para cerrar | Integración | Seguridad | `429` al exceder el límite de tasa |
| `TEST-S2-022` | Posterior de integración | E2E | Desacoplamiento | Timestamps: respuesta antes del scoring |

### 10. Escenarios Gherkin

```gherkin
Escenario: Evento publicado tras persistir
  Dado una transacción válida y Blob disponible
  Cuando la API la procesa
  Entonces persiste, publica transaction-event-v1 y responde 202 sin esperar el scoring

Escenario: Límite de tasa excedido
  Dado un origen que supera el límite configurado
  Cuando envía otra transacción
  Entonces la API responde 429 y no publica un evento adicional

Escenario: Fallo de publicación
  Dado el tópico de Event Grid no disponible
  Cuando la API intenta publicar
  Entonces aplica la política documentada sin afirmar un éxito falso
```

### 11. Definition of Done específica

- [ ] Criterios demostrados; solo archivos autorizados.
- [ ] Pruebas obligatorias en verde; sin secretos.
- [ ] Política ante fallo de publicación documentada.
- [ ] Revisión cruzada aprobada.

### 12. Comandos de validación

```bash
mvn -Dtest=IngestPublishesEventTest,RateLimitingFilterTest test
mvn verify
```

### 13. Evidencia esperada

- Prueba de orden persistir→publicar→responder.
- Respuesta `429` sanitizada y configuración de límites.

### 14. Instrucción para una IA o integrante

Resumir antes; reportar después. No declarar `DONE` solo por código escrito.

---

## ISS-S2-007 — Esqueleto de la Function + lectura de historial por cuenta

### Metadatos

- **Historia:** HU-S2-002 · **Feature:** FEAT-S2-002
- **Responsable principal:** Persona 3 · **Revisor:** Persona 2
- **Dependencias para iniciar:** ISS-S2-001, ISS-S2-003, ISS-S2-005
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S2-001
- **Requisitos:** RF-S2-001, RD-S2-001
- **Pruebas catalogadas:** TEST-S2-009

### 1. Objetivo

Crear el **módulo de Azure Functions (Java)**, disparado por el **evento de Event Grid**, que
lee el **historial reciente de UNA cuenta** en Cosmos usando la clave de partición (sin recorrer
particiones ajenas).

### 2. Contexto y razón técnica

El motor es serverless y reactivo. La consulta dominante debe golpear **una sola partición**
(`accountId`); una consulta cross-partition funciona en pruebas y falla en volumen. Se evalúa el
**consumo de la consulta**, no solo su resultado.

### 3. Descripción técnica

- Crear un nuevo módulo Maven `scoring-function/` (Azure Functions Java) con `host.json`,
  package `com.centinela.scoring`, y arquitectura hexagonal (domain/application/infrastructure).
- Implementar `ScoreTransactionFunction` con **trigger de Event Grid** que recibe
  `transaction-event-v1` (crear la **suscripción** del tópico apuntando a la Function).
- Definir el puerto `TransactionHistoryPort` y el adaptador `CosmosTransactionHistoryAdapter`
  que consulta por `accountId` (una partición), leyendo la connection string desde Key Vault por
  Managed Identity.
- Aún **sin reglas**: solo recuperar el historial y registrar la métrica de consumo (RU) de la
  consulta para evidenciar que toca una sola partición.
- Configuración por App Settings/Key Vault (endpoint Cosmos, nombre de colección).

### 4. Fuera de alcance

- Reglas de detección y umbral (ISS-S2-008).
- Persistir score o publicar caso (ISS-S2-009).

### 5. Archivos que deben crearse

```text
scoring-function/pom.xml
scoring-function/host.json
scoring-function/src/main/java/com/centinela/scoring/infrastructure/function/ScoreTransactionFunction.java
scoring-function/src/main/java/com/centinela/scoring/application/port/out/TransactionHistoryPort.java
scoring-function/src/main/java/com/centinela/scoring/infrastructure/cosmos/CosmosTransactionHistoryAdapter.java
scoring-function/src/test/java/com/centinela/scoring/infrastructure/cosmos/CosmosTransactionHistoryAdapterIT.java
scripts/deploy-scoring-function.sh
```

### 6. Archivos que pueden modificarse

```text
scripts/deploy-week2.sh
scripts/assign-rbac.sh (Cosmos data + Key Vault a la identidad de la Function)
```

### 7. Archivos prohibidos

```text
consulta cross-partition para recuperar el historial de una cuenta
invocación síncrona desde la API (debe ser trigger por evento)
```

### 8. Criterios de aceptación

- [ ] La Function se activa con el evento de Event Grid.
- [ ] Recupera el historial de una cuenta usando la clave de partición.
- [ ] La métrica de consumo evidencia acceso a una sola partición.
- [ ] La connection string de Cosmos se obtiene de Key Vault por Managed Identity.

### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S2-009` | Obligatoria para cerrar | Integración | Datos y escalabilidad | Historial de una cuenta en una sola partición |

### 10. Escenarios Gherkin

```gherkin
Escenario: Function activada por evento
  Dado un evento transaction-event-v1 publicado
  Cuando llega al Event Grid
  Entonces la Function se ejecuta y recupera el historial de esa accountId

Escenario: Consulta de una sola partición
  Dado transacciones de varias cuentas en Cosmos
  Cuando la Function consulta por accountId
  Entonces la métrica de consumo indica acceso a una única partición
```

### 11. Definition of Done específica

- [ ] Criterios demostrados; solo archivos autorizados.
- [ ] Prueba de integración disponible pasó (o se marcó su dependencia de Azure).
- [ ] Evidencia de la métrica de consumo de la consulta.
- [ ] Revisión cruzada aprobada.

### 12. Comandos de validación

```bash
cd scoring-function && mvn -q clean package
mvn -Dtest=CosmosTransactionHistoryAdapterIT verify
```

### 13. Evidencia esperada

- Log de activación de la Function por evento.
- Métrica de consumo (RU) de la consulta por `accountId`.

### 14. Instrucción para una IA o integrante

Resumir antes; reportar después. No declarar `DONE` solo por código escrito.

---

## ISS-S2-008 — Cuatro reglas + umbral configurable + detalle de activación

### Metadatos

- **Historia:** HU-S2-002 · **Feature:** FEAT-S2-002
- **Responsable principal:** Persona 3 · **Revisor:** Persona 5
- **Dependencias para iniciar:** ISS-S2-007
- **Estimación orientativa:** 1,5 días
- **Flujo:** FM-S2-001
- **Requisitos:** RF-S2-001, RF-S2-002, RF-S2-003
- **Pruebas catalogadas:** TEST-S2-010, TEST-S2-011, TEST-S2-012, TEST-S2-013, TEST-S2-014, TEST-S2-015

### 1. Objetivo

Implementar las **cuatro reglas de detección**, la **suma de puntos**, el **umbral configurable
sin redespliegue**, y el **registro del detalle de activación** (valores observados, no solo el
identificador de la regla).

### 2. Contexto y razón técnica

Las reglas son heurísticas explicables. El **detalle de activación** es el insumo del explicador
de Semana 3: una regla que no registra los valores que la activaron es una regla incompleta. El
umbral debe cambiarse sin redesplegar (App Setting / Key Vault / configuración externa).

### 3. Descripción técnica

- Modelar en `domain/rule` cuatro reglas puras: **Velocidad**, **Monto atípico**,
  **Geo-imposible**, **Comercio de riesgo**, cada una devolviendo puntos + **detalle observado**.
- `ScoreTransactionService` (application) suma los puntos y arma el score y el detalle.
- **Umbral configurable**: leído de configuración externa (App Setting/Key Vault); su cambio no
  requiere recompilar ni redesplegar.
- Cada regla activada produce un objeto con: id de regla, puntos, y **los valores que la
  activaron** (cantidad en la ventana; monto observado vs. promedio; distancia y tiempo;
  comercio/categoría marcada).
- Lista de comercios/categorías de riesgo como configuración externa.

### 4. Fuera de alcance

- Persistir el score y publicar el caso (ISS-S2-009).
- Explicación en lenguaje natural (Semana 3).

### 5. Archivos que deben crearse

```text
scoring-function/src/main/java/com/centinela/scoring/domain/rule/VelocityRule.java
scoring-function/src/main/java/com/centinela/scoring/domain/rule/AtypicalAmountRule.java
scoring-function/src/main/java/com/centinela/scoring/domain/rule/GeoImpossibleRule.java
scoring-function/src/main/java/com/centinela/scoring/domain/rule/RiskyMerchantRule.java
scoring-function/src/main/java/com/centinela/scoring/domain/model/RuleHit.java
scoring-function/src/main/java/com/centinela/scoring/domain/model/Score.java
scoring-function/src/main/java/com/centinela/scoring/application/service/ScoreTransactionService.java
scoring-function/src/main/java/com/centinela/scoring/application/config/ScoringThresholdProvider.java
scoring-function/src/test/java/com/centinela/scoring/domain/rule/VelocityRuleTest.java
scoring-function/src/test/java/com/centinela/scoring/domain/rule/AtypicalAmountRuleTest.java
scoring-function/src/test/java/com/centinela/scoring/domain/rule/GeoImpossibleRuleTest.java
scoring-function/src/test/java/com/centinela/scoring/domain/rule/RiskyMerchantRuleTest.java
scoring-function/src/test/java/com/centinela/scoring/application/service/ScoreTransactionServiceTest.java
```

### 6. Archivos que pueden modificarse

```text
scoring-function/src/main/java/com/centinela/scoring/infrastructure/function/ScoreTransactionFunction.java
scoring-function/host.json (settings de umbral y lista de comercios, no secretos)
```

### 7. Archivos prohibidos

```text
umbral embebido (hardcodeado) en el código
persistir solo el id de la regla sin los valores observados
```

### 8. Criterios de aceptación

- [ ] Las cuatro reglas evalúan y aportan puntos según su criterio.
- [ ] El score total es la suma de las reglas activadas.
- [ ] El umbral se modifica sin redespliegue y cambia el comportamiento.
- [ ] Cada regla activada registra los valores concretos que la activaron.
- [ ] Ninguna regla depende de infraestructura (son de dominio puro).

### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S2-010` | Obligatoria para cerrar | Unitario | Reglas | Regla de velocidad se activa |
| `TEST-S2-011` | Obligatoria para cerrar | Unitario | Reglas | Regla de monto atípico se activa |
| `TEST-S2-012` | Obligatoria para cerrar | Unitario | Reglas | Regla geo-imposible se activa |
| `TEST-S2-013` | Obligatoria para cerrar | Unitario | Reglas | Regla de comercio de riesgo se activa |
| `TEST-S2-014` | Obligatoria para cerrar | Integración | Configuración | Umbral cambia sin redespliegue |
| `TEST-S2-015` | Obligatoria para cerrar | Unitario | Explicabilidad | Detalle de activación con valores observados |

### 10. Escenarios Gherkin

```gherkin
Escenario: Ubicaciones incompatibles
  Dado dos transacciones de una cuenta con distancia/tiempo imposibles
  Cuando se evalúa la regla geo-imposible
  Entonces se activa y registra distancia y tiempo observados

Escenario: Umbral en caliente
  Dado un umbral configurable
  Cuando se cambia su valor sin redesplegar
  Entonces una misma transacción cruza o no el umbral según el nuevo valor

Escenario: Detalle de activación
  Dado una regla activada
  Cuando se inspecciona su resultado
  Entonces contiene los valores concretos que la activaron, no solo su id
```

### 11. Definition of Done específica

- [ ] Criterios demostrados; solo archivos autorizados.
- [ ] Pruebas unitarias de las cuatro reglas + umbral + detalle en verde.
- [ ] Sin umbral hardcodeado.
- [ ] Revisión cruzada aprobada.

### 12. Comandos de validación

```bash
cd scoring-function && mvn -q test
```

### 13. Evidencia esperada

- Reporte de pruebas de las cuatro reglas.
- Demostración de cambio de umbral sin redespliegue.
- Ejemplo de detalle de activación por regla.

### 14. Instrucción para una IA o integrante

Resumir antes; reportar después. No declarar `DONE` solo por código escrito.

---

## ISS-S2-009 — Persistir score y publicar caso si supera umbral

### Metadatos

- **Historia:** HU-S2-002 · **Feature:** FEAT-S2-002
- **Responsable principal:** Persona 3 · **Revisor:** Persona 4
- **Dependencias para iniciar:** ISS-S2-007, ISS-S2-008
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S2-001
- **Requisitos:** RF-S2-003, RM-S2-002
- **Pruebas catalogadas:** TEST-S2-016, TEST-S2-017

### 1. Objetivo

Persistir el **score y el detalle de activación** junto a la transacción en Cosmos, y **encolar
un mensaje de apertura de caso** (`flagged-case-v1`) cuando el score supere el umbral.

### 2. Contexto y razón técnica

Cierra el motor: los pasos 5–6 de la secuencia de scoring. El detalle de activación se persiste
para el explicador de Semana 3. La publicación del caso usa la **cola** (garantía de procesamiento),
no una llamada directa al consumidor.

### 3. Descripción técnica

- Puerto `ScorePersistencePort` + adaptador Cosmos que guarda score + `triggeredRules` (con
  valores observados) junto al documento de la transacción (misma partición `accountId`).
- Puerto `FlaggedCasePublisherPort` + adaptador **Storage Queue** que encola `flagged-case-v1`
  solo si `score >= umbral`.
- Manejo idempotente: reprocesar el mismo evento no duplica score ni caso (clave por
  `transactionId`).
- Sin lógica de gestión de caso (eso es del consumidor, ISS-S2-011).

### 4. Fuera de alcance

- Inserción del caso en PostgreSQL (ISS-S2-011).
- Explicador (Semana 3).

### 5. Archivos que deben crearse

```text
scoring-function/src/main/java/com/centinela/scoring/application/port/out/ScorePersistencePort.java
scoring-function/src/main/java/com/centinela/scoring/application/port/out/FlaggedCasePublisherPort.java
scoring-function/src/main/java/com/centinela/scoring/infrastructure/cosmos/CosmosScorePersistenceAdapter.java
scoring-function/src/main/java/com/centinela/scoring/infrastructure/queue/StorageQueueFlaggedCasePublisher.java
scoring-function/src/test/java/com/centinela/scoring/application/service/ScorePersistAndPublishTest.java
scoring-function/src/test/java/com/centinela/scoring/infrastructure/queue/StorageQueueFlaggedCasePublisherIT.java
```

### 6. Archivos que pueden modificarse

```text
scoring-function/src/main/java/com/centinela/scoring/application/service/ScoreTransactionService.java
scoring-function/src/main/java/com/centinela/scoring/infrastructure/function/ScoreTransactionFunction.java
```

### 7. Archivos prohibidos

```text
llamada directa/síncrona al consumidor de casos
persistir el caso en PostgreSQL desde la Function
```

### 8. Criterios de aceptación

- [ ] El score y el detalle se persisten junto a la transacción (misma partición).
- [ ] Si el score supera el umbral, se encola `flagged-case-v1`.
- [ ] Si no supera el umbral, no se encola caso.
- [ ] Reprocesar el mismo evento no duplica score ni caso.

### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S2-016` | Obligatoria para cerrar | Integración | Persistencia | Score + detalle persistidos en Cosmos |
| `TEST-S2-017` | Obligatoria para cerrar | Integración | Mensajería | Caso encolado solo si supera umbral |

### 10. Escenarios Gherkin

```gherkin
Escenario: Score persistido
  Dado una transacción evaluada
  Cuando la Function termina
  Entonces el score y el detalle quedan junto a la transacción en Cosmos

Escenario: Caso encolado
  Dado un score que supera el umbral
  Cuando la Function publica
  Entonces se encola flagged-case-v1 en la cola de casos

Escenario: Sin caso bajo umbral
  Dado un score por debajo del umbral
  Cuando la Function termina
  Entonces no se encola ningún caso
```

### 11. Definition of Done específica

- [ ] Criterios demostrados; solo archivos autorizados.
- [ ] Pruebas de persistencia y publicación en verde.
- [ ] Idempotencia verificada.
- [ ] Revisión cruzada aprobada.

### 12. Comandos de validación

```bash
cd scoring-function && mvn -Dtest=ScorePersistAndPublishTest test
mvn -Dtest=StorageQueueFlaggedCasePublisherIT verify
```

### 13. Evidencia esperada

- Documento Cosmos con score + detalle (sanitizado).
- Mensaje `flagged-case-v1` en la cola.

### 14. Instrucción para una IA o integrante

Resumir antes; reportar después. No declarar `DONE` solo por código escrito.

---

## ISS-S2-010 — Esquema relacional de casos con auditoría

### Metadatos

- **Historia:** HU-S2-001 · **Feature:** FEAT-S2-001
- **Responsable principal:** Persona 4 · **Revisor:** Persona 1
- **Dependencias para iniciar:** ISS-S2-002, ISS-S2-003
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S2-002
- **Requisitos:** RD-S2-004
- **Pruebas catalogadas:** TEST-S2-018

### 1. Objetivo

Definir el **modelo de datos relacional** de casos con migraciones versionadas: Caso, Estado,
Asignación, Resolución y **Auditoría inmutable** de cada cambio de estado.

### 2. Contexto y razón técnica

Los casos requieren integridad referencial, reportería y trazabilidad legal. La auditoría es un
**registro inmutable** (append-only) de qué cambió, quién y cuándo.

### 3. Descripción técnica

- Crear un módulo `casemanagement` en la app principal (domain/application/infrastructure).
- Migraciones **Flyway** en `src/main/resources/db/migration` con las tablas:
  - `case` (referencia a `transactionId`, `score`, `state`, `opened_at`)
  - `case_state` (catálogo de estados)
  - `case_assignment` (caso ↔ analista)
  - `case_resolution` (decisión, analista, fecha, observaciones)
  - `case_audit` (append-only: cambio, autor, timestamp)
- Entidades JPA + `CaseRepositoryPort`/`CaseAuditPort` (puertos de salida).
- Restricciones de integridad referencial y unicidad por `transactionId`.
- La auditoría no admite `UPDATE`/`DELETE` (inmutable): imponerlo por diseño/triggers.

### 4. Fuera de alcance

- Consumir la cola (ISS-S2-011).
- UI de gestión de casos (Semana 3+).

### 5. Archivos que deben crearse

```text
src/main/resources/db/migration/V1__case_schema.sql
src/main/resources/db/migration/V2__case_audit_immutable.sql
src/main/java/com/centinela/casemanagement/domain/model/FraudCase.java
src/main/java/com/centinela/casemanagement/domain/model/CaseState.java
src/main/java/com/centinela/casemanagement/domain/model/CaseAuditEntry.java
src/main/java/com/centinela/casemanagement/application/port/out/CaseRepositoryPort.java
src/main/java/com/centinela/casemanagement/application/port/out/CaseAuditPort.java
src/main/java/com/centinela/casemanagement/infrastructure/persistence/JpaCaseRepositoryAdapter.java
src/test/java/com/centinela/casemanagement/infrastructure/persistence/CaseSchemaIT.java
```

### 6. Archivos que pueden modificarse

```text
pom.xml (Flyway, driver PostgreSQL, JPA — si faltan)
src/main/resources/application.yml (datasource por Key Vault/Managed Identity, sin password)
```

### 7. Archivos prohibidos

```text
password de base de datos versionada
UPDATE/DELETE permitido sobre la tabla de auditoría
```

### 8. Criterios de aceptación

- [ ] Existen las cinco entidades con integridad referencial.
- [ ] La auditoría es append-only (no admite modificación/borrado).
- [ ] Las migraciones aplican de forma reproducible sobre PostgreSQL privado.
- [ ] La conexión no usa credenciales versionadas.

### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S2-018` | Obligatoria para cerrar | Integración | Datos | Modelo aplicado + auditoría inmutable |

### 10. Escenarios Gherkin

```gherkin
Escenario: Migración reproducible
  Dado un PostgreSQL vacío
  Cuando se aplican las migraciones
  Entonces existen las tablas de caso, estado, asignación, resolución y auditoría

Escenario: Auditoría inmutable
  Dado un registro de auditoría existente
  Cuando se intenta modificarlo o borrarlo
  Entonces la operación es rechazada
```

### 11. Definition of Done específica

- [ ] Criterios demostrados; solo archivos autorizados.
- [ ] Migraciones idempotentes y probadas; auditoría inmutable verificada.
- [ ] Sin credenciales versionadas.
- [ ] Revisión cruzada aprobada.

### 12. Comandos de validación

```bash
mvn -Dtest=CaseSchemaIT verify
```

### 13. Evidencia esperada

- DDL aplicado y verificación de inmutabilidad de auditoría.
- Diagrama entidad-relación del modelo de casos.

### 14. Instrucción para una IA o integrante

Resumir antes; reportar después. No declarar `DONE` solo por código escrito.

---

## ISS-S2-011 — Consumidor de la cola de casos (idempotente)

### Metadatos

- **Historia:** HU-S2-003 · **Feature:** FEAT-S2-003
- **Responsable principal:** Persona 4 · **Revisor:** Persona 3
- **Dependencias para iniciar:** ISS-S2-005, ISS-S2-010
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S2-002
- **Requisitos:** RM-S2-002, RD-S2-004
- **Pruebas catalogadas:** TEST-S2-019, TEST-S2-020, TEST-S2-023

### 1. Objetivo

Implementar el **consumidor** que lee `flagged-case-v1` de la cola, inserta el **caso + auditoría**
en PostgreSQL de forma **idempotente**, y **procesa el backlog** acumulado tras una caída.

### 2. Contexto y razón técnica

El flujo de casos consume a su propio ritmo. La cola **garantiza el procesamiento**: si el
consumidor cae, los mensajes se acumulan; al reanudarse, se procesan todos sin pérdida. El
mensaje se elimina solo tras confirmar la escritura.

### 3. Descripción técnica

- `FlaggedCaseQueueListener` (adaptador de mensajería) que lee la Storage Queue por Managed
  Identity y llama a `OpenCaseUseCase`.
- `OpenCaseService` inserta el caso (estado inicial + auditoría de apertura) en una **transacción**;
  idempotente por `transactionId` (un caso por transacción).
- **Eliminar el mensaje solo tras** confirmar el commit (para no perder ante fallo).
- Manejar reintentos y, opcionalmente, un destino de mensajes problemáticos (documentar).
- Ejecutable como componente del App Service (worker) o Function con trigger de cola (documentar
  la elección; debe poder **detenerse y reanudarse** para la prueba de desacoplamiento).

### 4. Fuera de alcance

- Resolución/asignación por analistas (Semana 3+).
- Explicador (Semana 3).

### 5. Archivos que deben crearse

```text
src/main/java/com/centinela/casemanagement/application/port/in/OpenCaseUseCase.java
src/main/java/com/centinela/casemanagement/application/service/OpenCaseService.java
src/main/java/com/centinela/casemanagement/infrastructure/messaging/FlaggedCaseQueueListener.java
src/test/java/com/centinela/casemanagement/application/service/OpenCaseServiceTest.java
src/test/java/com/centinela/casemanagement/infrastructure/messaging/FlaggedCaseQueueListenerIT.java
scripts/tests/validate-decoupling.sh
```

### 6. Archivos que pueden modificarse

```text
src/main/resources/application.yml (nombre de la cola, sin secretos)
src/main/java/com/centinela/casemanagement/infrastructure/persistence/JpaCaseRepositoryAdapter.java
```

### 7. Archivos prohibidos

```text
eliminar el mensaje antes de confirmar la escritura
acoplar el consumidor a la API o al motor de scoring de forma síncrona
```

### 8. Criterios de aceptación

- [ ] El consumidor inserta el caso + auditoría de apertura por cada mensaje.
- [ ] Es idempotente (reprocesar el mismo mensaje no duplica el caso).
- [ ] El mensaje se elimina solo tras confirmar la escritura.
- [ ] Al reanudarse tras una caída, procesa todo el backlog sin pérdida.

### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S2-019` | Obligatoria para cerrar | Integración | Casos | Inserta caso + auditoría idempotente |
| `TEST-S2-020` | Obligatoria para cerrar | Integración | Resiliencia | Procesa backlog al reanudar |
| `TEST-S2-023` | Posterior de integración | E2E | Desacoplamiento | Consumidor caído sin pérdida de casos |

### 10. Escenarios Gherkin

```gherkin
Escenario: Caso insertado con auditoría
  Dado un mensaje flagged-case-v1 en la cola
  Cuando el consumidor lo procesa
  Entonces inserta el caso y una entrada de auditoría de apertura

Escenario: Idempotencia
  Dado el mismo mensaje procesado dos veces
  Cuando el consumidor lo recibe de nuevo
  Entonces no crea un caso duplicado

Escenario: Backlog tras caída
  Dado el consumidor detenido y mensajes acumulados
  Cuando se reanuda
  Entonces procesa todos los mensajes sin pérdida
```

### 11. Definition of Done específica

- [ ] Criterios demostrados; solo archivos autorizados.
- [ ] Idempotencia y procesamiento de backlog verificados.
- [ ] El consumidor puede detenerse/reanudarse.
- [ ] Revisión cruzada aprobada.

### 12. Comandos de validación

```bash
mvn -Dtest=OpenCaseServiceTest test
mvn -Dtest=FlaggedCaseQueueListenerIT verify
./scripts/tests/validate-decoupling.sh
```

### 13. Evidencia esperada

- Caso + auditoría insertados (sanitizado).
- Demostración de backlog procesado tras reanudar.

### 14. Instrucción para una IA o integrante

Resumir antes; reportar después. No declarar `DONE` solo por código escrito.

---

## ISS-S2-012 — Pipeline de extremo a extremo

### Metadatos

- **Historia:** HU-S2-004 · **Feature:** FEAT-S2-004
- **Responsable principal:** Persona 5 · **Revisor:** Persona 3
- **Dependencias para iniciar:** ISS-S2-006, ISS-S2-009, ISS-S2-011
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S2-001, FM-S2-002
- **Requisitos:** RF-S2-001, RF-S2-004, RNF-S2-001
- **Pruebas catalogadas:** TEST-S2-021

### 1. Objetivo

Demostrar el **pipeline completo**: una transacción entra por la API y produce, **sin intervención
manual**, un score y —si corresponde— un caso.

### 2. Contexto y razón técnica

Es la prueba integradora de la semana. Debe reconciliar cada etapa (API → evento → score → cola
→ caso) sin pasos manuales, sobre el entorno desplegado.

### 3. Descripción técnica

- Script E2E que envía una transacción válida con token de Servicio y verifica en orden:
  Blob (crudo) → evento publicado → score en Cosmos → mensaje en cola → caso en PostgreSQL.
- Cubrir un caso que **supera** el umbral (genera caso) y uno que **no** (solo score).
- Registrar tiempos por etapa para evidenciar el flujo automático.

### 4. Fuera de alcance

- Prueba de desacoplamiento y de umbral (ISS-S2-013).
- Pruebas de carga (dimensionadas aparte por costo).

### 5. Archivos que deben crearse

```text
scripts/tests/test-pipeline-e2e.sh
docs/evidence/iss-s2-012/.gitkeep
```

### 6. Archivos que pueden modificarse

```text
scripts/validate-week1.sh (o crear validate-week2.sh como agregador)
```

### 7. Archivos prohibidos

```text
pasos manuales entre etapas del pipeline
simular etapas no ejecutadas
```

### 8. Criterios de aceptación

- [ ] Una transacción sobre el umbral produce score y caso sin intervención.
- [ ] Una transacción bajo el umbral produce score y no caso.
- [ ] Cada etapa se reconcilia con evidencia real.
- [ ] No hay pasos manuales.

### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S2-021` | Obligatoria para cerrar | E2E | Pipeline | Transacción → score → caso sin intervención |

### 10. Escenarios Gherkin

```gherkin
Escenario: Pipeline con caso
  Dado una transacción que supera el umbral
  Cuando entra por la API
  Entonces se genera score y un caso, sin intervención manual

Escenario: Pipeline sin caso
  Dado una transacción bajo el umbral
  Cuando entra por la API
  Entonces se genera score pero no caso
```

### 11. Definition of Done específica

- [ ] Criterios demostrados; solo archivos autorizados.
- [ ] Evidencia por etapa reconciliada.
- [ ] Revisión cruzada aprobada.

### 12. Comandos de validación

```bash
./scripts/tests/test-pipeline-e2e.sh
```

### 13. Evidencia esperada

- Traza por etapa con timestamps.
- Score y caso resultantes (sanitizados).

### 14. Instrucción para una IA o integrante

Resumir antes; reportar después. No declarar `DONE` solo por código escrito.

---

## ISS-S2-013 — Prueba de desacoplamiento y de umbral

### Metadatos

- **Historia:** HU-S2-003 · **Feature:** FEAT-S2-003
- **Responsable principal:** Persona 5 · **Revisor:** Persona 4
- **Dependencias para iniciar:** ISS-S2-006, ISS-S2-009, ISS-S2-011
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S2-003
- **Requisitos:** RNF-S2-001, RM-S2-002, RF-S2-002
- **Pruebas catalogadas:** TEST-S2-022, TEST-S2-023, TEST-S2-014

### 1. Objetivo

Demostrar, de forma reproducible, que (a) la **API responde antes** de que el scoring termine,
(b) con el **consumidor detenido** la API sigue operando y **ningún caso se pierde**, y (c) el
**umbral cambia sin redespliegue** y el comportamiento cambia.

### 2. Contexto y razón técnica

El comportamiento ante fallos **se verifica, no se supone**. La primera ejecución suele revelar
pérdida de mensajes. Es la prueba que protege el diseño desacoplado sobre el que se construye
Semana 3.

### 3. Descripción técnica

- **Desacoplamiento (timestamps):** comparar el timestamp de respuesta de la API con el de fin
  del scoring; el primero debe ser anterior.
- **Consumidor detenido:** detener el consumidor, enviar N transacciones que marcan caso,
  verificar que la API responde con normalidad y que los N mensajes quedan en la cola.
- **Reanudación:** reanudar el consumidor y verificar que se insertan exactamente N casos
  (sin pérdida ni duplicados).
- **Umbral en caliente:** cambiar el umbral sin redesplegar y verificar que una misma transacción
  cruza o no el umbral según el valor.
- Restaurar el estado al finalizar (trap/`finally`).

### 4. Fuera de alcance

- Pruebas de carga masiva (costo).

### 5. Archivos que deben crearse

```text
scripts/tests/test-decoupling.sh
scripts/tests/test-threshold-hot-reload.sh
docs/evidence/iss-s2-013/.gitkeep
```

### 6. Archivos que pueden modificarse

```text
scripts/tests/validate-decoupling.sh (reutilizar utilidades)
```

### 7. Archivos prohibidos

```text
afirmar el resultado sin ejecutar la prueba
dejar el consumidor detenido o el umbral alterado al finalizar
```

### 8. Criterios de aceptación

- [ ] La respuesta de la API es anterior al fin del scoring (timestamps).
- [ ] Con el consumidor detenido, la API responde y los casos quedan en cola.
- [ ] Al reanudar, se procesan todos los casos sin pérdida ni duplicados.
- [ ] El umbral cambia sin redespliegue y el comportamiento cambia.
- [ ] El estado se restaura al finalizar.

### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S2-022` | Obligatoria para cerrar | E2E | Desacoplamiento | API responde antes del scoring |
| `TEST-S2-023` | Obligatoria para cerrar | E2E | Resiliencia | Consumidor caído sin pérdida |
| `TEST-S2-014` | Obligatoria para cerrar | E2E | Configuración | Umbral en caliente cambia el comportamiento |

### 10. Escenarios Gherkin

```gherkin
Escenario: Respuesta antes del análisis
  Dado una transacción válida
  Cuando entra por la API
  Entonces la API responde antes de que el motor de scoring termine

Escenario: Sin pérdida con consumidor caído
  Dado el consumidor detenido y transacciones que marcan caso
  Cuando se reanuda el consumidor
  Entonces todos los casos marcados se procesan sin pérdida

Escenario: Umbral en caliente
  Dado un umbral configurable
  Cuando se cambia sin redesplegar
  Entonces el sistema abre o no un caso según el nuevo valor
```

### 11. Definition of Done específica

- [ ] Criterios demostrados; solo archivos autorizados.
- [ ] Evidencia reproducible por cada prueba.
- [ ] Estado restaurado; revisión cruzada aprobada.

### 12. Comandos de validación

```bash
./scripts/tests/test-decoupling.sh
./scripts/tests/test-threshold-hot-reload.sh
```

### 13. Evidencia esperada

- Timestamps de API vs. fin de scoring.
- Conteo de casos: enviados = encolados = insertados.
- Comportamiento con dos valores de umbral.

### 14. Instrucción para una IA o integrante

Resumir antes; reportar después. No declarar `DONE` solo por código escrito.

---

## ISS-S2-014 — Reporte de crédito + ADR + cierre documental

### Metadatos

- **Historia:** HU-S2-005 · **Feature:** FEAT-S2-005
- **Responsable principal:** Persona 5 · **Revisor:** Persona 1
- **Dependencias para iniciar:** ISS-S2-001..ISS-S2-013
- **Estimación orientativa:** 1 día
- **Flujo:** Todos los de Semana 2
- **Requisitos:** RNF-S2-003, y las decisiones a documentar del alcance
- **Pruebas catalogadas:** TEST-S2-024, TEST-S2-025, TEST-S2-026

### 1. Objetivo

Consolidar el **reporte de crédito consumido** (acumulado y proyección), actualizar el
**documento de decisiones de arquitectura** con las decisiones de la semana, y cerrar la
documentación y trazabilidad.

### 2. Contexto y razón técnica

El crédito se acelera en esta semana (el motor corre una vez por transacción). La documentación
debe reflejar el sistema realmente implementado y conservar las decisiones para Semana 3.

### 3. Descripción técnica

- Generar el reporte de crédito: acumulado a la fecha y proyección al cierre del proyecto.
- Actualizar el ADR con: clave de partición y alternativas descartadas; nivel de consistencia y
  su impacto en latencia; política de expiración y su relación con las ventanas de reglas;
  justificación de mensajería vs. invocación directa; valor del umbral y criterio; diferencia
  funcional entre los dos mecanismos de mensajería.
- Actualizar la **matriz de trazabilidad** de Semana 2 (requisito → issue → prueba → evidencia).
- Verificar apagado de recursos costosos al cierre de jornada (guía operativa).
- Ejecutar el escaneo de secretos y la auditoría de historial como cierre.

### 4. Fuera de alcance

- Nuevas funcionalidades; decisiones de Semana 3.

### 5. Archivos que deben crearse

```text
docs/evidence/iss-s2-014/reporte-credito.md
docs/5_Issues_y_Trazabilidad/7_Matriz_Trazabilidad_Semana2.md
docs/RESUMEN-Semana2.md
```

### 6. Archivos que pueden modificarse

```text
docs/2_Arquitectura/2_ADR_Decisiones_Arquitectura.md
docs/0_Vision/3_Checkpoint_Alcance.md
```

### 7. Archivos prohibidos

```text
afirmaciones de pruebas no ejecutadas
secretos o capturas sin sanitizar
```

### 8. Criterios de aceptación

- [ ] Reporte de crédito con acumulado y proyección; acumulado de Semana 2 < 40 USD.
- [ ] ADR actualizado con las seis decisiones requeridas.
- [ ] Matriz de trazabilidad de Semana 2 completa.
- [ ] Escaneo de secretos y auditoría de historial en verde.

### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S2-024` | Obligatoria para cerrar | Estático | Costo | Reporte de crédito < 40 USD |
| `TEST-S2-025` | Obligatoria para cerrar | Estático | Documentación | ADR y matriz completos |
| `TEST-S2-026` | Obligatoria para cerrar | Estático | Seguridad | Historial de git sin secretos |

### 10. Escenarios Gherkin

```gherkin
Escenario: Crédito bajo control
  Dado el consumo de la semana
  Cuando se genera el reporte
  Entonces el acumulado de Semana 2 es inferior a 40 USD

Escenario: Decisiones documentadas
  Dado el ADR actualizado
  Cuando se revisa
  Entonces contiene partición, consistencia, TTL, mensajería, umbral y distinción de colas
```

### 11. Definition of Done específica

- [ ] Criterios demostrados; solo archivos autorizados.
- [ ] Documentación coherente con lo implementado.
- [ ] Revisión cruzada aprobada.

### 12. Comandos de validación

```bash
bash scripts/tests/scan-repository.sh
./scripts/tests/audit-git-secrets.sh
```

### 13. Evidencia esperada

- Reporte de crédito y proyección.
- ADR y matriz actualizados; escaneos en verde.

### 14. Instrucción para una IA o integrante

Resumir antes; reportar después. No declarar `DONE` solo por código escrito.

---

## Matriz de trazabilidad de Semana 2

| Requisito | Issue(s) | Prueba(s) | Evidencia principal |
|---|---|---|---|
| `RD-S2-001` | ISS-S2-001, 007 | TEST-S2-001, 009 | Shard key `accountId`; consulta de una partición. |
| `RD-S2-002` | ISS-S2-001 | TEST-S2-001, 025 | Nivel de consistencia justificado. |
| `RD-S2-003` | ISS-S2-001 | TEST-S2-001 | TTL alineado a ventanas de reglas. |
| `RD-S2-004` | ISS-S2-010, 011 | TEST-S2-018, 019 | Modelo + auditoría inmutable. |
| `RD-S2-005` | ISS-S2-002 | TEST-S2-002 | Postgres privado, sin acceso público. |
| `RD-S2-006` | ISS-S2-002 | TEST-S2-002 | Estrategia de respaldo. |
| `RF-S2-001` | ISS-S2-007, 008 | TEST-S2-009..013 | Motor por evento con 4 reglas. |
| `RF-S2-002` | ISS-S2-008, 013 | TEST-S2-014 | Umbral sin redespliegue. |
| `RF-S2-003` | ISS-S2-008, 009 | TEST-S2-015, 016 | Detalle de activación persistido. |
| `RF-S2-004` | ISS-S2-006 | TEST-S2-007, 022 | Publicar evento tras persistir. |
| `RM-S2-001` | ISS-S2-004, 005, 006 | TEST-S2-005, 006 | Distribución de evento. |
| `RM-S2-002` | ISS-S2-005, 009, 011 | TEST-S2-017, 020, 023 | Cola con garantía de procesamiento. |
| `RS-S2-001` | ISS-S2-003 | TEST-S2-026 | Cero secretos en repo e historial. |
| `RS-S2-002` | ISS-S2-003 | TEST-S2-003 | Acceso al vault por Managed Identity. |
| `RS-S2-003` | ISS-S2-006 | TEST-S2-008 | Rate limiting `429`. |
| `RNF-S2-001` | ISS-S2-006, 012, 013 | TEST-S2-022 | Desacoplamiento por timestamps. |
| `RNF-S2-002` | ISS-S2-001, 002 | TEST-S2-024 | Nivel gratuito ambos almacenes. |
| `RNF-S2-003` | ISS-S2-014 | TEST-S2-024 | Crédito < 40 USD. |

### Reglas de lectura

- Una issue puede tener varias pruebas de distinto nivel.
- Una prueba puede cubrir más de una issue cuando verifica integración o E2E.
- Las 14 issues permanecen dentro de Semana 2. No hay trazabilidad hacia IA, explicador,
  contenedores ni observabilidad instrumentada (Semana 3).
