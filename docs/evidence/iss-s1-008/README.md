# Evidencia reproducible — ISS-S1-008

Esta carpeta contiene el procedimiento de evidencia de la persistencia cruda de
transacciones. No contiene tokens, connection strings, claves ni datos reales.

## Qué debe demostrarse antes de cerrar

1. `IngestTransactionServiceTest` pasa localmente.
2. `TransactionApiIT` y `TransactionApiValidationIT` pasan localmente.
3. `AzureRawTransactionBlobAdapterIT` ejecuta la escritura real, valida ruta y
   contenido, y elimina el Blob sintético.
4. La suite completa y el control de arquitectura pasan.
5. Una persona distinta revisa el Pull Request.

La prueba Azure no se considera aprobada cuando aparece como `SKIPPED`. Debe
ejecutarse con `CENTINELA_RUN_AZURE_IT=true` desde un entorno con acceso de red
al Private Endpoint y una identidad aceptada por `DefaultAzureCredential`.

## Variables no secretas

```bash
export CENTINELA_RUN_AZURE_IT=true
export CENTINELA_STORAGE_ACCOUNT='<nombre-storage>'
export CENTINELA_RAW_TRANSACTIONS_CONTAINER='raw-transactions-staging'
```

La identidad se obtiene mediante Managed Identity, Azure CLI, Azure Developer
CLI u otra fuente admitida por `DefaultAzureCredential`. No se usa connection
string.

## Captura

```bash
bash docs/evidence/iss-s1-008/capture-evidence.sh
```

El script crea una carpeta por ejecución en
`docs/evidence/iss-s1-008/runs/<runId>/`. Los resultados deben revisarse antes
de agregarlos al commit.

`TEST-S1-016`, `TEST-S1-023` y `TEST-S1-024` permanecen como pruebas posteriores
de integración y no se declaran aprobadas en esta issue.
