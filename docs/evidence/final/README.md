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

## Estado de la prueba de cierre (ISS-S1-014)

- **Scripts:** completos (`test-clean-deploy.sh`, `test-destroy-rebuild-cleanup.sh`) y
  `deploy-week1.sh` / `destroy-week1.sh` reintegrados tras el revert del PR #26 (incluida
  la limpieza tenant-level de la App Registration de Entra en `destroy-week1.sh`).
- **Verificación local reproducible:** `01-syntax-check.txt` — `bash -n` OK en todos los
  scripts de despliegue, destrucción y validación.
- **Run final destrucción → reconstrucción → limpieza:** requiere una suscripción Azure
  activa. Genera `deployment.log`, `validation-summary.md`, `resource-inventory.json` y
  `cleanup.log` bajo `run-{timestamp}/`. No se fabrica evidencia de Azure (regla del DoD).
