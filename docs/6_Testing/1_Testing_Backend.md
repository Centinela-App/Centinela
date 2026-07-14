# 08 — Plan y catálogo de pruebas de Semana 1

## Propósito

Este documento define las pruebas necesarias para demostrar las 14 issues y los criterios de `0_Vision/2_Alcance_Semana1.md`. La cantidad de pruebas no tiene que coincidir con la cantidad de issues: una issue de código puede necesitar pruebas unitarias, de contrato, integración y E2E.

## Taxonomía obligatoria

### Nivel de prueba

| Nivel | Qué aísla o recorre | Usa Azure real |
|---|---|---|
| Estático | Código, arquitectura, scripts, secretos, documentación o alcance sin ejecutar el sistema. | No. |
| Unitario | Una clase o función aislada mediante mocks/fakes. | No. |
| Contrato | OpenAPI, DTOs, tipos, obligatoriedad y respuestas. | No necesariamente. |
| Integración | Dos o más componentes o un adaptador con un recurso controlado. | Cuando el objetivo es Azure, sí. |
| E2E | Recorrido completo sobre la aplicación desplegada. | Sí. |

### Categoría

La categoría expresa el objetivo: arquitectura, validación, API, seguridad/RBAC, infraestructura, red, almacenamiento, Queue, configuración, disponibilidad, documentación o control de alcance.

**Gherkin no es un nivel de prueba.** Es la forma de describir los caminos feliz, alterno y de error de cualquier nivel.

## Reglas generales

- No usar PII real.
- Registrar commit, ambiente, runId y timestamp.
- Limpiar datos y recursos temporales.
- Un `202` solo es exitoso si el Blob existe.
- Ocultar tokens, secretos e identificadores sensibles.
- Usar el único entorno Azure integrado del equipo.
- No probar scoring, reglas, casos, IA, consumidor ni bases de Semana 2.

## Resumen

| ID | Nombre | Nivel | Categoría | Issue(s) |
|---|---|---|---|---|
| `TEST-S1-001` | Validar compilación y límites hexagonales | Estático | Arquitectura | ISS-S1-001 |
| `TEST-S1-002` | Detectar secretos y archivos sensibles versionados | Estático | Seguridad e higiene | ISS-S1-001, ISS-S1-002, ISS-S1-006, ISS-S1-013 |
| `TEST-S1-003` | Validar parámetros obligatorios del despliegue | Estático | Scripts de infraestructura | ISS-S1-002 |
| `TEST-S1-004` | Proteger la destrucción del Resource Group | Integración | Scripts y control de costos | ISS-S1-002, ISS-S1-014 |
| `TEST-S1-005` | Validar Storage, contenedores y colas por ambiente | Integración | Infraestructura y almacenamiento | ISS-S1-003 |
| `TEST-S1-006` | Validar App Service, Managed Identity y slot staging | Integración | Infraestructura y configuración | ISS-S1-004 |
| `TEST-S1-007` | Validar red privada y resolución DNS | Integración | Red y seguridad | ISS-S1-005 |
| `TEST-S1-008` | Validar existencia de los cuatro app roles | Integración | Identidad y seguridad | ISS-S1-006 |
| `TEST-S1-009` | Impedir modificaciones Azure al Analista | E2E | Seguridad y RBAC | ISS-S1-006 |
| `TEST-S1-010` | Validar mínimo privilegio de Managed Identity | Integración | Seguridad y RBAC | ISS-S1-006, ISS-S1-008, ISS-S1-009 |
| `TEST-S1-011` | Validar contrato OpenAPI de la transacción | Contrato | API y contrato | ISS-S1-007 |
| `TEST-S1-012` | Validar campos y límites de TransactionRequest | Unitario | Validación | ISS-S1-007 |
| `TEST-S1-013` | Mapear únicamente los datos crudos aprobados | Unitario | Mapeo y alcance | ISS-S1-007 |
| `TEST-S1-014` | Persistir antes de emitir el acuse | Unitario | Caso de uso y errores | ISS-S1-008 |
| `TEST-S1-015` | Integrar adaptador Blob de transacciones | Integración | Persistencia Blob | ISS-S1-008 |
| `TEST-S1-016` | Recibir y almacenar una transacción válida desplegada | E2E | API de ingesta | ISS-S1-008, ISS-S1-011 |
| `TEST-S1-017` | Rechazar payload inválido sin persistir | Integración | API y validación | ISS-S1-007, ISS-S1-008 |
| `TEST-S1-018` | Validar documento y normalizar nombre | Unitario | Documentos y seguridad | ISS-S1-009 |
| `TEST-S1-019` | Cargar documento desde la API y comprobar Blob | E2E | Documentos y almacenamiento | ISS-S1-009, ISS-S1-011 |
| `TEST-S1-020` | Validar roundtrip de Queue Storage | Integración | Queue e infraestructura | ISS-S1-010 |
| `TEST-S1-021` | Autorizar únicamente Servicio en transacciones | Integración | Seguridad HTTP | ISS-S1-011 |
| `TEST-S1-022` | Autorizar únicamente Analista en carga documental | Integración | Seguridad HTTP | ISS-S1-011 |
| `TEST-S1-023` | Confirmar aislamiento funcional entre staging y producción | E2E | Configuración por ambiente | ISS-S1-004, ISS-S1-008, ISS-S1-009 |
| `TEST-S1-024` | Mantener disponibilidad al retirar una instancia | E2E | Disponibilidad y resiliencia | ISS-S1-012 |
| `TEST-S1-025` | Validar entregables documentales y trazabilidad | Estático | Documentación | ISS-S1-013 |
| `TEST-S1-026` | Desplegar desde una suscripción o Resource Group limpio | E2E | Infraestructura reproducible | ISS-S1-002, ISS-S1-003, ISS-S1-004, ISS-S1-005, ISS-S1-006, ISS-S1-014 |
| `TEST-S1-027` | Destruir, reconstruir, validar y limpiar | E2E | Infraestructura reproducible y costos | ISS-S1-014 |
| `TEST-S1-028` | Verificar que no se implementó alcance de Semana 2 | Estático | Control de alcance | ISS-S1-001, ISS-S1-007, ISS-S1-008, ISS-S1-009, ISS-S1-010, ISS-S1-013 |


## TEST-S1-001 — Validar compilación y límites hexagonales

### Identificación

- **ID:** `TEST-S1-001`
- **Nombre:** Validar compilación y límites hexagonales
- **Nivel:** Estático
- **Categoría:** Arquitectura
- **Prioridad:** Crítica
- **Ambiente:** Local/CI
- **Requisitos:** `RNF-S1-001`
- **Flujo:** Transversal
- **Issue(s):** `ISS-S1-001`

### Propósito

Comprobar que el proyecto Java 21 compila y que dominio/aplicación no dependen de Spring Web, controladores ni SDK de Azure.

### Precondiciones

- Repositorio clonado limpio.
- Java 21 y Maven disponibles.

### Datos de prueba

- Reglas ArchUnit sobre paquetes `domain`, `application` e `infrastructure`.

### Dobles y dependencias

- ArchUnit o regla equivalente; no requiere Azure.

### Pasos

1. Ejecutar `mvn clean verify`.
2. Ejecutar `ArchitectureConventionsTest`.
3. Revisar que no existan imports prohibidos.

### Resultado esperado

- Build exitoso.
- Dominio y aplicación aislados de infraestructura.
- Una dependencia prohibida provoca fallo reproducible.

### Escenarios Gherkin

      ```gherkin
Escenario: Camino feliz
  Dado las capas respetan las reglas
  Cuando se ejecuta la suite
  Entonces todas las reglas pasan

Escenario: Camino alterno
  Dado existe una clase de infraestructura válida
  Cuando la regla inspecciona sus dependencias
  Entonces la clase puede usar el SDK de Azure sin contaminar dominio

Escenario: Camino de error
  Dado dominio importa una clase del SDK de Azure
  Cuando se ejecuta la prueba
  Entonces la prueba falla e identifica la dependencia
```

### Automatización

- **Archivo:** `src/test/java/com/centinela/architecture/ArchitectureConventionsTest.java`
- **Método/escenario:** `architecture_layers_should_be_isolated`
- **Comando aislado:** `mvn -Dtest=ArchitectureConventionsTest test`
- **Suite:** `mvn clean verify`

### Evidencia

