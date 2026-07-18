# 07 — Backlog implementable de Semana 1

## Propósito

Este documento traduce únicamente `0_Vision/2_Alcance_Semana1.md` y `0_Vision/1_Vision_Producto.md` a 14 issues implementables. Conserva la estructura completa: descripción técnica, archivos, criterios de aceptación, pruebas por nivel, Gherkin, Definition of Done, comandos y evidencia.

No autoriza scoring, reglas de fraude, apertura de casos, consumidor de cola, bases de datos de Semana 2, IA ni CI/CD obligatorio.

## Distribución consecutiva para cinco personas

| Persona | Issues asignadas | Entrega principal | Puede depender de |
|---|---|---|---|
| Persona 1 | `ISS-S1-001` a `ISS-S1-004` | Base Java, scripts, Storage y App Service | Solo issues del mismo bloque con número menor. |
| Persona 2 | `ISS-S1-005` a `ISS-S1-009` | Red, identidad/RBAC, contrato, ingesta y documentos | Issues `001–004` y números menores de su bloque. |
| Persona 3 | `ISS-S1-010` a `ISS-S1-011` | Validación de Queue y seguridad HTTP | Issues `001–009`. |
| Persona 4 | `ISS-S1-012` a `ISS-S1-013` | Alta disponibilidad, documentación y evidencias | Issues `001–011`. |
| Persona 5 | `ISS-S1-014` | Destrucción, reconstrucción y cierre final | Issues `001–013`. |

La asignación es consecutiva para reducir conflictos. Los bloques no tienen el mismo número de issues porque su esfuerzo no es equivalente. Persona 5 también realiza revisión cruzada durante la semana, aunque su issue de cierre sea la última.

### Regla obligatoria de dependencias

- Ninguna issue puede depender de una issue con número mayor.
- Una persona puede trabajar internamente las issues de su bloque en el orden indicado.
- Un archivo compartido se modifica solo después del traspaso del bloque anterior.
- Las pruebas posteriores de integración no convierten una issue futura en dependencia para iniciar o cerrar una issue temprana.

## Jerarquía del backlog

### EPIC-S1-001 — Fundamentos operativos de Centinela

Objetivo: entregar la base segura, reproducible y verificable para recibir y almacenar transacciones sin ejecutar análisis de fraude.

| Feature | Historia | Resultado de negocio | Issues |
|---|---|---|---|
| FEAT-S1-001 Infraestructura reproducible | HU-S1-001 Como equipo quiero desplegar y retirar los recursos por scripts. | Entorno reconstruible y control de costos. | ISS-S1-002, 003, 004, 005, 014 |
| FEAT-S1-002 Identidad y acceso mínimo | HU-S1-002 Como administrador quiero roles e identidades con mínimo privilegio. | Acceso seguro a Azure y a la API. | ISS-S1-006, 011 |
| FEAT-S1-003 Ingesta cruda de transacciones | HU-S1-003 Como sistema originador quiero enviar una transacción y recibir acuse. | Transacción validada y almacenada. | ISS-S1-001, 007, 008 |
| FEAT-S1-004 Almacenamiento complementario | HU-S1-004 Como analista quiero cargar documentos y como equipo validar una cola. | Documento almacenado y cola técnicamente verificada. | ISS-S1-009, 010 |
| FEAT-S1-005 Disponibilidad y evidencia | HU-S1-005 Como equipo quiero demostrar continuidad y conservar evidencia. | Prueba HA, trazabilidad y cierre reproducible. | ISS-S1-012, 013, 014 |

## Mapa de ejecución

| ID | Persona | Título | Dependencias para iniciar | Resultado verificable |
|---|---|---|---|---|
| ISS-S1-001 | 1 | Preparar repositorio Java y estructura hexagonal | — | Proyecto Java 21 compila y respeta límites de capas. |
| ISS-S1-002 | 1 | Crear scripts base de infraestructura y control de costos | — | Scripts parametrizados y seguros. |
| ISS-S1-003 | 1 | Crear Storage, contenedores y colas por ambiente | ISS-S1-002 | Storage privado y recursos lógicos separados. |
| ISS-S1-004 | 1 | Crear App Service, Managed Identity y slot staging | ISS-S1-002 | Producción y staging existen con configuración separada. |
| ISS-S1-005 | 2 | Crear VNet, subredes, DNS y Private Endpoints | ISS-S1-002, 003, 004 | Storage accesible privadamente desde la aplicación. |
| ISS-S1-006 | 2 | Configurar Entra ID, roles y RBAC mínimo | ISS-S1-002, 003, 004 | Roles creados y permisos mínimos aplicados. |
| ISS-S1-007 | 2 | Documentar e implementar contrato de transacción | ISS-S1-001 | OpenAPI, DTO, mapper y validaciones coinciden. |
| ISS-S1-008 | 2 | Persistir transacción cruda en Blob | ISS-S1-003..ISS-S1-007 | `202` solo después de almacenar el JSON. |
| ISS-S1-009 | 2 | Implementar carga técnica de documentos | ISS-S1-001, 003..007 | Archivo válido devuelve `201` y queda almacenado. |
| ISS-S1-010 | 3 | Validar escritura, lectura y eliminación en Queue Storage | ISS-S1-003, 005, 006 | Roundtrip técnico sin contrato de Semana 2. |
| ISS-S1-011 | 3 | Proteger endpoints y verificar mínimo privilegio | ISS-S1-006, 007, 009 | `401`, `403` y accesos permitidos por rol. |
| ISS-S1-012 | 4 | Probar alta disponibilidad de la API | ISS-S1-004, 005, 006, 008, 011 | Retirar una instancia no interrumpe la ingesta aceptada. |
| ISS-S1-013 | 4 | Completar README, matriz, diagrama, ADR y evidencias | ISS-S1-001..012 | Entregables completos y trazables. |
| ISS-S1-014 | 5 | Ejecutar destrucción, reconstrucción y cierre final | ISS-S1-013 | Ciclo reproducible y recursos eliminados. |

## Tipos de prueba utilizados

- **Estático:** estructura, arquitectura, secretos, documentación y alcance sin ejecutar un flujo desplegado.
- **Unitario:** una clase o función aislada con mocks/fakes, sin Spring completo ni Azure.
- **Contrato:** coherencia de OpenAPI, DTOs, campos, tipos y respuestas.
- **Integración:** interacción entre componentes o con un recurso real controlado.
- **E2E:** recorrido completo sobre el sistema desplegado.

La categoría indica qué se verifica —seguridad, red, API, infraestructura, disponibilidad, etc.— y no reemplaza al nivel.

## Regla sobre pruebas tempranas y posteriores

- **Obligatorias para cerrar la issue:** ejecutables con lo construido en esa issue y sus dependencias anteriores.
- **Posteriores de integración:** se ejecutan cuando el sistema integrado está disponible y son obligatorias para cerrar la Semana 1.

## ISS-S1-001 — Preparar repositorio Java y estructura hexagonal

### Metadatos

- **Historia:** HU-S1-003
- **Feature:** FEAT-S1-003
- **Responsable principal:** Persona 1
- **Revisor:** Persona 5
- **Dependencias para iniciar:** Ninguna
- **Estimación orientativa:** 0,5–1 día
- **Flujo:** FM-S1-001
- **Requisitos:** RF-S1-001..004; RNF-S1-001
- **Pruebas catalogadas:** TEST-S1-001, TEST-S1-002, TEST-S1-028

### 1. Objetivo

Crear la base Java 21/Spring Boot y la estructura modular hexagonal sobre la que se implementarán los dos endpoints de Semana 1.

### 2. Contexto y razón técnica

Sin una estructura inicial estable, cada integrante puede introducir paquetes, dependencias o accesos directos al SDK de Azure incompatibles. Esta issue fija los límites técnicos sin implementar todavía lógica de negocio.

### 3. Descripción técnica

- Crear un proyecto Maven con Java 21 y Spring Boot.
- Incluir dependencias mínimas para Web, Bean Validation, OAuth2 Resource Server, Actuator, Azure Blob Storage, Azure Queue Storage y pruebas.
- Crear los módulos lógicos `transactioningestion`, `documentstorage`, `identityaccess` y `shared` usando paquetes de dominio, aplicación, puertos e infraestructura.
- Crear una prueba de arquitectura que impida que dominio/aplicación dependan de controladores, SDK de Azure o clases de infraestructura.
- Configurar compilación, formato básico, perfiles de prueba y exclusión de archivos locales o secretos.
- No crear todavía controladores funcionales, adaptadores Azure ni reglas de fraude.

### 4. Fuera de alcance

- Endpoints funcionales.
- Scripts Azure.
- Scoring, reglas, casos, IA o consumidor de cola.
- Elección de bases de datos para Semana 2.

### 5. Archivos que deben crearse

```text
pom.xml
.gitignore
src/main/java/com/centinela/CentinelaApplication.java
src/main/java/com/centinela/transactioningestion/{domain,application,infrastructure}/package-info.java
src/main/java/com/centinela/documentstorage/{domain,application,infrastructure}/package-info.java
src/main/java/com/centinela/identityaccess/package-info.java
src/main/java/com/centinela/shared/package-info.java
src/test/java/com/centinela/architecture/ArchitectureConventionsTest.java

scripts/tests/scan-repository.sh
```

### 6. Archivos que pueden modificarse

```text
README.md, únicamente para comandos locales y requisitos de ejecución.
```

### 7. Archivos prohibidos

```text
src/main/java/com/centinela/scoring/**
src/main/java/com/centinela/fraudcase/**
src/main/java/com/centinela/ai/**
```

### 8. Criterios de aceptación

- [ ] `mvn clean verify` termina correctamente con Java 21.
- [ ] La aplicación inicia con el perfil de prueba sin conectarse a Azure.
- [ ] Dominio y aplicación no importan clases de Spring Web ni SDK de Azure.
- [ ] Los cuatro módulos lógicos de Semana 1 están identificables.
- [ ] El repositorio no contiene secretos, claves ni cadenas de conexión.


### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S1-001` | Obligatoria para cerrar | Estático | Arquitectura | Validar compilación y límites hexagonales |
| `TEST-S1-002` | Obligatoria para cerrar | Estático | Seguridad e higiene | Detectar secretos y archivos sensibles versionados |
| `TEST-S1-028` | Posterior de integración | Estático | Control de alcance | Verificar que no se implementó alcance de Semana 2 |

Las pruebas obligatorias deben pasar antes de cerrar esta issue. Las pruebas posteriores se ejecutan cuando estén disponibles sus dependencias y son obligatorias para cerrar la Semana 1, pero no crean dependencias hacia issues posteriores.

### 10. Escenarios Gherkin

