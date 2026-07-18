# Evidencia ISS-S1-007

Esta carpeta conserva evidencia reproducible y sanitizada del contrato HTTP de transaccion.
Los ejemplos usan identificadores ficticios y no contienen secretos ni datos personales reales.

## Generar evidencia

Desde Git Bash, WSL o Azure Cloud Shell, en la raiz del repositorio:

```bash
bash docs/evidence/iss-s1-007/capture-evidence.sh
```

El script debe generar:

- `01-required-tests.txt`: las cuatro pruebas obligatorias de la issue.
- `02-full-test-suite.txt`: suite completa, incluida la arquitectura.
- `03-openapi-lint.txt`: validacion de Redocly.
- `04-diff-check.txt`: comprobacion de espacios y conflictos del diff.
- `05-files-reviewed.txt`: commit base y archivos pendientes de revision.

Los archivos generados solo se deben versionar cuando los comandos terminen correctamente.
Si un comando falla, la issue no puede declararse `DONE`.

## Alcance demostrado

- El `202` de `examples/202-response.json` es una respuesta contractual obtenida en la prueba aislada del controller con `IngestTransactionUseCase` simulado.
- La confirmacion de escritura real en Blob y el `202` integrado pertenecen a `ISS-S1-008`.
- `examples/400-response.json` demuestra el formato publico y sanitizado de validacion.
- La revision cruzada sigue siendo una aprobacion humana y debe registrarse en el Pull Request.