- **Ruta:** `target/surefire-reports`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

Eliminar cualquier fixture intencional usado para demostrar el fallo.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-002 — Detectar secretos y archivos sensibles versionados

### Identificación

- **ID:** `TEST-S1-002`
- **Nombre:** Detectar secretos y archivos sensibles versionados
- **Nivel:** Estático
- **Categoría:** Seguridad e higiene
- **Prioridad:** Crítica
- **Ambiente:** Local/CI
- **Requisitos:** `RS-S1-004`
- **Flujo:** Transversal
- **Issue(s):** `ISS-S1-001`, `ISS-S1-002`, `ISS-S1-006`, `ISS-S1-013`

### Propósito

Verificar que el repositorio no contiene claves, cadenas de conexión, tokens, private keys ni archivos locales con credenciales.

### Precondiciones

- Repositorio completo disponible.

### Datos de prueba

- Patrones de `AccountKey`, connection strings, client secrets, tokens y private keys.

### Dobles y dependencias

- Script local de búsqueda; no imprime valores completos.

### Pasos

1. Ejecutar el escaneo.
2. Revisar `.gitignore`.
3. Confirmar que variables sensibles se referencian por nombre y no por valor.

### Resultado esperado

- Cero secretos detectados.
- Los archivos `.env` reales no están versionados.
- Los hallazgos muestran archivo/línea sin exponer el valor.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado el repositorio no contiene secretos
  Cuando se ejecuta el escaneo
  Entonces termina con código 0

Escenario: Camino alterno
  Dado existe un archivo de ejemplo con nombres de variables pero sin valores
  Cuando se ejecuta el escaneo
  Entonces el archivo permitido no se marca como secreto

Escenario: Camino de error
  Dado se introduce una cadena de conexión de prueba
  Cuando se ejecuta el escaneo
  Entonces la prueba falla y señala la ubicación
```

### Automatización

- **Archivo:** `scripts/tests/scan-repository.sh`
- **Método/escenario:** `scan_repository_for_secrets`
- **Comando aislado:** `./scripts/tests/scan-repository.sh`
- **Suite:** `mvn verify && ./scripts/tests/scan-repository.sh`

### Evidencia

- **Ruta:** `docs/evidence/repository/{runId}/secret-scan.md`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

Eliminar el fixture de secreto antes de commit.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-003 — Validar parámetros obligatorios del despliegue

### Identificación

- **ID:** `TEST-S1-003`
- **Nombre:** Validar parámetros obligatorios del despliegue
- **Nivel:** Estático
- **Categoría:** Scripts de infraestructura
- **Prioridad:** Alta
- **Ambiente:** Local
- **Requisitos:** `RI-S1-001`, `RNF-S1-003`, `RNF-S1-004`
- **Flujo:** FM-S1-004
- **Issue(s):** `ISS-S1-002`

### Propósito

Comprobar que el script no crea recursos si faltan parámetros y que no fija región, SKU, suscripción o nombres dentro del código.

### Precondiciones

- Azure CLI disponible; no se requiere ejecutar un despliegue real para los casos negativos.

### Datos de prueba

- SUBSCRIPTION_ID, LOCATION, RESOURCE_GROUP, NAME_PREFIX y APP_SERVICE_SKU.

### Dobles y dependencias

- Shellcheck opcional y funciones de validación del script.

### Pasos

1. Ejecutar el script sin cada parámetro obligatorio.
2. Inspeccionar que falle antes de `az group create`.
3. Buscar valores rígidos prohibidos.

### Resultado esperado

- Cada ausencia genera mensaje claro y código distinto de cero.
- No se crea Resource Group.
- Región y SKU permanecen parametrizados.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado todos los parámetros requeridos están presentes
  Cuando se ejecuta la validación previa
  Entonces el script permite continuar

Escenario: Camino alterno
  Dado el SKU se recibe por variable de entorno
  Cuando se valida el parámetro
  Entonces se acepta sin modificar el script

Escenario: Camino de error
  Dado falta LOCATION
  Cuando se ejecuta el script
  Entonces termina antes de crear recursos
```

### Automatización

- **Archivo:** `scripts/tests/test-deploy-parameters.sh`
- **Método/escenario:** `test_required_parameters`
- **Comando aislado:** `./scripts/tests/test-deploy-parameters.sh`
- **Suite:** `./scripts/tests/test-deploy-parameters.sh`

### Evidencia

- **Ruta:** `docs/evidence/infrastructure/{runId}/parameter-validation.md`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

No aplica; la prueba no debe crear recursos.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-004 — Proteger la destrucción del Resource Group

### Identificación

- **ID:** `TEST-S1-004`
- **Nombre:** Proteger la destrucción del Resource Group
- **Nivel:** Integración
- **Categoría:** Scripts y control de costos
- **Prioridad:** Crítica
- **Ambiente:** Local
- **Requisitos:** `RI-S1-006`, `RNF-S1-004`
- **Flujo:** FM-S1-004
- **Issue(s):** `ISS-S1-002`, `ISS-S1-014`

### Propósito

Evitar que `destroy-week1.sh` elimine un Resource Group distinto al aprobado y asegurar una vía reproducible de limpieza.

### Precondiciones

- Script disponible.
- Nombre de prueba que no coincide con el prefijo aprobado.

### Datos de prueba

- RESOURCE_GROUP válido e inválido; modo confirmación y modo no interactivo controlado.

### Dobles y dependencias

- Puede usar mocks de `az` para casos negativos; la destrucción real se valida en TEST-S1-027.

### Pasos

1. Ejecutar con nombre no permitido.
2. Ejecutar sin confirmación requerida.
3. Ejecutar validación con nombre correcto en modo dry-run o mock.

### Resultado esperado

- Nombres no permitidos son rechazados.
- Sin confirmación no se elimina nada.
- El comando final de eliminación solo se construye para el Resource Group exacto.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado el Resource Group coincide con el nombre aprobado y existe confirmación
  Cuando se ejecuta el script
  Entonces se autoriza la eliminación

Escenario: Camino alterno
  Dado se usa modo no interactivo dentro del test final
  Cuando se entrega la bandera explícita
  Entonces el script continúa y registra el runId

Escenario: Camino de error
  Dado el nombre pertenece a otro proyecto
  Cuando se solicita destruir
  Entonces el script rechaza la operación
```

### Automatización

- **Archivo:** `scripts/tests/test-destroy-safety.sh`
- **Método/escenario:** `test_resource_group_guard`
- **Comando aislado:** `./scripts/tests/test-destroy-safety.sh`
- **Suite:** `./scripts/tests/test-destroy-safety.sh`

### Evidencia

- **Ruta:** `docs/evidence/infrastructure/{runId}/destroy-safety.md`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

Eliminar mocks o archivos temporales.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-005 — Validar Storage, contenedores y colas por ambiente

### Identificación

- **ID:** `TEST-S1-005`
- **Nombre:** Validar Storage, contenedores y colas por ambiente
- **Nivel:** Integración
- **Categoría:** Infraestructura y almacenamiento
- **Prioridad:** Crítica
- **Ambiente:** Azure integrado
- **Requisitos:** `RF-S1-004`, `RF-S1-006`, `RI-S1-002`
- **Flujo:** FM-S1-004
- **Issue(s):** `ISS-S1-003`

### Propósito

Comprobar que existe un Storage Account compartido, con acceso público deshabilitado y recursos lógicos separados para staging y producción.

### Precondiciones

- ISS-S1-003 desplegada.
- Identidad de despliegue con lectura del control plane.

### Datos de prueba

- Contenedores raw y documentales; colas de staging y producción.

### Dobles y dependencias

- Azure CLI contra el entorno real.

### Pasos

1. Consultar configuración del Storage Account.
2. Listar contenedores y colas.
3. Comparar nombres de staging y producción.

### Resultado esperado

- Acceso público deshabilitado.
- Existen todos los recursos requeridos.
- No se comparte el mismo contenedor o cola entre ambientes.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado Storage fue creado por scripts
  Cuando se ejecuta la validación
  Entonces todos los recursos existen y son privados

Escenario: Camino alterno
  Dado un contenedor ya existe de una ejecución anterior
  Cuando se repite el script
  Entonces la operación es idempotente y conserva la configuración

Escenario: Camino de error
  Dado el acceso público está habilitado o falta una cola
  Cuando se valida el entorno
  Entonces la prueba falla
```