```gherkin
Escenario: Proyecto compilable
  Dado un repositorio limpio con Java 21 y Maven
  Cuando se ejecuta `mvn clean verify`
  Entonces la compilación y las pruebas de arquitectura terminan sin errores

Escenario: Dependencia arquitectónica inválida
  Dado una clase del dominio que intenta importar el SDK de Azure
  Cuando se ejecuta la prueba de arquitectura
  Entonces la prueba falla y señala la dependencia prohibida

Escenario: Configuración local segura
  Dado el proyecto recién clonado
  Cuando se inspeccionan archivos versionados y variables
  Entonces no aparecen credenciales ni valores secretos
```

### 11. Definition of Done específica

- [ ] Todos los criterios de aceptación están demostrados.
- [ ] Solo se crearon o modificaron archivos autorizados.
- [ ] Las pruebas obligatorias disponibles para esta etapa pasaron.
- [ ] Las pruebas posteriores quedaron trazadas con su issue bloqueadora.
- [ ] Existe evidencia reproducible y sanitizada.
- [ ] No se agregaron decisiones de Semana 2.
- [ ] No hay secretos ni datos personales reales.
- [ ] La revisión cruzada fue aprobada.

### 12. Comandos de validación

```bash
mvn clean verify
grep -RInE "AccountKey=|DefaultEndpointsProtocol=|client-secret|BEGIN PRIVATE KEY" . --exclude-dir=.git --exclude-dir=target
```

### 13. Evidencia esperada

- Salida de `mvn clean verify`.
- Árbol de paquetes.
- Resultado sanitizado de la prueba de arquitectura y búsqueda de secretos.

### 14. Instrucción para una IA o integrante

Antes de implementar, debe resumir objetivo, dependencias, archivos, criterios, pruebas, riesgos y fuera de alcance. Después debe listar archivos realmente modificados, pruebas realmente ejecutadas, evidencias, pendientes y cualquier desviación. No puede declarar `DONE` basándose solo en código escrito.

## ISS-S1-002 — Crear scripts base de infraestructura y control de costos

### Metadatos

- **Historia:** HU-S1-001
- **Feature:** FEAT-S1-001
- **Responsable principal:** Persona 1
- **Revisor:** Persona 5
- **Dependencias para iniciar:** Ninguna
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S1-004
- **Requisitos:** RI-S1-001; RI-S1-006; RNF-S1-002..004
- **Pruebas catalogadas:** TEST-S1-003, TEST-S1-004, TEST-S1-026, TEST-S1-027

### 1. Objetivo

Crear el armazón seguro y parametrizado para desplegar, validar y destruir una única infraestructura compartida por el equipo.

### 2. Contexto y razón técnica

El crédito de USD 200 es común para cinco personas. Los scripts deben impedir despliegues accidentales, valores rígidos y recursos olvidados, pero los recursos concretos se incorporan en las issues de infraestructura posteriores.

### 3. Descripción técnica

- Crear `deploy-week1.sh` como orquestador y no como script monolítico de negocio.
- Exigir `SUBSCRIPTION_ID`, `LOCATION`, `RESOURCE_GROUP`, `NAME_PREFIX` y `APP_SERVICE_SKU` por parámetros o variables de entorno.
- Validar sesión Azure CLI, suscripción activa, formato de nombres y que el SKU indicado soporte slot y escala horizontal.
- Crear funciones comunes para logging, manejo de errores, reintentos limitados y ocultamiento de valores sensibles.
- Crear `destroy-week1.sh` con confirmación explícita del Resource Group y opción no interactiva solo para automatización controlada.
- Agregar tags de proyecto/semana/equipo y advertencia de costos. No fijar región ni SKU en la documentación o los scripts.

### 4. Fuera de alcance

- Creación completa de todos los recursos en esta issue.
- CI/CD o GitHub Actions.
- Cinco entornos independientes.
- Presupuesto automático si la suscripción gratuita no permite crearlo.

### 5. Archivos que deben crearse

```text
scripts/deploy-week1.sh
scripts/destroy-week1.sh
scripts/validate-week1.sh
scripts/lib/common.sh
scripts/lib/parameters.sh
.env.example

scripts/tests/test-deploy-parameters.sh
scripts/tests/test-destroy-safety.sh
```

### 6. Archivos que pueden modificarse

```text
README.md para documentar parámetros y comandos.
```

### 7. Archivos prohibidos

```text
.env con valores reales
scripts/github/**
.github/workflows/**
```

### 8. Criterios de aceptación

- [ ] Los scripts fallan antes de crear recursos si falta un parámetro obligatorio.
- [ ] Ningún script contiene región, suscripción o SKU rígidos.
- [ ] `destroy-week1.sh` muestra el Resource Group exacto antes de eliminar.
- [ ] Los logs no imprimen tokens, secretos ni cadenas de conexión.
- [ ] El diseño soporta incorporar las issues 003, 004, 005 y 006 sin duplicar lógica.


### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S1-003` | Obligatoria para cerrar | Estático | Scripts de infraestructura | Validar parámetros obligatorios del despliegue |
| `TEST-S1-004` | Obligatoria para cerrar | Integración | Scripts y control de costos | Proteger la destrucción del Resource Group |
| `TEST-S1-026` | Posterior de integración | E2E | Infraestructura reproducible | Desplegar desde una suscripción o Resource Group limpio |
| `TEST-S1-027` | Posterior de integración | E2E | Infraestructura reproducible y costos | Destruir, reconstruir, validar y limpiar |

Las pruebas obligatorias deben pasar antes de cerrar esta issue. Las pruebas posteriores se ejecutan cuando estén disponibles sus dependencias y son obligatorias para cerrar la Semana 1, pero no crean dependencias hacia issues posteriores.

### 10. Escenarios Gherkin

```gherkin
Escenario: Parámetros válidos
  Dado una sesión de Azure CLI activa y todos los parámetros requeridos
  Cuando se ejecuta el modo de validación del script
  Entonces los parámetros se aceptan y el plan de despliegue se muestra sin exponer secretos

Escenario: Falta un parámetro
  Dado no existe `RESOURCE_GROUP`
  Cuando se inicia `deploy-week1.sh`
  Entonces el script termina antes de crear recursos e informa el parámetro faltante

Escenario: Destrucción protegida
  Dado un Resource Group cuyo nombre no coincide con el prefijo esperado
  Cuando se ejecuta `destroy-week1.sh`
  Entonces el script rechaza la eliminación hasta recibir una confirmación explícita válida
```

### 11. Definition of Done específica

- [ ] Todos los criterios de aceptación están demostrados.
- [ ] Solo se crearon o modificaron archivos autorizados.
- [ ] Las pruebas obligatorias disponibles para esta etapa pasaron.
- [ ] Las pruebas posteriores quedaron trazadas con su issue bloqueadora.
- [ ] Existe evidencia reproducible y sanitizada.
- [ ] No se agregaron decisiones de Semana 2.
- [ ] No hay secretos ni datos personales reales.
- [ ] La revisión cruzada fue aprobada.

### 12. Comandos de validación

```bash
bash -n scripts/*.sh scripts/lib/*.sh
shellcheck scripts/*.sh scripts/lib/*.sh
./scripts/deploy-week1.sh --validate-only
```

### 13. Evidencia esperada

- Salida de validación de parámetros.
- Resultado de ShellCheck.
- Captura sanitizada de la protección de destrucción.

### 14. Instrucción para una IA o integrante

Antes de implementar, debe resumir objetivo, dependencias, archivos, criterios, pruebas, riesgos y fuera de alcance. Después debe listar archivos realmente modificados, pruebas realmente ejecutadas, evidencias, pendientes y cualquier desviación. No puede declarar `DONE` basándose solo en código escrito.

## ISS-S1-003 — Crear Storage, contenedores y colas por ambiente

### Metadatos

- **Historia:** HU-S1-001
- **Feature:** FEAT-S1-001
- **Responsable principal:** Persona 1
- **Revisor:** Persona 5
- **Dependencias para iniciar:** ISS-S1-002
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S1-003 y FM-S1-004
- **Requisitos:** RF-S1-004..006; RI-S1-002
- **Pruebas catalogadas:** TEST-S1-005, TEST-S1-026, TEST-S1-027

### 1. Objetivo

Aprovisionar un único Storage Account con recursos lógicos separados para staging y producción, sin habilitar acceso público.

### 2. Contexto y razón técnica

Separar contenedores y colas por ambiente evita mezclar datos sin duplicar toda la infraestructura, lo cual ayuda a respetar el crédito disponible. El uso privado y DNS se completa en ISS-S1-005.

### 3. Descripción técnica

- Crear un Storage Account con nombre derivado de `NAME_PREFIX` y parámetros válidos de Azure.
- Deshabilitar acceso público al servicio y a los blobs.
- Crear `raw-transactions-staging`, `raw-transactions-production`, `verification-documents-staging` y `verification-documents-production`.
- Crear `transactions-ingestion-staging` y `transactions-ingestion-production`.
- Crear contenedores y colas mediante ARM/control plane o un mecanismo equivalente que no obligue a abrir temporalmente el acceso público del data plane.
- Hacer las operaciones idempotentes: si el recurso ya existe y coincide con la configuración, no debe fallar ni duplicarse.
- No colocar mensajes de negocio ni definir el esquema futuro de la cola.

### 4. Fuera de alcance

- Consumidor o productor de negocio de Queue.
- Contrato de evento de scoring.
- Bases de datos.
- Un Storage Account por integrante.

### 5. Archivos que deben crearse

```text
scripts/provision-storage.sh
scripts/tests/validate-storage.sh
```

### 6. Archivos que pueden modificarse

```text
scripts/deploy-week1.sh
scripts/validate-week1.sh
scripts/destroy-week1.sh
```

### 7. Archivos prohibidos

```text
src/main/java/**/queue/consumer/**
docs/week2-event-schema.*
```

### 8. Criterios de aceptación

- [ ] Existe un solo Storage Account para el entorno integrado.
- [ ] Los cuatro contenedores y las dos colas existen con nombres exactos.
- [ ] Los contenedores no permiten acceso anónimo.
- [ ] El acceso público del Storage está deshabilitado.
- [ ] Reejecutar el script no crea recursos duplicados.


### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S1-005` | Obligatoria para cerrar | Integración | Infraestructura y almacenamiento | Validar Storage, contenedores y colas por ambiente |
| `TEST-S1-026` | Posterior de integración | E2E | Infraestructura reproducible | Desplegar desde una suscripción o Resource Group limpio |
| `TEST-S1-027` | Posterior de integración | E2E | Infraestructura reproducible y costos | Destruir, reconstruir, validar y limpiar |

Las pruebas obligatorias deben pasar antes de cerrar esta issue. Las pruebas posteriores se ejecutan cuando estén disponibles sus dependencias y son obligatorias para cerrar la Semana 1, pero no crean dependencias hacia issues posteriores.

### 10. Escenarios Gherkin

```gherkin
Escenario: Recursos lógicos creados
  Dado un Storage Account nuevo
  Cuando se ejecuta `provision-storage.sh`
  Entonces se crean cuatro contenedores y dos colas con separación staging/production

Escenario: Reejecución segura
  Dado los recursos ya existen con la configuración aprobada
  Cuando se reejecuta el script
  Entonces la ejecución termina correctamente sin duplicar recursos

Escenario: Acceso público prohibido
  Dado los recursos están creados
  Cuando se intenta listar un contenedor de forma anónima
  Entonces la solicitud es rechazada
```

