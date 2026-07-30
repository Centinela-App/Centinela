# Evidencia final — Semana 1

Esta carpeta contiene las corridas de TEST-S1-026 y TEST-S1-027. Cada corrida completa
usa `docs/evidence/final/run-drc-<timestamp>-<id>/`.

## Ejecución recomendada

```bash
bash scripts/tests/test-destroy-rebuild-cleanup.sh \
  --confirm-resource-group "$RESOURCE_GROUP"
```

La confirmación explícita es obligatoria porque la prueba elimina el Resource Group al
inicio y al final. Debe usarse un RG exclusivo para el cierre, sin recursos de Semana 2
que necesiten conservarse.

## Contenido de una corrida

- `metadata.json`: commit, rama, fecha, RG sanitizado y resultado;
- `pre-destroy-inventory.json`: inventario previo cuando existía el RG;
- `destroy.log`: destrucción inicial con espera;
- `deployment.log` y `application-deploy.log`: infraestructura y aplicación;
- `maven-verify.log`: suite Maven estricta;
- `validate-*.log`: validaciones concretas de Semana 1;
- `queue-staging.log` y `queue-production.log`;
- `ha.log`;
- `temporary-rbac.log`: asignaciones temporales sanitizadas y revocación;
- `resource-inventory.json`;
- `cleanup.log`;
- `validation-summary.md`.

## Reglas de aprobación

- No se transforma un error o warning en resultado exitoso.
- La destrucción espera hasta comprobar que el RG desapareció.
- La reconstrucción despliega infraestructura **y** artefacto de aplicación.
- Entra configura issuer, audience y JWK URI en producción y staging.
- Queue pasa en ambos ambientes y elimina solamente su mensaje técnico.
- HA reconcilia todos los `202`, restaura una instancia y limpia datos sintéticos.
- Solo se revocan los roles temporales creados por la corrida.
- Sin `--keep-resources`, el cierre termina con el RG ausente.
- La App Registration también se elimina, salvo la excepción documentada
  `--keep-entra-final` cuando continúa siendo usada por una semana posterior.

La evidencia no se declara completada hasta ejecutar la corrida Azure real. No se fabrica
ni se reemplaza por salidas esperadas.