### Automatización

- **Archivo:** `scripts/tests/validate-storage.sh`
- **Método/escenario:** `validate_storage_resources`
- **Comando aislado:** `./scripts/tests/validate-storage.sh`
- **Suite:** `./scripts/validate-week1.sh`

### Evidencia

- **Ruta:** `docs/evidence/storage/{runId}/storage-inventory.json`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

No elimina recursos compartidos; solo limpia datos creados por pruebas específicas.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-006 — Validar App Service, Managed Identity y slot staging

### Identificación

- **ID:** `TEST-S1-006`
- **Nombre:** Validar App Service, Managed Identity y slot staging
- **Nivel:** Integración
- **Categoría:** Infraestructura y configuración
- **Prioridad:** Crítica
- **Ambiente:** Azure integrado
- **Requisitos:** `RF-S1-007`, `RI-S1-004`
- **Flujo:** FM-S1-004
- **Issue(s):** `ISS-S1-004`

### Propósito

Comprobar que producción y staging existen en la misma solución, con Managed Identity y variables separadas.

### Precondiciones

- App Service desplegado.

### Datos de prueba

- Web App, slot staging, identidad y app settings no secretos.

### Dobles y dependencias

- Azure CLI.

### Pasos

1. Consultar plan, Web App y slot.
2. Confirmar Managed Identity en producción y staging.
3. Comparar variables `APP_ENVIRONMENT` y nombres de contenedor.

### Resultado esperado

- Existe slot staging.
- Las identidades están habilitadas.
- Staging apunta a recursos staging y producción a recursos production.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado Web App y slot existen
  Cuando se valida la configuración
  Entonces ambos ambientes quedan separados

Escenario: Camino alterno
  Dado el script se reejecuta
  Cuando los recursos ya existen
  Entonces se actualiza sin crear otra Web App

Escenario: Camino de error
  Dado staging usa el contenedor production
  Cuando se compara la configuración
  Entonces la prueba falla
```

### Automatización

- **Archivo:** `scripts/tests/validate-app-service.sh`
- **Método/escenario:** `validate_app_service_and_slot`
- **Comando aislado:** `./scripts/tests/validate-app-service.sh`
- **Suite:** `./scripts/validate-week1.sh`

### Evidencia

- **Ruta:** `docs/evidence/appservice/{runId}/app-service-config.json`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

No modifica capacidad ni elimina slots.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-007 — Validar red privada y resolución DNS

### Identificación

- **ID:** `TEST-S1-007`
- **Nombre:** Validar red privada y resolución DNS
- **Nivel:** Integración
- **Categoría:** Red y seguridad
- **Prioridad:** Crítica
- **Ambiente:** Azure integrado
- **Requisitos:** `RI-S1-002`, `RI-S1-003`
- **Flujo:** FM-S1-004
- **Issue(s):** `ISS-S1-005`

### Propósito

Comprobar la configuración de VNet Integration, Private Endpoints y DNS privado, y demostrar que Storage rechaza el acceso público.

### Precondiciones

- VNet, subredes, Private Endpoints, DNS privado y VNet Integration desplegados.

### Datos de prueba

- Endpoints Blob y Queue; origen externo no autorizado y aplicación integrada.

### Dobles y dependencias

- Azure CLI, resolución DNS desde un contexto autorizado de la VNet y comprobación de acceso público denegado.

### Pasos

1. Verificar subredes, delegaciones y VNet Integration.
2. Comprobar Private Endpoints y zonas DNS.
3. Resolver los nombres de Storage desde un contexto autorizado de la VNet.
4. Intentar acceso de data plane desde un origen público no autorizado.

### Resultado esperado

- El acceso público falla.
- El FQDN resuelve a IP privada desde la VNet.
- La conectividad privada queda lista; el acceso funcional de la API se confirma después en las pruebas de Blob y E2E.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado VNet Integration, Private Endpoints y DNS están configurados
  Cuando se valida la resolución desde la red autorizada
  Entonces Storage resuelve a una dirección privada

Escenario: Camino alterno
  Dado se consulta el DNS desde la red integrada
  Cuando se resuelve el FQDN
  Entonces se obtiene una dirección privada

Escenario: Camino de error
  Dado un cliente de Internet intenta acceder a Storage
  Cuando envía la solicitud
  Entonces el acceso es rechazado
```

### Automatización

- **Archivo:** `scripts/tests/validate-network.sh`
- **Método/escenario:** `validate_private_storage_configuration`
- **Comando aislado:** `./scripts/tests/validate-network.sh`
- **Suite:** `./scripts/validate-week1.sh`

### Evidencia

- **Ruta:** `docs/evidence/network/{runId}/private-connectivity.md`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

Eliminar objetos técnicos creados para comprobar conectividad.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-008 — Validar existencia de los cuatro app roles

### Identificación

- **ID:** `TEST-S1-008`
- **Nombre:** Validar existencia de los cuatro app roles
- **Nivel:** Integración
- **Categoría:** Identidad y seguridad
- **Prioridad:** Alta
- **Ambiente:** Azure integrado
- **Requisitos:** `RS-S1-001`
- **Flujo:** Control de acceso
- **Issue(s):** `ISS-S1-006`

### Propósito

Comprobar que Entra ID define Servicio, Analista, Administrador y Auditor sin confundirlos con Azure RBAC.

### Precondiciones

- Aplicación Entra creada.

### Datos de prueba

- App roles SERVICE, ANALYST, ADMINISTRATOR y AUDITOR.

### Dobles y dependencias

- Microsoft Graph/Azure CLI según el script elegido.

### Pasos

1. Consultar el manifiesto de la aplicación.
2. Verificar nombres, valores y estado habilitado.
3. Confirmar que cada rol tiene descripción funcional.

### Resultado esperado

- Los cuatro roles existen exactamente una vez.
- No se conceden automáticamente permisos Contributor/Owner.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado el manifiesto contiene los cuatro roles
  Cuando se ejecuta la validación
  Entonces todos aparecen habilitados

Escenario: Camino alterno
  Dado se reejecuta el aprovisionamiento
  Cuando los roles ya existen
  Entonces no se duplican

Escenario: Camino de error
  Dado falta AUDITOR o un rol está deshabilitado
  Cuando se valida el manifiesto
  Entonces la prueba falla
```

### Automatización

- **Archivo:** `scripts/tests/validate-entra-roles.sh`
- **Método/escenario:** `validate_four_application_roles`
- **Comando aislado:** `./scripts/tests/validate-entra-roles.sh`
- **Suite:** `./scripts/tests/validate-rbac.sh`

### Evidencia

- **Ruta:** `docs/evidence/identity/{runId}/app-roles.json`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

No elimina asignaciones usadas por el equipo.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-009 — Impedir modificaciones Azure al Analista

### Identificación

- **ID:** `TEST-S1-009`
- **Nombre:** Impedir modificaciones Azure al Analista
- **Nivel:** E2E
- **Categoría:** Seguridad y RBAC
- **Prioridad:** Crítica
- **Ambiente:** Azure integrado
- **Requisitos:** `RS-S1-002`
- **Flujo:** Control de acceso
- **Issue(s):** `ISS-S1-006`

### Propósito

Demostrar el criterio explícito de Semana 1: un Analista puede consultar lo permitido, pero no modificar configuración de infraestructura.

### Precondiciones

- Identidad de prueba Analista.
- Recursos desplegados.

### Datos de prueba

- Intentos de lectura, modificación de tag y eliminación.

### Dobles y dependencias

- Azure RBAC real; no ejecutar como Owner.

### Pasos

1. Autenticarse como Analista.
2. Listar recursos.
3. Intentar cambiar un tag.
4. Intentar modificar Storage o eliminar un recurso.

### Resultado esperado

- Lectura permitida según matriz.
- Todas las operaciones de escritura/eliminación son denegadas.
- Ningún recurso cambia.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado el Analista tiene solo lectura
  Cuando lista recursos
  Entonces la consulta funciona

Escenario: Camino alterno
  Dado el Analista intenta leer otra propiedad permitida
  Cuando realiza la consulta
  Entonces Azure devuelve información sin permitir escritura

Escenario: Camino de error
  Dado el Analista intenta modificar un tag
  Cuando Azure autoriza o deniega
  Entonces la operación debe ser denegada
```

### Automatización

