# Evidencia ISS-S1-012 — Probar alta disponibilidad de la API

**Prueba obligatoria:** TEST-S1-024 (mantener disponibilidad al retirar una instancia).

## Estado

- **Código/scripts:** completos (`scripts/test-ha.sh`, `scripts/tests/send-transaction-load.sh`,
  `scripts/tests/reconcile-accepted-transactions.sh`).
- **Verificación local reproducible:** `01-syntax-check.txt` — `bash -n` OK en los tres scripts.
- **Ejecución de la prueba HA real:** requiere el App Service desplegado y una suscripción
  activa para escalar temporalmente a dos instancias, retirar una y reconciliar cada `202`
  con su Blob.

## Diseño verificado (estático)

- Registra la capacidad original y la restaura en `trap`/`finally` (vuelve a una instancia
  aunque la prueba falle).
- Escala temporalmente a dos instancias, retira una durante carga continua y contabiliza
  solicitudes totales, aceptadas, fallidas y reconciliadas.
- Reconcilia cada `202` con el Blob correspondiente (no declara éxito solo por HTTP).

## Comandos reproducibles (con suscripción)

```bash
./scripts/test-ha.sh
./scripts/tests/reconcile-accepted-transactions.sh
```

## Pendiente de suscripción Azure

Archivo de carga con IDs y estados, evento de retirada de instancia y reporte de
reconciliación con capacidad final = 1 — se generan al ejecutar contra el App Service real.