### 11. Definition of Done específica

- [ ] Todos los criterios de aceptación están demostrados.
- [ ] Solo se crearon o modificaron archivos autorizados.
- [ ] Las pruebas obligatorias disponibles para esta etapa pasaron.
- [ ] Las pruebas posteriores quedaron trazadas con su issue bloqueadora.
- [ ] Existe evidencia reproducible y sanitizada.
- [ ] No se agregaron decisiones de Semana 2.
- [ ] No hay secretos ni datos personales reales.
- [ ] La revisión cruzada fue aprobada.

### 12. Comandos de validación

```bash
./scripts/provision-storage.sh
./scripts/tests/validate-storage.sh
```

### 13. Evidencia esperada

- Listado de contenedores y colas.
- Propiedades de acceso público sanitizadas.
- Resultado de reejecución idempotente.

### 14. Instrucción para una IA o integrante

Antes de implementar, debe resumir objetivo, dependencias, archivos, criterios, pruebas, riesgos y fuera de alcance. Después debe listar archivos realmente modificados, pruebas realmente ejecutadas, evidencias, pendientes y cualquier desviación. No puede declarar `DONE` basándose solo en código escrito.

## ISS-S1-004 — Crear App Service, Managed Identity y slot staging

### Metadatos

- **Historia:** HU-S1-001
- **Feature:** FEAT-S1-001
- **Responsable principal:** Persona 1
- **Revisor:** Persona 5
- **Dependencias para iniciar:** ISS-S1-002
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S1-004
- **Requisitos:** RF-S1-007; RI-S1-004; RNF-S1-002..004
- **Pruebas catalogadas:** TEST-S1-006, TEST-S1-023, TEST-S1-026, TEST-S1-027

### 1. Objetivo

Aprovisionar un App Service compartido con producción y slot staging, Managed Identity y configuración aislada por ambiente.

### 2. Contexto y razón técnica

El SKU y la región se reciben por parámetros. El plan elegido debe soportar deployment slots y escala horizontal, pero la documentación no impone un valor comercial concreto.

### 3. Descripción técnica

- Crear un App Service Plan, Web App y slot `staging` usando parámetros.
- Activar System Assigned Managed Identity en producción y staging.
- Configurar variables no secretas para indicar ambiente y nombres de contenedores/colas.
- Marcar como slot settings las variables que no deben intercambiarse entre producción y staging.
- Mantener una instancia en operación normal; la segunda instancia solo se habilita durante ISS-S1-012.
- Preparar el despliegue de un único artefacto de aplicación, sin exigir pipeline CI/CD.

### 4. Fuera de alcance

- GitHub Actions.
- Blue/green avanzado, Front Door o múltiples regiones.
- Cinco App Service Plans.
- Fijar un SKU o región en la documentación.

### 5. Archivos que deben crearse

```text
scripts/provision-app-service.sh
scripts/deploy-application.sh
scripts/tests/validate-app-service.sh
```

### 6. Archivos que pueden modificarse

```text
scripts/deploy-week1.sh
scripts/validate-week1.sh
scripts/destroy-week1.sh
```

### 7. Archivos prohibidos

```text
.github/workflows/**
scripts/provision-runner.sh
```

### 8. Criterios de aceptación

- [ ] Web App y slot staging existen en el mismo plan.
- [ ] Ambos tienen Managed Identity activa.
- [ ] Producción usa recursos lógicos `*-production` y staging usa `*-staging`.
- [ ] El SKU y región provienen de parámetros.
- [ ] El plan queda en una instancia después del despliegue normal.


### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S1-006` | Obligatoria para cerrar | Integración | Infraestructura y configuración | Validar App Service, Managed Identity y slot staging |
| `TEST-S1-023` | Posterior de integración | E2E | Configuración por ambiente | Confirmar aislamiento funcional entre staging y producción |
| `TEST-S1-026` | Posterior de integración | E2E | Infraestructura reproducible | Desplegar desde una suscripción o Resource Group limpio |
| `TEST-S1-027` | Posterior de integración | E2E | Infraestructura reproducible y costos | Destruir, reconstruir, validar y limpiar |

Las pruebas obligatorias deben pasar antes de cerrar esta issue. Las pruebas posteriores se ejecutan cuando estén disponibles sus dependencias y son obligatorias para cerrar la Semana 1, pero no crean dependencias hacia issues posteriores.

### 10. Escenarios Gherkin

```gherkin
Escenario: Producción y staging separados
  Dado parámetros válidos y un Resource Group
  Cuando se ejecuta `provision-app-service.sh`
  Entonces se crean Web App y slot con settings de ambiente diferentes

Escenario: SKU no compatible
  Dado un SKU que no soporta slot o escala horizontal
  Cuando se valida antes del despliegue
  Entonces el script termina sin crear el App Service y explica la incompatibilidad

Escenario: Configuración cruzada
  Dado staging apunta a un contenedor de producción
  Cuando se ejecuta la validación
  Entonces la prueba falla e identifica el setting incorrecto
```

### 11. Definition of Done específica

- [ ] Todos los criterios de aceptación están demostrados.
- [ ] Solo se crearon o modificaron archivos autorizados.
- [ ] Las pruebas obligatorias disponibles para esta etapa pasaron.
- [ ] Las pruebas posteriores quedaron trazadas con su issue bloqueadora.
- [ ] Existe evidencia reproducible y sanitizada.
- [ ] No se agregaron decisiones de Semana 2.
- [ ] No hay secretos ni datos personales reales.
- [ ] La revisión cruzada fue aprobada.

### 12. Comandos de validación

```bash
./scripts/provision-app-service.sh
./scripts/tests/validate-app-service.sh
```

### 13. Evidencia esperada

- Listado de Web App y slot.
- Managed Identities sanitizadas.
- Comparación de settings sin secretos.

### 14. Instrucción para una IA o integrante

Antes de implementar, debe resumir objetivo, dependencias, archivos, criterios, pruebas, riesgos y fuera de alcance. Después debe listar archivos realmente modificados, pruebas realmente ejecutadas, evidencias, pendientes y cualquier desviación. No puede declarar `DONE` basándose solo en código escrito.

## ISS-S1-005 — Crear VNet, subredes, DNS y Private Endpoints

### Metadatos

- **Historia:** HU-S1-001
- **Feature:** FEAT-S1-001
- **Responsable principal:** Persona 2
- **Revisor:** Persona 1
- **Dependencias para iniciar:** ISS-S1-002, ISS-S1-003 e ISS-S1-004
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S1-004
- **Requisitos:** RI-S1-002; RI-S1-003
- **Pruebas catalogadas:** TEST-S1-007, TEST-S1-026, TEST-S1-027

### 1. Objetivo

Conectar la aplicación con Blob y Queue mediante red privada y mantener deshabilitado el acceso público del Storage Account.

### 2. Contexto y razón técnica

Azure-Semana1 exige segmentación de red y Storage no expuesto a Internet. La issue depende del Storage y App Service ya creados para evitar una dependencia circular.

### 3. Descripción técnica

- Crear una VNet compartida con `snet-app-integration` y `snet-private-endpoints`.
- Delegar la subred de integración al servicio requerido por App Service y deshabilitar políticas de red de Private Endpoint donde corresponda.
- Integrar producción y el slot `staging` con `snet-app-integration`.
- Crear Private Endpoints para los subrecursos Blob y Queue del Storage Account.
- Crear y vincular las zonas DNS privadas necesarias para que los nombres de Storage resuelvan a IP privada desde la VNet.
- Validar que el acceso anónimo/público permanece bloqueado y que la aplicación puede resolver los endpoints privados.

### 4. Fuera de alcance

- Application Gateway, Front Door, API Management o firewall adicional.
- VPN, ExpressRoute o máquinas virtuales.
- Subred para runners de CI.

### 5. Archivos que deben crearse

```text
scripts/provision-network.sh
scripts/configure-private-endpoints.sh
scripts/tests/validate-network.sh
```

### 6. Archivos que pueden modificarse

```text
scripts/deploy-week1.sh
scripts/validate-week1.sh
scripts/destroy-week1.sh
```

### 7. Archivos prohibidos

```text
scripts/provision-vm.sh
scripts/provision-apim.sh
.github/workflows/**
```

### 8. Criterios de aceptación

- [ ] Existen exactamente las dos subredes mínimas documentadas.
- [ ] Producción y staging tienen VNet Integration.
- [ ] Blob y Queue poseen Private Endpoint y zona DNS vinculada.
- [ ] `publicNetworkAccess` del Storage queda deshabilitado.
- [ ] La resolución desde el contexto de la aplicación devuelve direcciones privadas.


### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S1-007` | Obligatoria para cerrar | Integración | Red y seguridad | Validar red privada y resolución DNS |
| `TEST-S1-026` | Posterior de integración | E2E | Infraestructura reproducible | Desplegar desde una suscripción o Resource Group limpio |
| `TEST-S1-027` | Posterior de integración | E2E | Infraestructura reproducible y costos | Destruir, reconstruir, validar y limpiar |

Las pruebas obligatorias deben pasar antes de cerrar esta issue. Las pruebas posteriores se ejecutan cuando estén disponibles sus dependencias y son obligatorias para cerrar la Semana 1, pero no crean dependencias hacia issues posteriores.

### 10. Escenarios Gherkin

```gherkin
Escenario: Acceso privado operativo
  Dado Storage, App Service y las dos subredes creadas
  Cuando se configuran VNet Integration, Private Endpoints y DNS
  Entonces la aplicación resuelve Blob y Queue por red privada

Escenario: Acceso público bloqueado
  Dado el Storage desplegado
  Cuando se intenta acceder desde un cliente sin conectividad privada
  Entonces la operación falla y no expone contenedores ni colas

Escenario: DNS privado incompleto
  Dado el vínculo de la zona DNS se elimina en un entorno de prueba
  Cuando la aplicación intenta resolver Storage
  Entonces la validación falla y señala el vínculo DNS faltante
```

### 11. Definition of Done específica

- [ ] Todos los criterios de aceptación están demostrados.
- [ ] Solo se crearon o modificaron archivos autorizados.
- [ ] Las pruebas obligatorias disponibles para esta etapa pasaron.
- [ ] Las pruebas posteriores quedaron trazadas con su issue bloqueadora.
- [ ] Existe evidencia reproducible y sanitizada.
- [ ] No se agregaron decisiones de Semana 2.
- [ ] No hay secretos ni datos personales reales.
- [ ] La revisión cruzada fue aprobada.

### 12. Comandos de validación

```bash
./scripts/provision-network.sh
./scripts/configure-private-endpoints.sh
./scripts/tests/validate-network.sh
```

### 13. Evidencia esperada