- **Archivo:** `scripts/tests/test-analyst-rbac.sh`
- **Método/escenario:** `test_analyst_cannot_modify_resources`
- **Comando aislado:** `./scripts/tests/test-analyst-rbac.sh`
- **Suite:** `./scripts/tests/validate-rbac.sh`

### Evidencia

- **Ruta:** `docs/evidence/security/{runId}/analyst-rbac.md`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

Confirmar que no quedó ningún tag o cambio temporal.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-010 — Validar mínimo privilegio de Managed Identity

### Identificación

- **ID:** `TEST-S1-010`
- **Nombre:** Validar mínimo privilegio de Managed Identity
- **Nivel:** Integración
- **Categoría:** Seguridad y RBAC
- **Prioridad:** Crítica
- **Ambiente:** Azure integrado
- **Requisitos:** `RS-S1-003`, `RS-S1-004`
- **Flujo:** Control de acceso
- **Issue(s):** `ISS-S1-006`, `ISS-S1-008`, `ISS-S1-009`

### Propósito

Comprobar que las asignaciones RBAC de la Managed Identity son las mínimas para Blob, sin claves ni permisos de Queue no requeridos.

### Precondiciones

- Managed Identity creada y recursos Storage disponibles.

### Datos de prueba

- Asignaciones RBAC de producción y staging.

### Dobles y dependencias

- Azure CLI y consulta de App Settings; la escritura funcional se verifica después en TEST-S1-015 y TEST-S1-019.

### Pasos

1. Listar asignaciones de la Managed Identity.
2. Verificar el rol de datos Blob y su alcance mínimo.
3. Buscar connection strings o account keys en settings.
4. Confirmar ausencia de rol Queue en la identidad de la aplicación.

### Resultado esperado

- La Managed Identity tiene únicamente el acceso Blob requerido.
- No hay claves en configuración.
- No existe permiso Queue para la aplicación.
- La prueba no depende todavía del código de persistencia.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado la Managed Identity existe
  Cuando se consultan sus asignaciones
  Entonces solo aparece el rol Blob mínimo al alcance aprobado

Escenario: Camino alterno
  Dado producción y staging tienen identidades/configuración separadas
  Cuando se consultan las asignaciones
  Entonces cada ambiente queda limitado a sus recursos aprobados

Escenario: Camino de error
  Dado la identidad tiene Contributor o Queue Data Contributor
  Cuando se valida RBAC
  Entonces la prueba falla por privilegio excesivo
```

### Automatización

- **Archivo:** `scripts/tests/validate-managed-identity.sh`
- **Método/escenario:** `validate_managed_identity_least_privilege`
- **Comando aislado:** `./scripts/tests/validate-managed-identity.sh`
- **Suite:** `./scripts/tests/validate-rbac.sh`

### Evidencia

- **Ruta:** `docs/evidence/security/{runId}/managed-identity-rbac.json`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

No aplica; esta prueba solo consulta configuración y asignaciones.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-011 — Validar contrato OpenAPI de la transacción

### Identificación

- **ID:** `TEST-S1-011`
- **Nombre:** Validar contrato OpenAPI de la transacción
- **Nivel:** Contrato
- **Categoría:** API y contrato
- **Prioridad:** Crítica
- **Ambiente:** Local/CI
- **Requisitos:** `RF-S1-001`, `RF-S1-002`, `RF-S1-003`
- **Flujo:** FM-S1-001
- **Issue(s):** `ISS-S1-007`

### Propósito

Verificar que OpenAPI documenta el endpoint, campos mínimos, tipos, obligatoriedad y respuestas de Semana 1.

### Precondiciones

- Archivo OpenAPI disponible.

### Datos de prueba

- Esquema TransactionRequest y TransactionReceipt.

### Dobles y dependencias

- Validador OpenAPI local.

### Pasos

1. Validar sintaxis OpenAPI.
2. Comprobar campos mínimos y restricciones.
3. Comprobar respuestas 202, 400, 401, 403 y 503.
4. Confirmar ausencia de score, reglas y caseId.

### Resultado esperado

- Contrato válido.
- Campos mínimos coinciden con el modelo documentado.
- No incluye funcionalidades futuras.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado el contrato contiene todos los campos mínimos
  Cuando se ejecuta el validador
  Entonces la especificación es válida

Escenario: Camino alterno
  Dado latitud y longitud se omiten
  Cuando se valida el esquema
  Entonces el payload sigue siendo válido

Escenario: Camino de error
  Dado falta merchant.category o aparece score
  Cuando se valida el contrato
  Entonces la prueba falla
```

### Automatización

- **Archivo:** `src/test/java/com/centinela/transactioningestion/contract/OpenApiContractTest.java`
- **Método/escenario:** `openapi_should_match_week1_transaction_contract`
- **Comando aislado:** `mvn -Dtest=OpenApiContractTest test`
- **Suite:** `mvn verify`

### Evidencia

- **Ruta:** `target/surefire-reports/OpenApiContractTest.txt`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

No aplica.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-012 — Validar campos y límites de TransactionRequest

### Identificación

- **ID:** `TEST-S1-012`
- **Nombre:** Validar campos y límites de TransactionRequest
- **Nivel:** Unitario
- **Categoría:** Validación
- **Prioridad:** Crítica
- **Ambiente:** Local/CI
- **Requisitos:** `RF-S1-002`
- **Flujo:** FM-S1-001
- **Issue(s):** `ISS-S1-007`

### Propósito

Comprobar todas las reglas de validación del payload sin levantar Azure ni Spring completo.

### Precondiciones

- DTO y validador implementados.

### Datos de prueba

- Casos válidos, campos nulos, monto cero/negativo, códigos y coordenadas límite.

### Dobles y dependencias

- Jakarta Validation y objetos locales.

### Pasos

1. Construir payload válido.
2. Variar un campo por caso.
3. Ejecutar el validador.
4. Comparar violaciones esperadas.

### Resultado esperado

- Payload válido sin violaciones.
- Cada campo obligatorio ausente produce error.
- Monto y coordenadas fuera de rango son rechazados.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado todos los campos cumplen el contrato
  Cuando se valida el DTO
  Entonces no hay violaciones

Escenario: Camino alterno
  Dado no se envían coordenadas opcionales
  Cuando se valida el DTO
  Entonces el payload es válido

Escenario: Camino de error
  Dado amount es cero o countryCode tiene longitud incorrecta
  Cuando se valida el DTO
  Entonces se obtiene una violación específica
```

### Automatización

- **Archivo:** `src/test/java/com/centinela/transactioningestion/infrastructure/web/dto/TransactionRequestValidationTest.java`
- **Método/escenario:** `should_validate_transaction_contract`
- **Comando aislado:** `mvn -Dtest=TransactionRequestValidationTest test`
- **Suite:** `mvn test`

### Evidencia

- **Ruta:** `target/surefire-reports/TransactionRequestValidationTest.txt`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

No aplica.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-013 — Mapear únicamente los datos crudos aprobados

### Identificación

- **ID:** `TEST-S1-013`
- **Nombre:** Mapear únicamente los datos crudos aprobados
- **Nivel:** Unitario
- **Categoría:** Mapeo y alcance
- **Prioridad:** Alta
- **Ambiente:** Local/CI
- **Requisitos:** `RF-S1-003`, `RNF-S1-001`
- **Flujo:** FM-S1-001
- **Issue(s):** `ISS-S1-007`

### Propósito

Garantizar que el mapper conserva el contrato y no inventa score, decisión, reglas, caso o evento de Semana 2.

### Precondiciones

- DTO, dominio y mapper implementados.

### Datos de prueba

- Payload sintético completo y payload sin coordenadas opcionales.

### Dobles y dependencias

- No usa mocks externos.

### Pasos

1. Mapear DTO a dominio.
2. Mapear el recibo de dominio a respuesta.
3. Comparar todos los campos.
4. Inspeccionar ausencia de propiedades futuras.

### Resultado esperado

- Los valores se conservan exactamente.
- Campos opcionales ausentes permanecen ausentes.
- La respuesta solo contiene transactionId y RECEIVED.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado el DTO contiene todos los campos
  Cuando se ejecuta el mapper
  Entonces el dominio conserva los valores

Escenario: Camino alterno
  Dado latitud y longitud son nulas
  Cuando se mapea la transacción
  Entonces no se inventan coordenadas

Escenario: Camino de error
  Dado el mapper agrega score o caseId
  Cuando se ejecuta la prueba de igualdad estructural
  Entonces la prueba falla
```

