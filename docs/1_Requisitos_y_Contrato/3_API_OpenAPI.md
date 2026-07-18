# 06 — Contrato API de Semana 1

La fuente ejecutable es `openapi-centinela-semana1.yaml`.

## POST `/api/v1/transactions`

- Actor: Servicio.
- Valida el contrato.
- Guarda el JSON original.
- Devuelve `202` sin análisis.

Respuesta:

```json
{
  "transactionId": "tx-1001",
  "status": "RECEIVED"
}
```

## POST `/api/v1/verification-documents`

- Actor: Analista; la autorización por rol se completa en `ISS-S1-011`.
- Entrada: `multipart/form-data` con un único campo obligatorio `file`.
- Rechaza archivos ausentes o vacíos con `400`.
- Normaliza el nombre original para eliminar rutas, separadores y caracteres inseguros.
- Guarda los bytes en `yyyy/MM/dd/{documentId}/{nombreNormalizado}` dentro del contenedor documental del ambiente.
- Devuelve `201` solo después de que Blob confirma la escritura.
- Si Blob no está disponible, devuelve `503` sin exponer detalles internos.

Respuesta:

```json
{
  "documentId": "doc-1001",
  "status": "STORED"
}
```

La solicitud y la respuesta no contienen `caseId`; la carga no se asocia todavía a un caso de fraude.

## Decisiones aplazadas

No se publica en OpenAPI ningún endpoint de score, regla, caso, historial o IA. Tampoco se define un endpoint de consumo de cola.
