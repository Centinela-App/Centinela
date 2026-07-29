# Alcance de Semana 3 — Despliegue automatizado, explicabilidad y observabilidad

Esta semana el sistema pasa de funcional a **operable**, y cierra el proyecto.

Fuera de alcance, por decisión del enunciado: orquestación con clusters gestionados, modelos de
lenguaje generativo y entornos de staging con intercambio de despliegue.

---

## Lo que la auditoría encontró antes de empezar

Semanas 1 y 2 estaban completas en funcionalidad. Cuatro hallazgos condicionaron el plan:

1. **La traza distribuida era imposible con los contratos existentes.** Ni
   `transaction-event-v1` ni `flagged-case-v1` llevaban contexto de traza. El recorrido cruza
   Event Grid y una Storage Queue: sin propagarlo, se corta en cada salto y quedan cuatro trazas
   inconexas.
2. **El motor no registró lo suficiente para explicarse.** `GeoImpossibleRule` guardaba
   distancia y tiempo pero no las ciudades; `VelocityRule` no medía la cadencia habitual de la
   cuenta. La salida ejemplo del enunciado no era reproducible. El propio enunciado anticipa
   este caso y asigna la corrección al motor.
3. **El caso no tenía dónde guardar su explicación** ni los datos del documento, ni siquiera la
   cuenta a la que pertenece.
4. **No existía el informe de cuotas de Document Intelligence** que el punto 2.3 da por hecho:
   la Semana 1 dejó el OCR explícitamente fuera de alcance.

---

## Qué se construyó

### Trazabilidad de extremo a extremo

`traceparent` en formato W3C viaja **dentro** de los dos contratos. El filtro HTTP continúa la
traza del cliente si viene, o la abre. El motor la hereda al puntuar, la reemite en el mensaje
de caso, y el explicador la conserva. Un `traceparent` corrupto abre una traza nueva en lugar de
rechazar la transacción: la telemetría nunca tumba el negocio.

### Motor con registro suficiente

Las tres reglas afectadas ahora registran lo que la explicación necesita: ciudades de origen y
destino, lapso real de la ráfaga, cadencia histórica de la cuenta, multiplicador observado. El
`Score` guarda el **umbral vigente en el instante de decidir** — es configurable en caliente, y
leerlo después falsearía retroactivamente todos los casos anteriores.

### Explicador de casos

Plantilla determinista, sin modelo de lenguaje. Corre en un proceso aparte que consulta casos
con `explanation_state = 'PENDING'`. Detenerlo es escalar su Container App a cero; al volver,
recupera el backlog sin intervención.

Cuando falta un dato, la frase **se empobrece en lugar de rellenarse**: sin ciudad registrada se
habla de distancia, sin cadencia medida no se menciona ningún promedio. Una regla que la
plantilla no conoce se enumera con sus valores crudos en vez de omitirse — ocultarla dejaría un
score que no cuadra con las frases mostradas.

### Verificación documental

Extracción con PDFBox dentro del componente: es el **plan alternativo** que el enunciado prevé.
El extractor nunca lanza; distingue PDF corrupto, PDF sin capa de texto, formato no soportado,
archivo vacío y texto sin campos de identidad, y cada desenlace lleva un mensaje accionable. El
resultado se escribe como fila con estado más entrada en la bitácora inmutable del caso.

**Limitación declarada:** no hace OCR. Un escaneo sin capa de texto se reporta como ilegible en
vez de devolver campos vacíos que parezcan un documento legítimo sin datos.

### API de consulta

`GET /api/v1/transactions/{id}/analysis` y `GET /api/v1/cases/{transactionId}`. No existían: la
ingesta responde `202` antes de que haya veredicto, así que durante dos semanas el resultado
solo era observable entrando a la base de datos. Un `404` en `/cases` significa "esta
transacción no fue marcada", que es la respuesta correcta para una transacción normal.

### Contenedores y escalado

