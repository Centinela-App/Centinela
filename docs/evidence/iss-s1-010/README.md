# Evidencia ISS-S1-010 — Roundtrip real de Queue Storage

**Prueba obligatoria:** TEST-S1-020.

## Estado

- Scripts corregidos: `scripts/validate-queue.sh` y
  `scripts/tests/test-queue-roundtrip.sh`.
- La ejecución real sigue pendiente hasta correrla en Azure desde un host conectado a la
  VNet. No se considera válida una corrida desde un host que resuelva el endpoint público.

## Comportamiento exigido

La prueba:

1. verifica que Storage conserve `publicNetworkAccess=Disabled`;
2. confirma que el nombre de Queue resuelva a una IP privada;
3. envía un mensaje con `testRunId` único;
4. busca exactamente ese mensaje sin asumir que la cola está vacía;
5. lo elimina usando `messageId` y `popReceipt`;
6. confirma que el `testRunId` propio ya no existe.

Para enviar, recibir y eliminar se requieren temporalmente los dos roles mínimos:

- `Storage Queue Data Message Sender`;
- `Storage Queue Data Message Processor`.

El orquestador final registra cuáles asignaciones creó y revoca únicamente esas
asignaciones al terminar.

## Comandos aislados

```bash
bash scripts/validate-queue.sh staging
bash scripts/validate-queue.sh production
```

La evidencia por corrida queda bajo `docs/evidence/queue/run-*/` e incluye payload
sanitizado, respuesta de envío, mensajes inspeccionados, eliminación y resumen final.