- Diagrama o salida de VNet y subredes.
- Listado de Private Endpoints y zonas DNS.
- Prueba de acceso público fallido y resolución privada exitosa.

### 14. Instrucción para una IA o integrante

Antes de implementar, debe resumir objetivo, dependencias, archivos, criterios, pruebas, riesgos y fuera de alcance. Después debe listar archivos realmente modificados, pruebas realmente ejecutadas, evidencias, pendientes y cualquier desviación. No puede declarar `DONE` basándose solo en código escrito.

## ISS-S1-006 — Configurar Entra ID, roles y RBAC mínimo

### Metadatos

- **Historia:** HU-S1-002
- **Feature:** FEAT-S1-002
- **Responsable principal:** Persona 2
- **Revisor:** Persona 1
- **Dependencias para iniciar:** ISS-S1-002, ISS-S1-003 e ISS-S1-004
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S1-001 y FM-S1-002
- **Requisitos:** RS-S1-001..004
- **Pruebas catalogadas:** TEST-S1-008, TEST-S1-009, TEST-S1-010, TEST-S1-021, TEST-S1-022

### 1. Objetivo

Crear las identidades y permisos mínimos para Servicio, Analista, Administrador y Auditor, además del acceso de la Managed Identity a Blob Storage.

### 2. Contexto y razón técnica

La autenticación HTTP y la autorización de endpoints se implementan en ISS-S1-011. Esta issue se limita a Entra ID y Azure RBAC, evitando conceder permisos administrativos amplios a usuarios funcionales.

### 3. Descripción técnica

- Crear o configurar la aplicación de Entra ID que representa la API.
- Definir los app roles `SERVICE`, `ANALYST`, `ADMINISTRATOR` y `AUDITOR` sin convertirlos automáticamente en roles de infraestructura.
- Asignar a la Managed Identity de producción y staging el permiso mínimo de datos requerido para los contenedores Blob usados por la API.
- No asignar permiso de Queue a la aplicación, porque la cola no forma parte del flujo de negocio de Semana 1.
- Asignar `Reader` a las identidades de demostración Analista/Auditor cuando sea necesario para verificar lectura sin modificación.
- Crear una identidad o asignación temporal mínima para la prueba de Queue y documentar su revocación posterior.

### 4. Fuera de alcance

- Spring Security y conversión de claims.
- Administración completa de usuarios.
- Permisos de Contributor/Owner para Analista o Auditor.
- Secretos de cliente versionados.

### 5. Archivos que deben crearse

```text
scripts/provision-entra-app.sh
scripts/assign-rbac.sh
scripts/tests/validate-rbac.sh
docs/evidence/identity/.gitkeep

scripts/tests/validate-entra-roles.sh
scripts/tests/test-analyst-rbac.sh
scripts/tests/validate-managed-identity.sh
```

### 6. Archivos que pueden modificarse

```text
scripts/deploy-week1.sh
scripts/destroy-week1.sh
3_Seguridad/1_Seguridad_Backend.md si cambia un identificador técnico aprobado.
```

### 7. Archivos prohibidos

```text
src/main/resources/*secret*
.env real
scripts/grant-owner.sh
```

### 8. Criterios de aceptación

- [ ] Los cuatro roles de aplicación existen.
- [ ] Analista y Auditor no pueden modificar ni eliminar recursos Azure.
- [ ] La Managed Identity puede escribir en los contenedores necesarios sin usar claves.
- [ ] La aplicación no recibe permisos de Queue Storage.
- [ ] Las asignaciones temporales de la prueba de cola quedan identificadas para revocación.


### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S1-008` | Obligatoria para cerrar | Integración | Identidad y seguridad | Validar existencia de los cuatro app roles |
| `TEST-S1-009` | Obligatoria para cerrar | E2E | Seguridad y RBAC | Impedir modificaciones Azure al Analista |
| `TEST-S1-010` | Obligatoria para cerrar | Integración | Seguridad y RBAC | Validar mínimo privilegio de Managed Identity |
| `TEST-S1-021` | Posterior de integración | Integración | Seguridad HTTP | Autorizar únicamente Servicio en transacciones |
| `TEST-S1-022` | Posterior de integración | Integración | Seguridad HTTP | Autorizar únicamente Analista en carga documental |

Las pruebas obligatorias deben pasar antes de cerrar esta issue. Las pruebas posteriores se ejecutan cuando estén disponibles sus dependencias y son obligatorias para cerrar la Semana 1, pero no crean dependencias hacia issues posteriores.

### 10. Escenarios Gherkin

```gherkin
Escenario: Managed Identity con mínimo privilegio
  Dado la Web App y los contenedores creados
  Cuando se asigna el rol de datos Blob requerido
  Entonces la aplicación puede almacenar blobs sin cadena de conexión

Escenario: Analista sin modificación
  Dado una identidad con rol funcional Analista y Azure Reader
  Cuando intenta cambiar tags o eliminar un recurso
  Entonces Azure deniega la operación

Escenario: Permiso excesivo detectado
  Dado una asignación Contributor aparece para Analista o Auditor
  Cuando se ejecuta la validación RBAC
  Entonces la validación falla y reporta la asignación prohibida
```

### 11. Definition of Done específica

- [ ] Todos los criterios de aceptación están demostrados.
- [ ] Solo se crearon o modificaron archivos autorizados.
- [ ] Las pruebas obligatorias disponibles para esta etapa pasaron.
- [ ] Las pruebas posteriores quedaron trazadas con su issue bloqueadora.
- [ ] Existe evidencia reproducible y sanitizada.
- [ ] No se agregaron decisiones de Semana 2.
- [ ] No hay secretos ni datos personales reales.
- [ ] La revisión cruzada fue aprobada.

### 12. Comandos de validación

```bash
./scripts/provision-entra-app.sh
./scripts/assign-rbac.sh
./scripts/tests/validate-rbac.sh
```

### 13. Evidencia esperada

- Listado sanitizado de app roles.
- Asignaciones RBAC por principal y alcance.
- Intento de modificación denegado para Analista.

### 14. Instrucción para una IA o integrante

Antes de implementar, debe resumir objetivo, dependencias, archivos, criterios, pruebas, riesgos y fuera de alcance. Después debe listar archivos realmente modificados, pruebas realmente ejecutadas, evidencias, pendientes y cualquier desviación. No puede declarar `DONE` basándose solo en código escrito.

## ISS-S1-007 — Documentar e implementar contrato de transacción

### Metadatos

- **Historia:** HU-S1-003
- **Feature:** FEAT-S1-003
- **Responsable principal:** Persona 2
- **Revisor:** Persona 3
- **Dependencias para iniciar:** ISS-S1-001
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S1-001
- **Requisitos:** RF-S1-001..003; RNF-S1-001
- **Pruebas catalogadas:** TEST-S1-011, TEST-S1-012, TEST-S1-013, TEST-S1-017, TEST-S1-028

### 1. Objetivo

Implementar el contrato HTTP, DTOs, validaciones y límite de entrada para recibir una transacción sin ejecutar lógica de fraude.

### 2. Contexto y razón técnica

El contrato de Semana 1 debe ser estable para los sistemas originadores y, al mismo tiempo, no debe contener campos de score, reglas o casos que todavía no existen. La persistencia real se conecta en ISS-S1-008.

### 3. Descripción técnica

- Alinear `openapi-centinela-semana1.yaml` con los DTOs request/response.
- Crear `TransactionRequest`, `LocationRequest`, `MerchantRequest` y `TransactionReceiptResponse` con validaciones Bean Validation equivalentes al modelo documentado.
- Crear un mapper web que convierta DTO a un comando de aplicación sin exponer clases de infraestructura.
- Crear `IngestTransactionUseCase` como puerto de entrada y un controller que dependa de ese puerto.
- Crear manejo global para `400` con respuesta segura y sin stack trace.
- No incorporar score, decisión, reglas activadas, `caseId`, publicación en Queue ni consulta histórica.

### 4. Fuera de alcance

- Persistencia Blob.
- Configuración JWT.
- Idempotencia avanzada no solicitada.
- Endpoints GET de score/caso.

### 5. Archivos que deben crearse

```text
src/main/java/com/centinela/transactioningestion/domain/model/Transaction.java
src/main/java/com/centinela/transactioningestion/domain/model/Location.java
src/main/java/com/centinela/transactioningestion/domain/model/Merchant.java
src/main/java/com/centinela/transactioningestion/application/port/in/IngestTransactionUseCase.java
src/main/java/com/centinela/transactioningestion/application/command/IngestTransactionCommand.java
src/main/java/com/centinela/transactioningestion/infrastructure/web/TransactionController.java
src/main/java/com/centinela/transactioningestion/infrastructure/web/dto/TransactionRequest.java
src/main/java/com/centinela/transactioningestion/infrastructure/web/dto/LocationRequest.java
src/main/java/com/centinela/transactioningestion/infrastructure/web/dto/MerchantRequest.java
src/main/java/com/centinela/transactioningestion/infrastructure/web/dto/TransactionReceiptResponse.java
src/main/java/com/centinela/transactioningestion/infrastructure/web/mapper/TransactionWebMapper.java
src/main/java/com/centinela/shared/web/ApiExceptionHandler.java
src/main/java/com/centinela/shared/web/ErrorResponse.java
src/test/java/com/centinela/transactioningestion/infrastructure/web/TransactionControllerValidationTest.java

src/test/java/com/centinela/transactioningestion/contract/OpenApiContractTest.java
src/test/java/com/centinela/transactioningestion/infrastructure/web/dto/TransactionRequestValidationTest.java
src/test/java/com/centinela/transactioningestion/infrastructure/web/TransactionWebMapperTest.java
docs/evidence/iss-s1-007/README.md
docs/evidence/iss-s1-007/capture-evidence.sh
docs/evidence/iss-s1-007/examples/valid-request.json
docs/evidence/iss-s1-007/examples/202-response.json
docs/evidence/iss-s1-007/examples/400-response.json
```

### 6. Archivos que pueden modificarse

```text
openapi-centinela-semana1.yaml
1_Requisitos_y_Contrato/3_API_OpenAPI.md
pom.xml solo si falta una dependencia ya aprobada.
5_Issues_y_Trazabilidad/1_Historias_Issues.md solo para registrar los DTO separados y la evidencia autorizada.
```

### 7. Archivos prohibidos

```text
src/main/java/com/centinela/scoring/**
src/main/java/com/centinela/fraudcase/**
src/main/java/**/QueuePublisher*
```

### 8. Criterios de aceptación

- [ ] `POST /api/v1/transactions` acepta únicamente `application/json`.
- [ ] Todos los campos obligatorios y rangos definidos se validan.
- [ ] Una entrada inválida devuelve `400` y no invoca el puerto de persistencia.
- [ ] La respuesta de éxito solo contiene `transactionId` y `status=RECEIVED`.
- [ ] OpenAPI y clases Java no contienen campos de Semana 2.


### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S1-011` | Obligatoria para cerrar | Contrato | API y contrato | Validar contrato OpenAPI de la transacción |
| `TEST-S1-012` | Obligatoria para cerrar | Unitario | Validación | Validar campos y límites de TransactionRequest |
| `TEST-S1-013` | Obligatoria para cerrar | Unitario | Mapeo y alcance | Mapear únicamente los datos crudos aprobados |
| `TEST-S1-017` | Posterior de integración | Integración | API y validación | Rechazar payload inválido sin persistir |
| `TEST-S1-028` | Posterior de integración | Estático | Control de alcance | Verificar que no se implementó alcance de Semana 2 |

Las pruebas obligatorias deben pasar antes de cerrar esta issue. Las pruebas posteriores se ejecutan cuando estén disponibles sus dependencias y son obligatorias para cerrar la Semana 1, pero no crean dependencias hacia issues posteriores.

### 10. Escenarios Gherkin

```gherkin
Escenario: Contrato válido en aislamiento
  Dado un payload que cumple el esquema y un puerto de entrada simulado
  Cuando el controller recibe la solicitud
  Entonces invoca el caso de uso con el comando correcto y devuelve el recibo esperado

Escenario: Campo obligatorio ausente
  Dado un payload sin `accountId`
  Cuando se envía al endpoint
  Entonces se devuelve `400` y el caso de uso no es invocado

Escenario: Campo futuro no permitido
  Dado un payload que incluye `score` o `caseId`
  Cuando se valida contra OpenAPI y DTO
  Entonces la solicitud se rechaza o el contrato detecta la propiedad no permitida
```

### 11. Definition of Done específica

- [ ] Todos los criterios de aceptación están demostrados.
- [ ] Solo se crearon o modificaron archivos autorizados.
- [ ] Las pruebas obligatorias disponibles para esta etapa pasaron.
- [ ] Las pruebas posteriores quedaron trazadas con su issue bloqueadora.
- [ ] Existe evidencia reproducible y sanitizada.
- [ ] No se agregaron decisiones de Semana 2.
- [ ] No hay secretos ni datos personales reales.
- [ ] La revisión cruzada fue aprobada.

### 12. Comandos de validación

```bash
mvn -Dtest=TransactionControllerValidationTest,OpenApiContractTest,TransactionRequestValidationTest,TransactionWebMapperTest test
npx @redocly/cli lint docs/1_Requisitos_y_Contrato/openapi-centinela-semana1.yaml
```

### 13. Evidencia esperada

- Reporte de pruebas del controller.
- Diff o validación del OpenAPI.
- Ejemplos sanitizados de `400` y del recibo de contrato (`transactionId` + `status=RECEIVED`) devuelto por el controller con el puerto de salida simulado. El `202` real ligado a la persistencia en Blob se valida en `ISS-S1-008`, no en esta issue.

### 14. Instrucción para una IA o integrante

Antes de implementar, debe resumir objetivo, dependencias, archivos, criterios, pruebas, riesgos y fuera de alcance. Después debe listar archivos realmente modificados, pruebas realmente ejecutadas, evidencias, pendientes y cualquier desviación. No puede declarar `DONE` basándose solo en código escrito.

## ISS-S1-008 — Persistir transacción cruda en Blob

### Metadatos

- **Historia:** HU-S1-003
- **Feature:** FEAT-S1-003
- **Responsable principal:** Persona 2
- **Revisor:** Persona 3
- **Dependencias para iniciar:** ISS-S1-003, ISS-S1-004, ISS-S1-005, ISS-S1-006 e ISS-S1-007
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S1-001
- **Requisitos:** RF-S1-003..004; RS-S1-003..004; RNF-S1-001
- **Pruebas catalogadas:** TEST-S1-014, TEST-S1-015, TEST-S1-017, TEST-S1-016, TEST-S1-023, TEST-S1-024

### 1. Objetivo

Implementar el caso de uso y adaptador Blob para que una transacción válida quede almacenada antes de devolver `202 Accepted`.

### 2. Contexto y razón técnica

Semana 1 conserva la transacción sin ejecutar análisis. El adaptador debe usar Managed Identity y el contenedor del ambiente. No se publican mensajes en Queue ni se define comportamiento de scoring.

### 3. Descripción técnica

- Crear `IngestTransactionService` como implementación del puerto de entrada.
- Crear `RawTransactionStoragePort` como puerto de salida independiente del SDK Azure.
- Construir la ruta `yyyy/MM/dd/{transactionId}.json` con la fecha de recepción UTC y seleccionar el contenedor del ambiente.
- Crear un adaptador Azure Blob autenticado mediante `DefaultAzureCredential`/Managed Identity, sin connection string.
- Almacenar un JSON semánticamente equivalente al recibido, sin agregar score, decisión, reglas ni caso.
- Devolver `202` únicamente después de confirmar la escritura. Mapear indisponibilidad de Storage a `503` seguro y sin detalles internos.

### 4. Fuera de alcance

- Publicación en Queue.
- Consumidor, reintentos de negocio o contrato de evento.
- Consulta de estado.
- Persistencia histórica en base de datos.

### 5. Archivos que deben crearse

```text
src/main/java/com/centinela/transactioningestion/application/exception/StorageUnavailableException.java
src/main/java/com/centinela/transactioningestion/application/port/out/RawTransactionStoragePort.java
src/main/java/com/centinela/transactioningestion/application/service/IngestTransactionService.java
src/main/java/com/centinela/transactioningestion/infrastructure/azure/blob/AzureRawTransactionBlobAdapter.java
src/main/java/com/centinela/transactioningestion/infrastructure/azure/blob/RawTransactionBlobProperties.java
src/main/java/com/centinela/transactioningestion/infrastructure/azure/blob/BlobPathFactory.java
src/main/java/com/centinela/transactioningestion/infrastructure/config/TransactionIngestionConfiguration.java
src/test/java/com/centinela/transactioningestion/application/service/IngestTransactionServiceTest.java
src/test/java/com/centinela/transactioningestion/infrastructure/azure/blob/AzureRawTransactionBlobAdapterIT.java
src/test/java/com/centinela/transactioningestion/infrastructure/web/TransactionApiIT.java
src/test/java/com/centinela/transactioningestion/infrastructure/web/TransactionApiValidationIT.java
scripts/tests/test-transaction-e2e.sh
scripts/tests/test-environment-isolation.sh
docs/evidence/iss-s1-008/**
```

### 6. Archivos que pueden modificarse

```text
pom.xml únicamente para agregar `azure-identity` bajo el BOM existente.
TransactionController.java
ApiExceptionHandler.java
application*.yml únicamente con nombres no secretos de configuración.
docs/5_Issues_y_Trazabilidad/1_Historias_Issues.md únicamente para autorizar estas correcciones de alcance.
```

### 7. Archivos prohibidos

```text
src/main/java/**/queue/**
src/main/java/com/centinela/scoring/**
connection strings en cualquier archivo.
```

### 8. Criterios de aceptación

- [ ] Una transacción válida devuelve `202` después de una escritura Blob exitosa.
- [ ] El Blob se crea en el contenedor y ruta del ambiente correctos.
- [ ] El contenido no incluye campos futuros ni datos enriquecidos.
- [ ] Sin token devuelve `401`; rol no autorizado devuelve `403` al completar ISS-S1-011.
- [ ] Si Blob no está disponible, se devuelve `503` y no se informa éxito.


### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S1-014` | Obligatoria para cerrar | Unitario | Caso de uso y errores | Persistir antes de emitir el acuse |
| `TEST-S1-015` | Obligatoria para cerrar | Integración | Persistencia Blob | Integrar adaptador Blob de transacciones |
| `TEST-S1-017` | Obligatoria para cerrar | Integración | API y validación | Rechazar payload inválido sin persistir |
| `TEST-S1-016` | Posterior de integración | E2E | API de ingesta | Recibir y almacenar una transacción válida desplegada |
| `TEST-S1-023` | Posterior de integración | E2E | Configuración por ambiente | Confirmar aislamiento funcional entre staging y producción |
| `TEST-S1-024` | Posterior de integración | E2E | Disponibilidad y resiliencia | Mantener disponibilidad al retirar una instancia |

Las pruebas obligatorias deben pasar antes de cerrar esta issue. Las pruebas posteriores se ejecutan cuando estén disponibles sus dependencias y son obligatorias para cerrar la Semana 1, pero no crean dependencias hacia issues posteriores.

### 10. Escenarios Gherkin

```gherkin
Escenario: Persistencia exitosa
  Dado un token Servicio, una transacción válida y Blob disponible
  Cuando se envía `POST /api/v1/transactions`
  Entonces la API almacena el JSON y devuelve `202` con estado `RECEIVED`

Escenario: Storage no disponible
  Dado una transacción válida y el adaptador Blob indisponible
  Cuando se procesa la solicitud
  Entonces la API devuelve `503` y no afirma que la transacción fue recibida

Escenario: Aislamiento por ambiente
  Dado la aplicación ejecutándose en staging
  Cuando se almacena una transacción
  Entonces el Blob queda en `raw-transactions-staging` y no en producción
```

### 11. Definition of Done específica

- [ ] Todos los criterios de aceptación están demostrados.
- [ ] Solo se crearon o modificaron archivos autorizados.
- [ ] Las pruebas obligatorias disponibles para esta etapa pasaron.
- [ ] Las pruebas posteriores quedaron trazadas con su issue bloqueadora.
- [ ] Existe evidencia reproducible y sanitizada.
- [ ] No se agregaron decisiones de Semana 2.
- [ ] No hay secretos ni datos personales reales.
- [ ] La revisión cruzada fue aprobada.

### 12. Comandos de validación

```bash
mvn -Dtest=IngestTransactionServiceTest test
mvn -Dtest=TransactionApiIT,TransactionApiValidationIT test
CENTINELA_RUN_AZURE_IT=true mvn -Dtest=AzureRawTransactionBlobAdapterIT verify
mvn test
```

### 13. Evidencia esperada

- Respuesta HTTP y ubicación del Blob.
- Contenido sanitizado del Blob.
- Reporte de pruebas unitarias e integración.
- Ejecución Azure sin pruebas omitidas y limpieza del Blob sintético.

### 14. Instrucción para una IA o integrante

Antes de implementar, debe resumir objetivo, dependencias, archivos, criterios, pruebas, riesgos y fuera de alcance. Después debe listar archivos realmente modificados, pruebas realmente ejecutadas, evidencias, pendientes y cualquier desviación. No puede declarar `DONE` basándose solo en código escrito.

## ISS-S1-009 — Implementar carga técnica de documentos

### Metadatos

- **Historia:** HU-S1-004
- **Feature:** FEAT-S1-004
- **Responsable principal:** Persona 2
- **Revisor:** Persona 3
- **Dependencias para iniciar:** ISS-S1-001, ISS-S1-003, ISS-S1-004, ISS-S1-005, ISS-S1-006 e ISS-S1-007
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S1-002
- **Requisitos:** RF-S1-005; RS-S1-003..004
- **Pruebas catalogadas:** TEST-S1-018, TEST-S1-019, TEST-S1-022, TEST-S1-023