Dos imágenes multietapa. Una sola imagen de aplicación cumple tres papeles —API, explicador,
extractor— según qué interruptores encienda la plataforma. Tres métricas de escalado, una por
componente, justificadas en `ADR-010`.

### Despliegue continuo

GitHub Actions con OIDC. **Cero credenciales**: no hay contraseña, certificado ni JSON de
service principal en ningún sitio. Un fallo de prueba detiene el pipeline antes de construir
ninguna imagen, porque el trabajo que publica declara `needs` sobre el que prueba.

### Observabilidad

Instrumentación por etapas con duración y desenlace, en formato clave-valor estable. Las cinco
consultas de operación están escritas y verificadas en `docs/observabilidad/consultas-kql.md`.
Una alerta, con umbral justificado: más de 5 transacciones ingeridas sin puntuar en 15 minutos.

### Banco de pruebas — repositorio aparte

`centinela-lab` es un cliente externo. Un botón por causal de alerta, un control negativo, un
escenario de documento ilegible y un generador de carga. No comparte código, base de datos ni
despliegue con Centinela: se comunica solo por la API pública.

### Agentes de verificación

Siete definiciones en `.claude/agents/`, cada una apoyada en scripts ejecutables de
`scripts/verify/`. El veredicto se sustenta en salida de comando, de modo que un tercero pueda
reproducirlo sin depender de una IA.

---

## Mapa de entregables

| # | Entregable | Dónde está |
|---|---|---|
| 1 | Pipeline de despliegue continuo | `.github/workflows/cd.yml` |
| 2 | Justificación de la plataforma de CI/CD | `ADR-008` |
| 3 | Aplicación contenedorizada | `Dockerfile`, `scoring-function/Dockerfile` |
| 4 | Reglas de escalado y evidencia | `ADR-010`, `scripts/provision-container-apps.sh`, `scripts/verify/verify-scaling.sh` |
| 5 | Reporte de optimización de imágenes | `scripts/verify/report-image-size.sh` |
| 6 | Flujo de verificación documental | módulo `documentverification` |
| 7 | Explicador de casos | módulo `caseexplanation` |
| 8 | Instrumentación del pipeline | `shared/telemetry`, `docs/observabilidad/consultas-kql.md` |
| 9 | Alerta configurada | `scripts/provision-observability.sh` |
| 10 | Reporte de crédito consumido | `scripts/tests/validate-week2-closeout.sh` + `scripts/shutdown-daily.sh` |
| 11 | Documento de decisiones cerrado | `docs/2_Arquitectura/2_ADR_Decisiones_Arquitectura.md` |
| 12 | README de despliegue | `README.md` y `docs/4_Infraestructura_y_Despliegue/5_Runbook_Despliegue_Completo.md` |

---

## Los ocho escenarios de la sustentación

| # | Escenario | Cómo se demuestra |
|---|---|---|
| 1 | Transacción normal, sin marcar | Botón **Transacción normal** en `centinela-lab` |
| 2 | Transacción fraudulenta, caso con explicación | Botón **Fraude combinado** |
| 3 | El cliente respondió antes del análisis | El `202` llega en milisegundos; el veredicto tarda segundos |
| 4 | Escalado bajo carga | Botón **Generar carga** + `scripts/verify/verify-scaling.sh` |
| 5 | Traza completa de una transacción | `scripts/verify/verify-trace.sh <transactionId>` |
| 6 | Integración que dispara despliegue | Un commit a `main` |
| 7 | **Documento ilegible** | Botón **Documento ilegible** |
| 8 | **Explicador detenido** | Escalar a cero `ca-<prefijo>-explainer` y lanzar el escenario 2 |

Los puntos 7 y 8 son escenarios de fallo y su inclusión es obligatoria.

---

## Verificación del estado

```bash
# Calidad estructural, sin necesidad de Azure
bash scripts/verify/verify-practices.sh

# Con el sistema desplegado
bash scripts/verify/verify-trace.sh <transactionId>
bash scripts/verify/verify-explainer-correspondence.sh <transactionId>
bash scripts/verify/verify-scaling.sh
```