### Automatización

- **Archivo:** `src/test/java/com/centinela/transactioningestion/infrastructure/web/TransactionWebMapperTest.java`
- **Método/escenario:** `should_map_only_week1_fields`
- **Comando aislado:** `mvn -Dtest=TransactionWebMapperTest test`
- **Suite:** `mvn test`

### Evidencia

- **Ruta:** `target/surefire-reports/TransactionWebMapperTest.txt`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

No aplica.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-014 — Persistir antes de emitir el acuse

### Identificación

- **ID:** `TEST-S1-014`
- **Nombre:** Persistir antes de emitir el acuse
- **Nivel:** Unitario
- **Categoría:** Caso de uso y errores
- **Prioridad:** Crítica
- **Ambiente:** Local/CI
- **Requisitos:** `RF-S1-003`, `RF-S1-004`
- **Flujo:** FM-S1-001
- **Issue(s):** `ISS-S1-008`

### Propósito

Verificar que el caso de uso llama al puerto Blob y solo devuelve RECEIVED cuando la persistencia termina correctamente.

### Precondiciones

- Caso de uso y puerto de salida disponibles.

### Datos de prueba

- Transacción sintética y fake/mock del puerto Blob.

### Dobles y dependencias

- Mockito/fake local; no Azure.

### Pasos

1. Configurar almacenamiento exitoso.
2. Ejecutar el caso de uso.
3. Verificar orden de llamada y respuesta.
4. Configurar fallo de Storage y repetir.

### Resultado esperado

- Éxito devuelve RECEIVED después de almacenar.
- Fallo de Storage se propaga como error de disponibilidad.
- Nunca se invoca scoring ni Queue.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado el puerto Blob almacena correctamente
  Cuando se ejecuta el caso de uso
  Entonces se devuelve RECEIVED

Escenario: Camino alterno
  Dado el payload incluye campos opcionales
  Cuando se almacena
  Entonces los campos crudos se conservan

Escenario: Camino de error
  Dado el puerto Blob falla
  Cuando se ejecuta el caso de uso
  Entonces no se devuelve acuse exitoso
```

### Automatización

- **Archivo:** `src/test/java/com/centinela/transactioningestion/application/service/IngestTransactionServiceTest.java`
- **Método/escenario:** `should_ack_only_after_blob_persistence`
- **Comando aislado:** `mvn -Dtest=IngestTransactionServiceTest test`
- **Suite:** `mvn test`

### Evidencia

- **Ruta:** `target/surefire-reports/IngestTransactionServiceTest.txt`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

No aplica.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-015 — Integrar adaptador Blob de transacciones

### Identificación

- **ID:** `TEST-S1-015`
- **Nombre:** Integrar adaptador Blob de transacciones
- **Nivel:** Integración
- **Categoría:** Persistencia Blob
- **Prioridad:** Crítica
- **Ambiente:** Azure staging/integración
- **Requisitos:** `RF-S1-004`, `RS-S1-003`
- **Flujo:** FM-S1-001
- **Issue(s):** `ISS-S1-008`

### Propósito

Comprobar que el adaptador almacena el JSON original en la ruta y contenedor del ambiente correctos mediante identidad/configuración aprobada.

### Precondiciones

- Storage de prueba o staging accesible.
- Contenedor correspondiente creado.

### Datos de prueba

- transactionId único y fecha controlada.

### Dobles y dependencias

- Azure SDK y Storage real de integración; sin connection string en repositorio.

### Pasos

1. Invocar el adaptador.
2. Consultar el Blob creado.
3. Validar ruta, contenido y metadatos mínimos.
4. Repetir en ambiente staging.

### Resultado esperado

- Ruta `yyyy/MM/dd/{transactionId}.json`.
- Contenido equivalente al payload original.
- Nunca escribe en el contenedor del otro ambiente.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado Storage está disponible
  Cuando el adaptador persiste
  Entonces el Blob aparece en la ruta esperada

Escenario: Camino alterno
  Dado se ejecuta en staging
  Cuando se persiste la transacción
  Entonces solo se usa el contenedor staging

Escenario: Camino de error
  Dado Storage rechaza la operación
  Cuando el adaptador intenta persistir
  Entonces devuelve una excepción técnica traducible a 503
```

### Automatización

- **Archivo:** `src/test/java/com/centinela/transactioningestion/infrastructure/azure/blob/AzureRawTransactionBlobAdapterIT.java`
- **Método/escenario:** `should_store_raw_transaction_in_environment_container`
- **Comando aislado:** `mvn -Dtest=AzureRawTransactionBlobAdapterIT verify`
- **Suite:** `mvn verify`

### Evidencia

- **Ruta:** `docs/evidence/storage/{runId}/transaction-blob-it.md`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

Eliminar los blobs creados por el test.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-016 — Recibir y almacenar una transacción válida desplegada

### Identificación

- **ID:** `TEST-S1-016`
- **Nombre:** Recibir y almacenar una transacción válida desplegada
- **Nivel:** E2E
- **Categoría:** API de ingesta
- **Prioridad:** Crítica
- **Ambiente:** Azure staging
- **Requisitos:** `RF-S1-001`, `RF-S1-003`, `RF-S1-004`, `RNF-S1-001`
- **Flujo:** FM-S1-001
- **Issue(s):** `ISS-S1-008`, `ISS-S1-011`

### Propósito

Demostrar el camino completo Servicio → App Service → validación → caso de uso → Blob → acuse, sin análisis.

### Precondiciones

- API desplegada en staging.
- Token SERVICE válido.
- Storage privado accesible desde la aplicación.

### Datos de prueba

- Payload sintético válido con transactionId único.

### Dobles y dependencias

- App Service, Entra ID y Blob reales.

### Pasos

1. Enviar POST con token SERVICE.
2. Registrar respuesta.
3. Consultar el Blob esperado por identidad autorizada.
4. Comparar contenido.
5. Confirmar ausencia de score/case/evento.

### Resultado esperado

- HTTP 202 con RECEIVED.
- Existe el Blob correcto.
- No se ejecuta scoring ni se publica un mensaje de negocio.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado el Servicio está autenticado y el payload es válido
  Cuando envía la transacción
  Entonces recibe 202 y el Blob existe

Escenario: Camino alterno
  Dado se omiten coordenadas opcionales
  Cuando se envía la transacción
  Entonces se acepta y almacena

Escenario: Camino de error
  Dado Blob no está disponible
  Cuando se envía una transacción válida
  Entonces la API devuelve 503 y no 202
```

### Automatización

- **Archivo:** `scripts/tests/test-transaction-e2e.sh`
- **Método/escenario:** `test_valid_transaction_end_to_end`
- **Comando aislado:** `./scripts/tests/test-transaction-e2e.sh`
- **Suite:** `./scripts/validate-week1.sh`

### Evidencia

- **Ruta:** `docs/evidence/api/{runId}/transaction-e2e.md`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

Eliminar el Blob sintético después de conservar evidencia.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-017 — Rechazar payload inválido sin persistir

### Identificación

- **ID:** `TEST-S1-017`
- **Nombre:** Rechazar payload inválido sin persistir
- **Nivel:** Integración
- **Categoría:** API y validación
- **Prioridad:** Crítica
- **Ambiente:** Local/CI
- **Requisitos:** `RF-S1-002`
- **Flujo:** FM-S1-001
- **Issue(s):** `ISS-S1-007`, `ISS-S1-008`

### Propósito

Comprobar que la API responde 400 para payloads inválidos y no crea Blobs.

### Precondiciones

- Controller y manejo de errores implementados.

### Datos de prueba

- Matriz de payloads: campo faltante, tipo incorrecto, monto no positivo, fecha inválida.

### Dobles y dependencias

- MockMvc o aplicación de integración; puerto Blob espiado/fake.

### Pasos

1. Enviar cada payload inválido.
2. Verificar código y error.
3. Confirmar que el puerto Blob no fue invocado.

### Resultado esperado

- HTTP 400.
- Respuesta de error estable.
- Cero persistencias.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz de validación
  Dado el payload es válido
  Cuando se procesa la validación
  Entonces no se genera error 400

Escenario: Camino alterno
  Dado faltan coordenadas opcionales
  Cuando se valida
  Entonces la solicitud continúa

Escenario: Camino de error
  Dado falta transactionId o amount es negativo
  Cuando se envía la solicitud
  Entonces se devuelve 400 y no se almacena
```

