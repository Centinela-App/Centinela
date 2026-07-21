# Evidencias de ISS-S1-009

Esta carpeta conserva evidencia reproducible y sanitizada de la carga tecnica
de documentos.

## Pruebas disponibles en esta issue

- `TEST-S1-018`: validacion, archivo no vacio y normalizacion del nombre.
- Integracion HTTP local: `VerificationDocumentApiIT` con puerto Blob simulado.
- Contrato OpenAPI: `VerificationDocumentOpenApiContractTest`.
- Integracion directa con Azure: `AzureVerificationDocumentBlobAdapterIT`.

La integracion directa demuestra escritura, lectura y limpieza en el contenedor
real, pero **no reemplaza TEST-S1-019**. Ese E2E exige API staging desplegada y
un token `ANALYST`, por lo que queda bloqueado por `ISS-S1-011`.

Tambien permanecen posteriores:

- `TEST-S1-022`: autorizacion HTTP exclusiva del Analista, bloqueada por ISS-S1-011.
- `TEST-S1-023`: aislamiento funcional staging/production, cierre integrado.

## Captura

Desde Git Bash, con Azure CLI autenticado y conectividad al Storage:

```bash
export CENTINELA_RUN_AZURE_DOCUMENT_IT=true
export CENTINELA_STORAGE_ACCOUNT='<storage-account>'
export CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER='verification-documents-staging'

bash docs/evidence/iss-s1-009/capture-evidence.sh
```

El script falla si la prueba real de Azure fue omitida. Los archivos generados
no contienen tokens, claves, connection strings ni contenido personal real.
