# Evidencia ISS-S1-012 — Alta disponibilidad de la API

**Prueba obligatoria:** TEST-S1-024.

## Estado

- Scripts corregidos: `scripts/test-ha.sh`,
  `scripts/tests/send-transaction-load.sh` y
  `scripts/tests/reconcile-accepted-transactions.sh`.
- La corrida Azure real sigue pendiente hasta ejecutarla contra la aplicación desplegada.

## Comportamiento exigido

La prueba:

1. exige capacidad inicial igual a `1`;
2. escala el App Service Plan a `2` y confirma el cambio;
3. mantiene carga autenticada mientras vuelve a `1`;
4. separa fallos de transporte, respuestas `5xx` y otras respuestas HTTP;
5. reconcilia cada transacción aceptada con HTTP `202` contra su Blob;
6. restaura la capacidad original aun si ocurre un error;
7. elimina los Blobs sintéticos de la corrida.

No pasa si no hubo solicitudes, no hubo respuestas `202`, falta algún Blob aceptado, la
capacidad final no es `1` o un subproceso termina con error.

## Comando aislado

```bash
bash scripts/test-ha.sh
```

Requiere `CENTINELA_SERVICE_TOKEN`, conectividad privada a Blob y permiso temporal
`Storage Blob Data Contributor` sobre `raw-transactions-production`. La evidencia queda
en `docs/evidence/ha/run-*/`.