### Automatización

- **Archivo:** `src/test/java/com/centinela/transactioningestion/infrastructure/web/TransactionApiValidationIT.java`
- **Método/escenario:** `should_reject_invalid_payload_without_storage`
- **Comando aislado:** `mvn -Dtest=TransactionApiValidationIT test`
- **Suite:** `mvn verify`

### Evidencia

- **Ruta:** `target/surefire-reports/TransactionApiValidationIT.txt`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

No aplica.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-018 — Validar documento y normalizar nombre

### Identificación

- **ID:** `TEST-S1-018`
- **Nombre:** Validar documento y normalizar nombre
- **Nivel:** Unitario
- **Categoría:** Documentos y seguridad
- **Prioridad:** Alta
- **Ambiente:** Local/CI
- **Requisitos:** `RF-S1-005`
- **Flujo:** FM-S1-002
- **Issue(s):** `ISS-S1-009`

### Propósito

Verificar archivo obligatorio/no vacío y prevenir traversal o nombres físicos inseguros.

### Precondiciones

- Caso de uso documental disponible.

### Datos de prueba

- Archivo válido, vacío, sin nombre y nombre con `../` o separadores.

### Dobles y dependencias

- Mock/fake del puerto de almacenamiento.

### Pasos

1. Enviar archivo válido.
2. Enviar archivo vacío.
3. Enviar nombre peligroso.
4. Verificar nombre físico normalizado.

### Resultado esperado

- Archivo válido se entrega al puerto.
- Archivo vacío es rechazado.
- No se construyen rutas fuera del prefijo documentId.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado el archivo tiene contenido y nombre válido
  Cuando se almacena
  Entonces se genera documentId y nombre seguro

Escenario: Camino alterno
  Dado el nombre contiene espacios o caracteres normalizables
  Cuando se procesa
  Entonces se conserva un nombre seguro

Escenario: Camino de error
  Dado el archivo está vacío o intenta `../`
  Cuando se valida
  Entonces la operación es rechazada o normalizada sin escapar la ruta
```

### Automatización

- **Archivo:** `src/test/java/com/centinela/documentstorage/application/StoreVerificationDocumentServiceTest.java`
- **Método/escenario:** `should_validate_and_normalize_document`
- **Comando aislado:** `mvn -Dtest=StoreVerificationDocumentServiceTest test`
- **Suite:** `mvn test`

### Evidencia

- **Ruta:** `target/surefire-reports/StoreVerificationDocumentServiceTest.txt`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

No aplica.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-019 — Cargar documento desde la API y comprobar Blob

### Identificación

- **ID:** `TEST-S1-019`
- **Nombre:** Cargar documento desde la API y comprobar Blob
- **Nivel:** E2E
- **Categoría:** Documentos y almacenamiento
- **Prioridad:** Crítica
- **Ambiente:** Azure staging
- **Requisitos:** `RF-S1-005`, `RS-S1-003`
- **Flujo:** FM-S1-002
- **Issue(s):** `ISS-S1-009`, `ISS-S1-011`

### Propósito

Demostrar que un Analista autenticado carga un archivo y que queda almacenado en el contenedor del ambiente.

### Precondiciones

- API staging desplegada.
- Token ANALYST válido.

### Datos de prueba

- Archivo sintético sin PII y nombre seguro.

### Dobles y dependencias

- App Service, Entra ID y Blob reales.

### Pasos

1. Enviar multipart con `file`.
2. Verificar 201 y documentId.
3. Consultar el Blob por la ruta documentada.
4. Comparar bytes y metadatos.

### Resultado esperado

- HTTP 201 con STORED.
- Blob existente en contenedor documental staging.
- No se requiere caseId.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado un Analista autenticado tiene un archivo no vacío
  Cuando lo carga
  Entonces recibe 201 y el Blob existe

Escenario: Camino alterno
  Dado el archivo tiene un nombre normalizable
  Cuando se carga
  Entonces la ruta física es segura

Escenario: Camino de error
  Dado Storage documental falla
  Cuando se intenta cargar
  Entonces la API devuelve 503 y no 201
```

### Automatización

- **Archivo:** `scripts/tests/test-document-upload-e2e.sh`
- **Método/escenario:** `test_document_upload_end_to_end`
- **Comando aislado:** `./scripts/tests/test-document-upload-e2e.sh`
- **Suite:** `./scripts/validate-week1.sh`

### Evidencia

- **Ruta:** `docs/evidence/documents/{runId}/document-upload.md`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

Eliminar el archivo sintético tras registrar evidencia.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-020 — Validar roundtrip de Queue Storage

### Identificación

- **ID:** `TEST-S1-020`
- **Nombre:** Validar roundtrip de Queue Storage
- **Nivel:** Integración
- **Categoría:** Queue e infraestructura
- **Prioridad:** Crítica
- **Ambiente:** Azure integrado
- **Requisitos:** `RF-S1-006`
- **Flujo:** FM-S1-003
- **Issue(s):** `ISS-S1-010`

### Propósito

Demostrar escritura, lectura y eliminación de un mensaje técnico sin convertirlo en contrato de negocio.

### Precondiciones

- Cola del ambiente creada.
- Identidad temporal mínima autorizada para la prueba.

### Datos de prueba

- Mensaje con testRunId, environment y createdAt; sin campos de scoring.

### Dobles y dependencias

- Azure Queue Storage real y conectividad privada.

### Pasos

1. Enviar mensaje técnico.
2. Leer hasta encontrar el mismo testRunId.
3. Validar contenido.
4. Eliminar usando pop receipt.
5. Confirmar que no quedan residuos del run.

### Resultado esperado

- El mismo mensaje se escribe y lee.
- Se elimina correctamente.
- No existe productor/consumidor Java ni contrato futuro.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado la cola está disponible y la identidad tiene permiso temporal
  Cuando se ejecuta el roundtrip
  Entonces el mensaje se valida y elimina

Escenario: Camino alterno
  Dado la cola tarda en entregar el mensaje
  Cuando se aplican reintentos limitados
  Entonces el mensaje se recupera dentro del límite

Escenario: Camino de error
  Dado no se recupera el mensaje
  Cuando se agotan reintentos
  Entonces la prueba falla y limpia lo que pueda
```

### Automatización

- **Archivo:** `scripts/tests/test-queue-roundtrip.sh`
- **Método/escenario:** `test_queue_write_read_delete`
- **Comando aislado:** `./scripts/tests/test-queue-roundtrip.sh staging`
- **Suite:** `./scripts/validate-week1.sh`

### Evidencia

- **Ruta:** `docs/evidence/queue/{runId}/queue-roundtrip.md`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

Eliminar el mensaje y revocar permisos temporales si fueron creados.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-021 — Autorizar únicamente Servicio en transacciones

### Identificación

- **ID:** `TEST-S1-021`
- **Nombre:** Autorizar únicamente Servicio en transacciones
- **Nivel:** Integración
- **Categoría:** Seguridad HTTP
- **Prioridad:** Crítica
- **Ambiente:** Local/CI
- **Requisitos:** `RS-S1-001`
- **Flujo:** FM-S1-001
- **Issue(s):** `ISS-S1-011`

### Propósito

Comprobar autenticación y autorización del endpoint de transacciones.

### Precondiciones

- Spring Security configurado.

### Datos de prueba

- Sin token, token SERVICE, token ANALYST, ADMINISTRATOR y AUDITOR.

### Dobles y dependencias

- JWT de prueba en integración; E2E opcional con Entra para la evidencia final.

### Pasos

1. Invocar sin token.
2. Invocar con SERVICE.
3. Invocar con cada rol no permitido.

### Resultado esperado

- Sin token 401.
- SERVICE puede continuar hasta validación/almacenamiento.
- Los demás roles reciben 403.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado el token contiene SERVICE
  Cuando se llama POST transactions
  Entonces la autorización permite la operación

Escenario: Camino alterno
  Dado el token es válido pero pertenece a ANALYST
  Cuando se llama el endpoint
  Entonces se devuelve 403

Escenario: Camino de error
  Dado no existe token o es inválido
  Cuando se llama el endpoint
  Entonces se devuelve 401 sin filtrar detalles
```