### 1. Objetivo

Implementar la carga y almacenamiento de un documento técnico sin asociarlo todavía a un caso de fraude.

### 2. Contexto y razón técnica

La Semana 1 solo demuestra almacenamiento documental. No existe `caseId`, flujo de revisión, antivirus, clasificación de evidencias ni decisiones de Semana 2.

### 3. Descripción técnica

- Crear un puerto de entrada `StoreVerificationDocumentUseCase` y un caso de uso.
- Crear un puerto de salida `VerificationDocumentStoragePort` y adaptador Blob con Managed Identity.
- Crear un endpoint `POST /api/v1/verification-documents` con `multipart/form-data` y campo obligatorio `file`.
- Validar que el archivo exista, no esté vacío y que el nombre original se normalice para impedir traversal de rutas.
- Generar `documentId` y almacenar en `yyyy/MM/dd/{documentId}/{originalFilename}` dentro del contenedor del ambiente.
- Devolver `201` con `documentId` y `status=STORED`; mapear indisponibilidad de Blob a `503`.

### 4. Fuera de alcance

- Asociar documentos a casos.
- Definir estados de investigación.
- OCR, antivirus, IA o clasificación documental.
- Reglas de tipos/tamaños no exigidas por los dos MD, salvo protección técnica configurable.

### 5. Archivos que deben crearse

```text
src/main/java/com/centinela/documentstorage/application/port/in/StoreVerificationDocumentUseCase.java
src/main/java/com/centinela/documentstorage/application/port/out/VerificationDocumentStoragePort.java
src/main/java/com/centinela/documentstorage/application/service/StoreVerificationDocumentService.java
src/main/java/com/centinela/documentstorage/domain/model/VerificationDocument.java
src/main/java/com/centinela/documentstorage/infrastructure/web/VerificationDocumentController.java
src/main/java/com/centinela/documentstorage/infrastructure/web/dto/DocumentReceiptResponse.java
src/main/java/com/centinela/documentstorage/infrastructure/azure/blob/AzureVerificationDocumentBlobAdapter.java
src/test/java/com/centinela/documentstorage/application/StoreVerificationDocumentServiceTest.java
src/test/java/com/centinela/documentstorage/infrastructure/web/VerificationDocumentApiIT.java

scripts/tests/test-document-upload-e2e.sh
```

### 6. Archivos que pueden modificarse

```text
openapi-centinela-semana1.yaml
1_Requisitos_y_Contrato/3_API_OpenAPI.md
ApiExceptionHandler.java
application*.yml con nombres no secretos.
```

### 7. Archivos prohibidos

```text
campo `caseId` en request/response o modelo
src/main/java/com/centinela/fraudcase/**
servicios OCR/IA.
```

### 8. Criterios de aceptación

- [ ] Archivo no vacío de Analista produce `201`.
- [ ] El archivo queda en el contenedor documental del ambiente y ruta documentada.
- [ ] El nombre físico no permite `../`, rutas absolutas ni separadores inyectados.
- [ ] Servicio, Administrador y Auditor reciben `403` al completar ISS-S1-011.
- [ ] No se crea ni se requiere `caseId`.


### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S1-018` | Obligatoria para cerrar | Unitario | Documentos y seguridad | Validar documento y normalizar nombre |
| `TEST-S1-019` | Posterior de integración | E2E | Documentos y almacenamiento | Cargar documento desde la API y comprobar Blob |
| `TEST-S1-022` | Posterior de integración | Integración | Seguridad HTTP | Autorizar únicamente Analista en carga documental |
| `TEST-S1-023` | Posterior de integración | E2E | Configuración por ambiente | Confirmar aislamiento funcional entre staging y producción |

Las pruebas obligatorias deben pasar antes de cerrar esta issue. Las pruebas posteriores se ejecutan cuando estén disponibles sus dependencias y son obligatorias para cerrar la Semana 1, pero no crean dependencias hacia issues posteriores.

### 10. Escenarios Gherkin

```gherkin
Escenario: Carga válida
  Dado un Analista autenticado y un archivo no vacío
  Cuando envía el multipart al endpoint
  Entonces el archivo se almacena y la API devuelve `201`

Escenario: Archivo ausente
  Dado una solicitud multipart sin campo `file`
  Cuando se procesa la solicitud
  Entonces la API devuelve `400` y no crea Blob

Escenario: Nombre peligroso
  Dado un archivo cuyo nombre contiene `../`
  Cuando se normaliza antes de crear la ruta
  Entonces no se escribe fuera del prefijo asignado al `documentId`
```

### 11. Definition of Done específica

- [ ] Todos los criterios de aceptación están demostrados.
- [ ] Solo se crearon o modificaron archivos autorizados.
- [ ] Las pruebas obligatorias disponibles para esta etapa pasaron.
- [ ] Las pruebas posteriores quedaron trazadas con su issue bloqueadora.
- [ ] Existe evidencia reproducible y sanitizada.
- [ ] No se agregaron decisiones de Semana 2.
- [ ] No hay secretos ni datos personales reales.
- [ ] La revisión cruzada fue aprobada.

### 12. Comandos de validación

```bash
mvn -Dtest=StoreVerificationDocumentServiceTest test
mvn -Dtest=VerificationDocumentApiIT verify
```

### 13. Evidencia esperada

- Respuesta `201`.
- Ubicación y metadatos del Blob documental.
- Pruebas de archivo ausente y nombre normalizado.

### 14. Instrucción para una IA o integrante

Antes de implementar, debe resumir objetivo, dependencias, archivos, criterios, pruebas, riesgos y fuera de alcance. Después debe listar archivos realmente modificados, pruebas realmente ejecutadas, evidencias, pendientes y cualquier desviación. No puede declarar `DONE` basándose solo en código escrito.

## ISS-S1-010 — Validar escritura, lectura y eliminación en Queue Storage

### Metadatos

- **Historia:** HU-S1-004
- **Feature:** FEAT-S1-004
- **Responsable principal:** Persona 3
- **Revisor:** Persona 2
- **Dependencias para iniciar:** ISS-S1-003, ISS-S1-005 e ISS-S1-006
- **Estimación orientativa:** 0,5 día
- **Flujo:** FM-S1-003
- **Requisitos:** RF-S1-006
- **Pruebas catalogadas:** TEST-S1-020

### 1. Objetivo

Demostrar conectividad y operación básica de las colas de staging y producción sin conectarlas al flujo de transacciones ni definir un mensaje de negocio.

### 2. Contexto y razón técnica

Azure-Semana1 solicita validar la cola. La prueba debe usar un mensaje técnico temporal identificable, eliminarlo al finalizar y revocar cualquier permiso temporal.

### 3. Descripción técnica

- Crear un script que seleccione explícitamente el ambiente.
- Generar un mensaje técnico con `testRunId`, `environment` y `createdAt`; no incluir campos de scoring ni convertirlo en contrato futuro.
- Enviar el mensaje a la cola correspondiente mediante identidad autorizada y conectividad privada.
- Recibir el mismo mensaje, validar su `testRunId` y eliminarlo usando el pop receipt.
- Confirmar que no queden mensajes creados por el run de prueba.
- Revocar la asignación temporal si fue creada exclusivamente para la prueba.

### 4. Fuera de alcance

- Publicar transacciones reales.
- Crear productor Java de Queue.
- Crear consumidor, Function o contrato de evento.
- Realizar pruebas con datos personales reales.

### 5. Archivos que deben crearse

```text
scripts/validate-queue.sh
scripts/tests/test-queue-roundtrip.sh
docs/evidence/queue/.gitkeep
```

### 6. Archivos que pueden modificarse

```text
scripts/validate-week1.sh
scripts/assign-rbac.sh si necesita una asignación temporal documentada.
```

### 7. Archivos prohibidos

```text
src/main/java/**/QueuePublisher.java
src/main/java/**/QueueConsumer.java
docs/transaction-event-v*.json
```

### 8. Criterios de aceptación

- [ ] El mensaje técnico se escribe en la cola del ambiente seleccionado.
- [ ] Se lee exactamente el mensaje creado por el run y se valida su identificador.
- [ ] El mensaje se elimina y la prueba no deja residuos propios.
- [ ] No se utiliza la cola como parte de `POST /api/v1/transactions`.
- [ ] No se define un esquema de negocio para Semana 2.


### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S1-020` | Obligatoria para cerrar | Integración | Queue e infraestructura | Validar roundtrip de Queue Storage |

Las pruebas obligatorias deben pasar antes de cerrar esta issue. Las pruebas posteriores se ejecutan cuando estén disponibles sus dependencias y son obligatorias para cerrar la Semana 1, pero no crean dependencias hacia issues posteriores.

### 10. Escenarios Gherkin

```gherkin
Escenario: Roundtrip exitoso
  Dado una cola vacía y una identidad temporal autorizada
  Cuando el script envía, recibe y elimina un mensaje técnico
  Entonces el mismo `testRunId` es verificado y no quedan residuos del run

Escenario: Ambiente inválido
  Dado el parámetro de ambiente no es `staging` ni `production`
  Cuando se inicia la prueba
  Entonces el script termina sin enviar mensajes

Escenario: Mensaje no recuperado
  Dado el mensaje enviado no aparece dentro del tiempo limitado
  Cuando se agota el número de reintentos
  Entonces la prueba falla, registra evidencia y ejecuta limpieza segura
```

### 11. Definition of Done específica

- [ ] Todos los criterios de aceptación están demostrados.
- [ ] Solo se crearon o modificaron archivos autorizados.
- [ ] Las pruebas obligatorias disponibles para esta etapa pasaron.
- [ ] Las pruebas posteriores quedaron trazadas con su issue bloqueadora.
- [ ] Existe evidencia reproducible y sanitizada.
- [ ] No se agregaron decisiones de Semana 2.
- [ ] No hay secretos ni datos personales reales.
- [ ] La revisión cruzada fue aprobada.

### 12. Comandos de validación

```bash
./scripts/validate-queue.sh staging
./scripts/validate-queue.sh production
```

### 13. Evidencia esperada

- Payload técnico sanitizado.
- Identificador de mensaje y confirmación de eliminación.
- Asignación temporal y evidencia de revocación, si aplica.

### 14. Instrucción para una IA o integrante

Antes de implementar, debe resumir objetivo, dependencias, archivos, criterios, pruebas, riesgos y fuera de alcance. Después debe listar archivos realmente modificados, pruebas realmente ejecutadas, evidencias, pendientes y cualquier desviación. No puede declarar `DONE` basándose solo en código escrito.

## ISS-S1-011 — Proteger endpoints y verificar mínimo privilegio

### Metadatos

