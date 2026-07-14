# 03 — Flujos y casos de uso

## FM-S1-001 — Ingestar transacción

1. El sistema originador obtiene un token con el rol o permiso de Servicio.
2. Envía una transacción a `POST /api/v1/transactions`.
3. El controller valida el DTO.
4. El puerto de entrada invoca el caso de uso.
5. El caso de uso conserva el JSON original mediante el puerto Blob.
6. La API devuelve `202 Accepted` con `transactionId` y estado `RECEIVED`.

### Errores

- Payload inválido: `400 Bad Request`.
- Sin autenticación: `401 Unauthorized`.
- Rol no autorizado: `403 Forbidden`.
- Storage no disponible: `503 Service Unavailable`.

### Prohibido en este flujo

No calcular score, consultar historial, aplicar reglas, publicar eventos de scoring ni abrir casos.

## FM-S1-002 — Cargar documento

1. Analista envía un archivo por `multipart/form-data` a `POST /api/v1/verification-documents`.
2. La API valida que exista un archivo (campo `file`) y conserva su nombre y tipo.
3. El caso de uso lo guarda en el contenedor documental del ambiente.
4. Devuelve `201 Created` con `documentId`.

El documento todavía no se asocia a un caso porque los casos pertenecen a Semana 2.

## FM-S1-003 — Validar Queue Storage

1. Se crea una cola por ambiente.
2. Desde un contexto con conectividad autorizada se escribe un mensaje temporal.
3. Se lee el mensaje.
4. Se elimina el mensaje.
5. Se registra evidencia.

La cola no tiene consumidor de negocio en Semana 1 y su contrato definitivo queda abierto.

## FM-S1-004 — Reconstruir infraestructura

1. Ejecutar `destroy-week1.sh`.
2. Confirmar eliminación del Resource Group de práctica.
3. Ejecutar `deploy-week1.sh` con los parámetros requeridos.
4. Verificar red, Storage, App Service, slot, identidades y configuración.

## FM-S1-005 — Demostrar alta disponibilidad

1. Mantener una instancia durante el desarrollo.
2. Escalar temporalmente a dos instancias.
3. Ejecutar solicitudes continuas contra la API.
4. Reiniciar o retirar una de las instancias durante la demostración.
5. Confirmar que la API continúa respondiendo y que las transacciones aceptadas están almacenadas.
6. Regresar a una instancia.