### Automatización

- **Archivo:** `src/test/java/com/centinela/identityaccess/TransactionEndpointAuthorizationIT.java`
- **Método/escenario:** `should_authorize_only_service`
- **Comando aislado:** `mvn -Dtest=TransactionEndpointAuthorizationIT test`
- **Suite:** `mvn verify`

### Evidencia

- **Ruta:** `target/surefire-reports/TransactionEndpointAuthorizationIT.txt`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

No aplica.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-022 — Autorizar únicamente Analista en carga documental

### Identificación

- **ID:** `TEST-S1-022`
- **Nombre:** Autorizar únicamente Analista en carga documental
- **Nivel:** Integración
- **Categoría:** Seguridad HTTP
- **Prioridad:** Crítica
- **Ambiente:** Local/CI
- **Requisitos:** `RS-S1-001`, `RF-S1-005`
- **Flujo:** FM-S1-002
- **Issue(s):** `ISS-S1-011`

### Propósito

Comprobar que el documento solo puede ser cargado por Analista, conforme al actor descrito en los documentos fuente.

### Precondiciones

- Spring Security configurado.

### Datos de prueba

- Sin token y tokens ANALYST, SERVICE, ADMINISTRATOR y AUDITOR.

### Dobles y dependencias

- JWT de prueba.

### Pasos

1. Invocar con ANALYST.
2. Invocar sin token.
3. Invocar con cada rol no permitido.

### Resultado esperado

- ANALYST puede continuar.
- Sin token 401.
- SERVICE, ADMINISTRATOR y AUDITOR reciben 403.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado el token contiene ANALYST
  Cuando se carga un archivo válido
  Entonces la autorización permite la operación

Escenario: Camino alterno
  Dado el token contiene AUDITOR
  Cuando se intenta cargar
  Entonces se devuelve 403 porque es solo lectura

Escenario: Camino de error
  Dado no hay token
  Cuando se intenta cargar
  Entonces se devuelve 401
```

### Automatización

- **Archivo:** `src/test/java/com/centinela/identityaccess/DocumentEndpointAuthorizationIT.java`
- **Método/escenario:** `should_authorize_only_analyst`
- **Comando aislado:** `mvn -Dtest=DocumentEndpointAuthorizationIT test`
- **Suite:** `mvn verify`

### Evidencia

- **Ruta:** `target/surefire-reports/DocumentEndpointAuthorizationIT.txt`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

No aplica.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-023 — Confirmar aislamiento funcional entre staging y producción

### Identificación

- **ID:** `TEST-S1-023`
- **Nombre:** Confirmar aislamiento funcional entre staging y producción
- **Nivel:** E2E
- **Categoría:** Configuración por ambiente
- **Prioridad:** Alta
- **Ambiente:** Azure staging/production
- **Requisitos:** `RF-S1-007`
- **Flujo:** FM-S1-001 y FM-S1-002
- **Issue(s):** `ISS-S1-004`, `ISS-S1-008`, `ISS-S1-009`

### Propósito

Demostrar que cada ambiente usa sus propias variables, contenedores y colas lógicas.

### Precondiciones

- Producción y slot staging desplegados.

### Datos de prueba

- Una transacción y un documento sintéticos con IDs distintos por ambiente.

### Dobles y dependencias

- App Service y Storage reales.

### Pasos

1. Enviar datos a staging.
2. Comprobar recursos staging.
3. Confirmar que no aparecen en production.
4. Comparar app settings sin revelar valores sensibles.

### Resultado esperado

- Los datos de staging solo aparecen en staging.
- Las variables no apuntan al mismo recurso lógico.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado staging tiene sus variables propias
  Cuando recibe una transacción
  Entonces el Blob se crea en raw-transactions-staging

Escenario: Camino alterno
  Dado se carga un documento en staging
  Cuando se consulta Storage
  Entonces solo aparece en verification-documents-staging

Escenario: Camino de error
  Dado una variable staging apunta a production
  Cuando se ejecuta la validación
  Entonces la prueba falla
```

### Automatización

- **Archivo:** `scripts/tests/test-environment-isolation.sh`
- **Método/escenario:** `test_staging_production_isolation`
- **Comando aislado:** `./scripts/tests/test-environment-isolation.sh`
- **Suite:** `./scripts/validate-week1.sh`

### Evidencia

- **Ruta:** `docs/evidence/appservice/{runId}/environment-isolation.md`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

Eliminar datos sintéticos de ambos ambientes.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-024 — Mantener disponibilidad al retirar una instancia

### Identificación

- **ID:** `TEST-S1-024`
- **Nombre:** Mantener disponibilidad al retirar una instancia
- **Nivel:** E2E
- **Categoría:** Disponibilidad y resiliencia
- **Prioridad:** Crítica
- **Ambiente:** Azure integrado
- **Requisitos:** `RI-S1-005`, `RNF-S1-002`
- **Flujo:** FM-S1-005
- **Issue(s):** `ISS-S1-012`

### Propósito

Demostrar que con dos instancias temporales la API continúa respondiendo cuando una deja de atender, sin perder transacciones aceptadas.

### Precondiciones

- Pruebas funcionales y de seguridad aprobadas.
- Capacidad inicial en una instancia.
- Permiso temporal para escalar.

### Datos de prueba

- Carga controlada de transacciones sintéticas con IDs únicos.

### Dobles y dependencias

- App Service real y script de carga.

### Pasos

1. Escalar a dos instancias.
2. Esperar ambas listas.
3. Iniciar carga controlada.
4. Retirar/reiniciar una instancia.
5. Continuar carga.
6. Reconciliar cada 202 con su Blob.
7. Volver a una instancia.

### Resultado esperado

- La API sigue respondiendo.
- No existe 202 sin Blob.
- La capacidad final vuelve a una instancia para controlar costos.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado dos instancias atienden la API
  Cuando se retira una durante la carga
  Entonces la otra mantiene el servicio y los 202 tienen Blob

Escenario: Camino alterno
  Dado algunas solicitudes reciben error transitorio no aceptado
  Cuando se reconcilian resultados
  Entonces solo se exige Blob para solicitudes 202

Escenario: Camino de error
  Dado no se puede alcanzar dos instancias
  Cuando se inicia la prueba
  Entonces se detiene y no se declara alta disponibilidad
```

### Automatización

- **Archivo:** `scripts/test-ha.sh`
- **Método/escenario:** `test_single_instance_failure_continuity`
- **Comando aislado:** `./scripts/test-ha.sh`
- **Suite:** `./scripts/validate-week1.sh`

### Evidencia

- **Ruta:** `docs/evidence/ha/{runId}/ha-summary.md`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

Detener carga, volver a una instancia y limpiar Blobs sintéticos.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-025 — Validar entregables documentales y trazabilidad

### Identificación

- **ID:** `TEST-S1-025`
- **Nombre:** Validar entregables documentales y trazabilidad
- **Nivel:** Estático
- **Categoría:** Documentación
- **Prioridad:** Alta
- **Ambiente:** Local/CI
- **Requisitos:** `RI-S1-001`, `RS-S1-001`, `RI-S1-003`
- **Flujo:** Transversal
- **Issue(s):** `ISS-S1-013`

### Propósito

Comprobar que README, matriz de roles, diagrama de red, ADR y matriz de trazabilidad existen y reflejan lo implementado.

### Precondiciones

- Issues 001 a 012 completadas o con evidencia real disponible.

### Datos de prueba

- Lista de entregables y referencias a evidencia.

### Dobles y dependencias

- Script de validación documental.

### Pasos

1. Verificar existencia de archivos.
2. Validar enlaces y IDs.
3. Comparar matriz de roles con scripts y seguridad.
4. Confirmar que el diagrama muestra subredes y reglas.
5. Confirmar ADR de clasificación cloud y red.

### Resultado esperado

- Todos los entregables requeridos existen.
- No hay decisiones no aprobadas de Semana 2.
- No se declara evidencia inexistente.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado los documentos están completos y enlazados
  Cuando se ejecuta la validación
  Entonces todos los controles pasan

Escenario: Camino alterno
  Dado una evidencia se conserva como log sanitizado en vez de captura
  Cuando se valida la ruta
  Entonces se acepta si contiene commit, runId y timestamp

Escenario: Camino de error
  Dado falta la matriz de roles o el diagrama
  Cuando se valida el paquete
  Entonces la prueba falla
```

