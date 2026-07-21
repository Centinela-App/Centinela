# Evidence Final - Semana 1

Carpeta para almacenar evidencia de las pruebas de cierre de Semana 1.

## Runs de Prueba

Cada ejecución de prueba genera una carpeta con el formato `run-{timestamp}-{random-id}/`:

```
docs/evidence/final/
├── README.md                    # Este archivo
├── run-YYYYMMDDTHHMMSS-xxxx/   # Carpeta de run
│   ├── metadata.json          # Metadata del run
│   ├── deployment.log         # Log de despliegue
│   ├── validation-summary.md  # Resumen de validaciones
│   ├── resource-inventory.json # Inventario de recursos
│   └── cleanup.log           # Log de limpieza
```

## Comandos para Generar Evidencia

```bash
# TEST-S1-026: Clean Deploy
bash scripts/tests/test-clean-deploy.sh

# TEST-S1-027: Destroy -> Rebuild -> Cleanup
bash scripts/tests/test-destroy-rebuild-cleanup.sh
```

## Notas sobre Sanitización

- Todos los logs son revisados antes de commit
- Subscription IDs son enmascarados con `mask()`
- Tokens y credenciales son filtrados
- Resource names pueden incluir prefijos sensibles (revisar antes de commit)

## Actualización del Índice

Después de cada run, actualizar `docs/evidence/INDEX.md` con la referencia al run.