- **Historia:** HU-S1-002
- **Feature:** FEAT-S1-002
- **Responsable principal:** Persona 3
- **Revisor:** Persona 2
- **Dependencias para iniciar:** ISS-S1-006, ISS-S1-007 e ISS-S1-009
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S1-001 y FM-S1-002
- **Requisitos:** RS-S1-001..004
- **Pruebas catalogadas:** TEST-S1-021, TEST-S1-022, TEST-S1-016, TEST-S1-019

### 1. Objetivo

Configurar Spring Security para que cada endpoint acepte únicamente los roles previstos y distinga correctamente falta de autenticación y falta de autorización.

### 2. Contexto y razón técnica

Los app roles de Entra son conceptos funcionales. Spring debe convertir el claim `roles` a authorities `ROLE_*` sin confundirlos con Azure RBAC.

### 3. Descripción técnica

- Configurar la aplicación como OAuth2 Resource Server JWT usando issuer/audience por variables de entorno no secretas.
- Crear un convertidor que transforme `SERVICE`, `ANALYST`, `ADMINISTRATOR` y `AUDITOR` en `ROLE_SERVICE`, `ROLE_ANALYST`, `ROLE_ADMINISTRATOR` y `ROLE_AUDITOR`.
- Permitir `POST /api/v1/transactions` solo a `ROLE_SERVICE`.
- Permitir `POST /api/v1/verification-documents` solo a `ROLE_ANALYST`.
- Devolver `401` cuando no exista token válido y `403` cuando el token sea válido pero el rol no esté autorizado.
- No registrar tokens completos, claims sensibles ni encabezados Authorization.

### 4. Fuera de alcance

- Login UI o frontend.
- Administración de usuarios.
- Permisos de Semana 2.
- Autorización basada en score/caso.

### 5. Archivos que deben crearse

```text
src/main/java/com/centinela/identityaccess/SecurityConfiguration.java
src/main/java/com/centinela/identityaccess/EntraRolesJwtAuthenticationConverter.java
src/main/java/com/centinela/identityaccess/RestAuthenticationEntryPoint.java
src/main/java/com/centinela/identityaccess/RestAccessDeniedHandler.java
src/test/java/com/centinela/identityaccess/EndpointAuthorizationTest.java

src/test/java/com/centinela/identityaccess/TransactionEndpointAuthorizationIT.java
src/test/java/com/centinela/identityaccess/DocumentEndpointAuthorizationIT.java
```

### 6. Archivos que pueden modificarse

```text
application*.yml
TransactionController.java y VerificationDocumentController.java solo para anotaciones de seguridad si se aprueba ese enfoque.
```

### 7. Archivos prohibidos

```text
credenciales de usuarios
client secrets en recursos
logging de `Authorization`.
```

### 8. Criterios de aceptación

- [ ] Sin token, ambos endpoints devuelven `401`.
- [ ] Servicio puede enviar transacciones y no puede cargar documentos.
- [ ] Analista puede cargar documentos; Administrador, Servicio y Auditor no pueden ejecutar operaciones de escritura en los endpoints de Semana 1.
- [ ] Auditor no puede ejecutar operaciones de escritura.
- [ ] Los errores `401/403` no filtran detalles del token.


### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S1-021` | Obligatoria para cerrar | Integración | Seguridad HTTP | Autorizar únicamente Servicio en transacciones |
| `TEST-S1-022` | Obligatoria para cerrar | Integración | Seguridad HTTP | Autorizar únicamente Analista en carga documental |
| `TEST-S1-016` | Posterior de integración | E2E | API de ingesta | Recibir y almacenar una transacción válida desplegada |
| `TEST-S1-019` | Posterior de integración | E2E | Documentos y almacenamiento | Cargar documento desde la API y comprobar Blob |

Las pruebas obligatorias deben pasar antes de cerrar esta issue. Las pruebas posteriores se ejecutan cuando estén disponibles sus dependencias y son obligatorias para cerrar la Semana 1, pero no crean dependencias hacia issues posteriores.

### 10. Escenarios Gherkin

```gherkin
Escenario: Servicio autorizado
  Dado un JWT válido con rol SERVICE
  Cuando envía una transacción válida
  Entonces la solicitud supera la autorización y continúa al caso de uso

Escenario: Rol incorrecto
  Dado un JWT válido con rol ANALYST
  Cuando intenta enviar una transacción
  Entonces la API devuelve `403` y no persiste Blob

Escenario: Sin autenticación
  Dado una solicitud sin bearer token
  Cuando intenta cargar un documento
  Entonces la API devuelve `401` y no ejecuta el caso de uso
```

### 11. Definition of Done específica

- [ ] Todos los criterios de aceptación están demostrados.
- [ ] Solo se crearon o modificaron archivos autorizados.
- [ ] Las pruebas obligatorias disponibles para esta etapa pasaron.
- [ ] Las pruebas posteriores quedaron trazadas con su issue bloqueadora.
- [ ] Existe evidencia reproducible y sanitizada.
- [ ] No se agregaron decisiones de Semana 2.
- [ ] No hay secretos ni datos personales reales.
- [ ] La revisión cruzada fue aprobada.

### 12. Comandos de validación

```bash
mvn -Dtest=EndpointAuthorizationTest test
mvn verify
```

### 13. Evidencia esperada

- Matriz rol/endpoint con resultados.
- Respuestas `401` y `403` sanitizadas.
- Prueba de que no se registran tokens.

### 14. Instrucción para una IA o integrante

Antes de implementar, debe resumir objetivo, dependencias, archivos, criterios, pruebas, riesgos y fuera de alcance. Después debe listar archivos realmente modificados, pruebas realmente ejecutadas, evidencias, pendientes y cualquier desviación. No puede declarar `DONE` basándose solo en código escrito.

## ISS-S1-012 — Probar alta disponibilidad de la API

### Metadatos

- **Historia:** HU-S1-005
- **Feature:** FEAT-S1-005
- **Responsable principal:** Persona 4
- **Revisor:** Persona 3
- **Dependencias para iniciar:** ISS-S1-004, ISS-S1-005, ISS-S1-006, ISS-S1-008 e ISS-S1-011
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S1-005
- **Requisitos:** RI-S1-005; RNF-S1-002
- **Pruebas catalogadas:** TEST-S1-024

### 1. Objetivo

Demostrar que la API continúa aceptando solicitudes cuando una de dos instancias temporales deja de estar disponible, y regresar inmediatamente a una instancia.

### 2. Contexto y razón técnica

La prueba debe cumplir disponibilidad sin convertir dos instancias en operación permanente. Debe reconciliar cada respuesta aceptada con su Blob para evitar declarar éxito solo por códigos HTTP.

### 3. Descripción técnica

- Crear un script que registre la capacidad original y la restaure en `finally`/trap.
- Escalar temporalmente el App Service Plan/Web App de una a dos instancias.
- Generar solicitudes válidas continuas con IDs únicos y registrar código HTTP, timestamp y transactionId.
- Retirar o reiniciar una sola instancia mediante un mecanismo controlado disponible en App Service.
- Continuar la carga durante la retirada y contabilizar errores de conectividad o `5xx`.
- Para cada `202`, verificar que exista el Blob correspondiente. Al finalizar, volver a una instancia incluso si la prueba falla.

### 4. Fuera de alcance

- Prueba de rendimiento o capacidad máxima.
- Alta disponibilidad multirregión.
- Mantener dos instancias permanentemente.
- Pruebas de scoring o Queue.

### 5. Archivos que deben crearse

```text
scripts/test-ha.sh
scripts/tests/send-transaction-load.sh
scripts/tests/reconcile-accepted-transactions.sh
docs/evidence/ha/.gitkeep
```

### 6. Archivos que pueden modificarse

```text
scripts/validate-week1.sh
```

### 7. Archivos prohibidos

```text
configuración permanente de dos instancias
scripts/load-test-production-unbounded.sh
```

### 8. Criterios de aceptación

- [ ] La prueba inicia con una instancia y escala temporalmente a dos.
- [ ] Se retira solo una instancia durante solicitudes continuas.
- [ ] La API continúa respondiendo; cualquier `202` tiene Blob asociado.
- [ ] El informe muestra solicitudes totales, aceptadas, fallidas y reconciliadas.
- [ ] La capacidad vuelve a una instancia aunque haya error en la prueba.


### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S1-024` | Obligatoria para cerrar | E2E | Disponibilidad y resiliencia | Mantener disponibilidad al retirar una instancia |

Las pruebas obligatorias deben pasar antes de cerrar esta issue. Las pruebas posteriores se ejecutan cuando estén disponibles sus dependencias y son obligatorias para cerrar la Semana 1, pero no crean dependencias hacia issues posteriores.

### 10. Escenarios Gherkin

```gherkin
Escenario: Continuidad con una instancia retirada
  Dado dos instancias activas y carga continua
  Cuando se retira una instancia
  Entonces las solicitudes siguen llegando a la instancia restante y cada `202` se reconcilia con Blob

Escenario: No se alcanza capacidad dos
  Dado Azure no permite escalar a dos instancias
  Cuando se inicia la prueba
  Entonces la prueba se detiene sin simular éxito y conserva la capacidad original

Escenario: Fallo durante la prueba
  Dado un comando intermedio termina con error
  Cuando se activa el trap de limpieza
  Entonces la capacidad vuelve a una instancia y se guarda evidencia parcial
```

### 11. Definition of Done específica

- [ ] Todos los criterios de aceptación están demostrados.
- [ ] Solo se crearon o modificaron archivos autorizados.
- [ ] Las pruebas obligatorias disponibles para esta etapa pasaron.
- [ ] Las pruebas posteriores quedaron trazadas con su issue bloqueadora.
- [ ] Existe evidencia reproducible y sanitizada.
- [ ] No se agregaron decisiones de Semana 2.
- [ ] No hay secretos ni datos personales reales.
- [ ] La revisión cruzada fue aprobada.

### 12. Comandos de validación

```bash
./scripts/test-ha.sh
./scripts/tests/reconcile-accepted-transactions.sh
```

### 13. Evidencia esperada

- Archivo de carga con IDs y estados.
- Evento o captura de retirada de instancia.
- Reporte de reconciliación y capacidad final igual a uno.

### 14. Instrucción para una IA o integrante

Antes de implementar, debe resumir objetivo, dependencias, archivos, criterios, pruebas, riesgos y fuera de alcance. Después debe listar archivos realmente modificados, pruebas realmente ejecutadas, evidencias, pendientes y cualquier desviación. No puede declarar `DONE` basándose solo en código escrito.

## ISS-S1-013 — Completar README, matriz, diagrama, ADR y evidencias

### Metadatos

- **Historia:** HU-S1-005
- **Feature:** FEAT-S1-005
- **Responsable principal:** Persona 4
- **Revisor:** Persona 5
- **Dependencias para iniciar:** ISS-S1-001..ISS-S1-012
- **Estimación orientativa:** 1 día
- **Flujo:** Todos los flujos de Semana 1
- **Requisitos:** Todos los requisitos de Semana 1
- **Pruebas catalogadas:** TEST-S1-002, TEST-S1-025, TEST-S1-028

### 1. Objetivo

