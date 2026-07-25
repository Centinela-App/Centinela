# Evidencia de integración ISS-S2-001 a ISS-S2-011

Esta carpeta no contiene salidas simuladas. Cada validación real debe crear un directorio `run-<UTC>` con:

- `maven-root.txt`
- `maven-scoring-function.txt`
- `static-validation.txt`
- `secret-scan.txt`
- `azure-resources.json`
- `rbac.json`
- `cosmos-private-endpoint.json`
- `function-host-storage-private-endpoints.json`
- `postgres-managed-identities.txt`
- `function-settings-sanitized.json`
- `queue-delete-test.txt`

La prueba completa API → score → caso pertenece a `ISS-S2-012` y no debe guardarse como evidencia de esta corrección.