### Automatización

- **Archivo:** `scripts/tests/validate-documentation.sh`
- **Método/escenario:** `validate_week1_deliverables`
- **Comando aislado:** `./scripts/tests/validate-documentation.sh`
- **Suite:** `./scripts/validate-week1.sh`

### Evidencia

- **Ruta:** `docs/evidence/final/{runId}/documentation-validation.md`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

No aplica.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-026 — Desplegar desde una suscripción o Resource Group limpio

### Identificación

- **ID:** `TEST-S1-026`
- **Nombre:** Desplegar desde una suscripción o Resource Group limpio
- **Nivel:** E2E
- **Categoría:** Infraestructura reproducible
- **Prioridad:** Crítica
- **Ambiente:** Azure integrado
- **Requisitos:** `RI-S1-001`, `RNF-S1-003`, `RNF-S1-004`
- **Flujo:** FM-S1-004
- **Issue(s):** `ISS-S1-002`, `ISS-S1-003`, `ISS-S1-004`, `ISS-S1-005`, `ISS-S1-006`, `ISS-S1-014`

### Propósito

Demostrar que todos los recursos de Semana 1 se crean mediante scripts sin intervención manual.

### Precondiciones

- Resource Group objetivo inexistente.
- Azure CLI autenticado.
- Parámetros y cuota disponibles.

### Datos de prueba

- Prefijo único y parámetros aprobados.

### Dobles y dependencias

- Azure real.

### Pasos

1. Confirmar ausencia del Resource Group.
2. Ejecutar deploy-week1.sh.
3. Ejecutar inventario y validaciones de infraestructura.
4. Registrar comandos y duración.

### Resultado esperado

- Despliegue termina con código 0.
- Existen únicamente los recursos de alcance.
- No fue necesario completar pasos manuales en Portal.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado el Resource Group no existe y los parámetros son válidos
  Cuando se ejecuta el script
  Entonces se crea toda la infraestructura requerida

Escenario: Camino alterno
  Dado un comando transitorio falla y el script aplica reintento limitado
  Cuando se reintenta
  Entonces el despliegue continúa sin duplicar recursos

Escenario: Camino de error
  Dado un recurso obligatorio no puede crearse
  Cuando se ejecuta el despliegue
  Entonces falla, registra evidencia y no declara éxito
```

### Automatización

- **Archivo:** `scripts/tests/test-clean-deploy.sh`
- **Método/escenario:** `test_deploy_from_clean_environment`
- **Comando aislado:** `./scripts/tests/test-clean-deploy.sh`
- **Suite:** `./scripts/validate-week1.sh`

### Evidencia

- **Ruta:** `docs/evidence/final/{runId}/clean-deploy.log`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

Mantener temporalmente el entorno para las pruebas siguientes o ejecutar limpieza segura si el despliegue quedó inconsistente.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-027 — Destruir, reconstruir, validar y limpiar

### Identificación

- **ID:** `TEST-S1-027`
- **Nombre:** Destruir, reconstruir, validar y limpiar
- **Nivel:** E2E
- **Categoría:** Infraestructura reproducible y costos
- **Prioridad:** Crítica
- **Ambiente:** Azure integrado
- **Requisitos:** `RI-S1-006`, `RNF-S1-002`, `RNF-S1-004`
- **Flujo:** FM-S1-004
- **Issue(s):** `ISS-S1-014`

### Propósito

Cerrar la Semana 1 demostrando destrucción y reconstrucción completa, seguida de limpieza final para no consumir crédito.

### Precondiciones

- Documentación y pruebas anteriores aprobadas.
- Resource Group conocido.

### Datos de prueba

- Mismos parámetros del despliegue final.

### Dobles y dependencias

- Azure real y scripts de deploy/destroy.

### Pasos

1. Destruir el entorno.
2. Confirmar ausencia.
3. Reconstruir desde cero.
4. Ejecutar smoke y validación completa.
5. Guardar evidencia.
6. Volver a una instancia.
7. Destruir finalmente y confirmar ausencia.

### Resultado esperado

- El ciclo no requiere Portal.
- La reconstrucción produce el entorno esperado.
- La limpieza final elimina los recursos activos.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado el entorno existe y las pruebas previas pasaron
  Cuando se destruye, reconstruye, valida y destruye
  Entonces el ciclo termina sin recursos activos

Escenario: Camino alterno
  Dado se conserva el entorno por una demostración inmediata aprobada
  Cuando se documenta la excepción
  Entonces queda responsable y hora exacta de eliminación

Escenario: Camino de error
  Dado la reconstrucción falla
  Cuando se ejecuta el cierre
  Entonces se guarda evidencia, se limpia lo creado y no se declara DONE
```

### Automatización

- **Archivo:** `scripts/tests/test-destroy-rebuild-cleanup.sh`
- **Método/escenario:** `test_full_lifecycle`
- **Comando aislado:** `./scripts/tests/test-destroy-rebuild-cleanup.sh`
- **Suite:** `./scripts/validate-week1.sh`

### Evidencia

- **Ruta:** `docs/evidence/final/{runId}/lifecycle-summary.md`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

Confirmar que el Resource Group no existe; cualquier excepción debe tener responsable y fecha de eliminación.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## TEST-S1-028 — Verificar que no se implementó alcance de Semana 2

### Identificación

- **ID:** `TEST-S1-028`
- **Nombre:** Verificar que no se implementó alcance de Semana 2
- **Nivel:** Estático
- **Categoría:** Control de alcance
- **Prioridad:** Crítica
- **Ambiente:** Local/CI
- **Requisitos:** `RNF-S1-001`
- **Flujo:** Transversal
- **Issue(s):** `ISS-S1-001`, `ISS-S1-007`, `ISS-S1-008`, `ISS-S1-009`, `ISS-S1-010`, `ISS-S1-013`

### Propósito

Mantener abierta la evolución hacia Semana 2 comprobando que no existen scoring, reglas, casos, consumidor, bases futuras ni IA.

### Precondiciones

- Repositorio completo.

### Datos de prueba

- Patrones de paquetes, clases, endpoints y campos prohibidos.

### Dobles y dependencias

- Script estático y prueba de reflexión/esquema.

### Pasos

1. Buscar paquetes y clases futuras.
2. Inspeccionar OpenAPI.
3. Inspeccionar modelos de transacción/documento.
4. Confirmar que Queue solo aparece en scripts técnicos de validación.

### Resultado esperado

- No existen módulos futuros.
- El contrato no contiene score, decision, rules o caseId.
- No existe productor/consumidor de negocio para Queue.

### Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado el repositorio contiene solo Semana 1
  Cuando se ejecuta el control de alcance
  Entonces la prueba pasa

Escenario: Camino alterno
  Dado la documentación menciona Semana 2 únicamente como fuera de alcance
  Cuando se inspecciona
  Entonces la mención está permitida

Escenario: Camino de error
  Dado aparece una clase ScoringService o QueueConsumer
  Cuando se ejecuta el control
  Entonces la prueba falla
```

### Automatización

- **Archivo:** `scripts/tests/validate-week1-scope.sh`
- **Método/escenario:** `validate_no_week2_implementation`
- **Comando aislado:** `./scripts/tests/validate-week1-scope.sh`
- **Suite:** `mvn verify && ./scripts/tests/validate-week1-scope.sh`

### Evidencia

- **Ruta:** `docs/evidence/repository/{runId}/scope-validation.md`
- **Identificación mínima:** commit, ambiente, runId y timestamp UTC.
- **Contenido:** resultado, efectos verificados y datos sanitizados.

### Limpieza

Eliminar cualquier fixture futuro usado para probar el detector.

### Definition of Done del caso

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Camino feliz, alterno y de error verificados.
- [ ] Resultado y efectos que NO deben ocurrir comprobados.
- [ ] Evidencia guardada y enlazada.
- [ ] Datos y recursos temporales limpiados.
- [ ] Sin secretos ni PII real.
- [ ] Trazabilidad actualizada.
- [ ] Revisado por una persona distinta a quien implementó la issue.


## Exclusiones expresas

No se prueban score, reglas, umbral, casos, consumidores, Functions, IA, bases de datos futuras ni contrato de evento de Semana 2. Cuando llegue el alcance oficial, se agregarán nuevos IDs sin reescribir las pruebas estables de Semana 1 salvo cambio formal del contrato.
