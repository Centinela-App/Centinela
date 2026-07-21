# Evidencia ISS-S1-010 — Validar escritura, lectura y eliminación en Queue Storage

**Prueba obligatoria:** TEST-S1-020 (roundtrip de Queue Storage).

## Estado

- **Código/scripts:** completos y restaurados (`scripts/validate-queue.sh`,
  `scripts/tests/test-queue-roundtrip.sh`). Reintegrados tras el revert accidental del PR #26.
- **Verificación local reproducible:** `01-syntax-check.txt` — `bash -n` OK en ambos scripts.
- **Ejecución del roundtrip real:** requiere una suscripción Azure activa con la cola
  provisionada (`transactions-ingestion-{staging|production}`), conectividad privada y la
  asignación temporal `Storage Queue Data Message Processor`.

## Comandos reproducibles (con suscripción)

```bash
./scripts/validate-queue.sh staging
./scripts/validate-queue.sh production
```

El script envía un mensaje técnico (`testRunId`, `environment`, `createdAt`), lo recibe,
valida el `testRunId`, lo elimina con el pop receipt y confirma que no quedan residuos.

## Pendiente de suscripción Azure

Payload sanitizado, ID de mensaje, confirmación de eliminación y evidencia de revocación
de la asignación temporal — se generan al ejecutar contra la cola real. No se fabrica
evidencia de Azure (regla del DoD: "No simular evidencia").