Consolidar una documentación verificable que explique lo construido, cómo reproducirlo, qué evidencia demuestra cada requisito y qué decisiones permanecen abiertas para Semana 2.

### 2. Contexto y razón técnica

La documentación no debe convertirse en una fuente de requisitos nuevos. Debe reflejar el sistema realmente implementado y conservar explícitamente los límites de Semana 1.

### 3. Descripción técnica

- Actualizar README con prerrequisitos, parámetros, despliegue, validación, destrucción y control de costos.
- Crear diagrama de contexto/arquitectura que muestre App Service, VNet, Storage, Entra y los dos endpoints, dejando Queue desconectada del flujo de negocio.
- Crear ADR breves para arquitectura hexagonal, Managed Identity, Storage privado y separación lógica staging/production.
- Actualizar matriz requisito → issue → prueba → evidencia.
- Crear un índice de evidencias con commit, ambiente, runId, timestamp y ruta; sanitizar IDs sensibles.
- Crear una sección “Decisiones reservadas para Semana 2” sin proponer soluciones.

### 4. Fuera de alcance

- Diseñar scoring, bases de datos, contratos de eventos o consumidor.
- Agregar servicios no implementados al diagrama.
- Documentar resultados de pruebas que no se ejecutaron.

### 5. Archivos que deben crearse

```text
docs/architecture/centinela-week1.md
docs/adr/ADR-001-hexagonal.md
docs/adr/ADR-002-managed-identity.md
docs/adr/ADR-003-private-storage.md
docs/adr/ADR-004-environment-separation.md
docs/evidence/INDEX.md
docs/week2/OPEN_DECISIONS.md

scripts/tests/validate-documentation.sh
scripts/tests/validate-week1-scope.sh
```

### 6. Archivos que pueden modificarse

```text
README.md
5_Issues_y_Trazabilidad/2_Matriz_Trazabilidad.md
0_Vision/3_Checkpoint_Alcance.md
7_Gestion_y_Trabajo_IA/5_Reporte_Validacion.md
```

### 7. Archivos prohibidos

```text
docs/week2/solution-design.md
afirmaciones de pruebas no ejecutadas
secretos o capturas sin sanitizar.
```

### 8. Criterios de aceptación

- [ ] README permite a otra persona desplegar y destruir sin instrucciones orales.
- [ ] El diagrama coincide con los recursos reales de Semana 1.
- [ ] Cada requisito apunta a issue, prueba y evidencia.
- [ ] Las decisiones de Semana 2 aparecen como abiertas, no resueltas.
- [ ] No hay secretos ni PII en documentación o evidencias.


### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S1-002` | Obligatoria para cerrar | Estático | Seguridad e higiene | Detectar secretos y archivos sensibles versionados |
| `TEST-S1-025` | Obligatoria para cerrar | Estático | Documentación | Validar entregables documentales y trazabilidad |
| `TEST-S1-028` | Obligatoria para cerrar | Estático | Control de alcance | Verificar que no se implementó alcance de Semana 2 |

Las pruebas obligatorias deben pasar antes de cerrar esta issue. Las pruebas posteriores se ejecutan cuando estén disponibles sus dependencias y son obligatorias para cerrar la Semana 1, pero no crean dependencias hacia issues posteriores.

### 10. Escenarios Gherkin

```gherkin
Escenario: Trazabilidad completa
  Dado los requisitos, issues y pruebas terminados
  Cuando se revisa la matriz
  Entonces cada requisito tiene al menos una issue, prueba y evidencia verificable

Escenario: Decisión futura no aprobada
  Dado un texto propone una base de datos o evento para Semana 2
  Cuando se ejecuta la revisión anti-alcance
  Entonces la documentación se rechaza hasta reemplazarlo por una decisión abierta

Escenario: Evidencia sensible
  Dado una captura contiene token o identificador sensible
  Cuando se revisa antes de versionar
  Entonces la evidencia se sanitiza o no se incorpora
```

### 11. Definition of Done específica

- [ ] Todos los criterios de aceptación están demostrados.
- [ ] Solo se crearon o modificaron archivos autorizados.
- [ ] Las pruebas obligatorias disponibles para esta etapa pasaron.
- [ ] Las pruebas posteriores quedaron trazadas con su issue bloqueadora.
- [ ] Existe evidencia reproducible y sanitizada.
- [ ] No se agregaron decisiones de Semana 2.
- [ ] No hay secretos ni datos personales reales.
- [ ] La revisión cruzada fue aprobada.

### 12. Comandos de validación

```bash
mvn clean verify
./scripts/validate-week1.sh
grep -RInE "AccountKey=|client_secret|Bearer [A-Za-z0-9]" docs README.md
```

### 13. Evidencia esperada

- README y diagrama revisados.
- Matriz completa.
- Índice de evidencias con enlaces válidos.
- Aprobación de revisión cruzada.

### 14. Instrucción para una IA o integrante

Antes de implementar, debe resumir objetivo, dependencias, archivos, criterios, pruebas, riesgos y fuera de alcance. Después debe listar archivos realmente modificados, pruebas realmente ejecutadas, evidencias, pendientes y cualquier desviación. No puede declarar `DONE` basándose solo en código escrito.

## ISS-S1-014 — Ejecutar destrucción, reconstrucción y cierre final

### Metadatos

- **Historia:** HU-S1-001
- **Feature:** FEAT-S1-001
- **Responsable principal:** Persona 5
- **Revisor:** Persona 4
- **Dependencias para iniciar:** ISS-S1-013
- **Estimación orientativa:** 1 día
- **Flujo:** FM-S1-004
- **Requisitos:** RI-S1-001; RI-S1-006; RNF-S1-004
- **Pruebas catalogadas:** TEST-S1-026, TEST-S1-027

### 1. Objetivo

Demostrar desde un entorno limpio que los scripts reconstruyen la Semana 1 sin pasos manuales y eliminar los recursos al finalizar para controlar costos.

### 2. Contexto y razón técnica

Esta es la prueba de cierre, no una nueva implementación. Puede corregir defectos encontrados en scripts o documentación, pero no introducir servicios o alcance adicionales.

### 3. Descripción técnica

- Registrar el estado inicial y confirmar el Resource Group objetivo.
- Ejecutar `destroy-week1.sh` y comprobar que el Resource Group de práctica se eliminó.
- Ejecutar `deploy-week1.sh` desde cero con parámetros aprobados.
- Ejecutar `validate-week1.sh` y las pruebas funcionales, seguridad, Queue y disponibilidad aplicables.
- Guardar un reporte final con comandos, commit, ambiente, runId, timestamps, resultados y desviaciones.
- Regresar a una instancia y destruir nuevamente los recursos cuando termine la demostración, salvo instrucción explícita del equipo para conservarlos temporalmente.

### 4. Fuera de alcance

- Cambios arquitectónicos no revisados.
- Añadir CI/CD.
- Dejar recursos costosos encendidos sin responsable y fecha de retiro.
- Simular evidencia.

### 5. Archivos que deben crearse

```text
docs/evidence/final/{runId}/deployment.log
docs/evidence/final/{runId}/validation-summary.md
docs/evidence/final/{runId}/resource-inventory.json
docs/evidence/final/{runId}/cleanup.log

scripts/tests/test-clean-deploy.sh
scripts/tests/test-destroy-rebuild-cleanup.sh
```

### 6. Archivos que pueden modificarse

```text
Scripts o documentación únicamente para corregir fallas encontradas y con revisión cruzada.
```

### 7. Archivos prohibidos

```text
Nuevos módulos de negocio.
Recursos de Semana 2.
Credenciales o tokens dentro de logs.
```

### 8. Criterios de aceptación

- [ ] El Resource Group puede eliminarse mediante el script seguro.
- [ ] El entorno completo se reconstruye desde cero sin configurar recursos manualmente.
- [ ] Las validaciones obligatorias pasan y las evidencias se enlazan.
- [ ] La capacidad final es una instancia antes de la limpieza.
- [ ] Los recursos se destruyen al terminar o existe una excepción documentada con responsable y fecha.


### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Propósito |
|---|---|---|---|---|
| `TEST-S1-026` | Obligatoria para cerrar | E2E | Infraestructura reproducible | Desplegar desde una suscripción o Resource Group limpio |
| `TEST-S1-027` | Obligatoria para cerrar | E2E | Infraestructura reproducible y costos | Destruir, reconstruir, validar y limpiar |

Las pruebas obligatorias deben pasar antes de cerrar esta issue. Las pruebas posteriores se ejecutan cuando estén disponibles sus dependencias y son obligatorias para cerrar la Semana 1, pero no crean dependencias hacia issues posteriores.

### 10. Escenarios Gherkin

```gherkin
Escenario: Reconstrucción completa
  Dado el Resource Group de práctica no existe
  Cuando se ejecuta el despliegue y validación final
  Entonces todos los recursos de Semana 1 aparecen y las pruebas obligatorias pasan

Escenario: Parámetro inválido
  Dado la reconstrucción recibe una suscripción o prefijo no aprobado
  Cuando se ejecuta el script
  Entonces el proceso se detiene antes de crear recursos

Escenario: Limpieza final
  Dado la demostración terminó
  Cuando se ejecuta el script de destrucción
  Entonces el Resource Group se elimina y queda evidencia sin secretos
```

### 11. Definition of Done específica

- [ ] Todos los criterios de aceptación están demostrados.
- [ ] Solo se crearon o modificaron archivos autorizados.
- [ ] Las pruebas obligatorias disponibles para esta etapa pasaron.
- [ ] Las pruebas posteriores quedaron trazadas con su issue bloqueadora.
- [ ] Existe evidencia reproducible y sanitizada.
- [ ] No se agregaron decisiones de Semana 2.
- [ ] No hay secretos ni datos personales reales.
- [ ] La revisión cruzada fue aprobada.

### 12. Comandos de validación

```bash
./scripts/destroy-week1.sh
./scripts/deploy-week1.sh
./scripts/validate-week1.sh
mvn clean verify
```

### 13. Evidencia esperada

- Logs sanitizados de destrucción y reconstrucción.
- Inventario de recursos.
- Resumen de pruebas.
- Confirmación final de limpieza o excepción temporal aprobada.

### 14. Instrucción para una IA o integrante

Antes de implementar, debe resumir objetivo, dependencias, archivos, criterios, pruebas, riesgos y fuera de alcance. Después debe listar archivos realmente modificados, pruebas realmente ejecutadas, evidencias, pendientes y cualquier desviación. No puede declarar `DONE` basándose solo en código escrito.


## Regla de cierre del backlog

Una issue solo se cierra con evidencia de sus pruebas obligatorias. La Semana 1 solo se cierra cuando `ISS-S1-014` ejecuta también todas las pruebas posteriores de integración y confirma reconstrucción y limpieza. No se agregan issues de scoring, reglas, casos, IA, consumidor de cola, bases futuras o CI/CD obligatorio hasta recibir el alcance oficial de Semana 2.
