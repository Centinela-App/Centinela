# Evidencia ISS-S2-014

Esta carpeta contiene el cierre verificable de Semana 2.

Una corrida real crea `run-closeout-<UTC>/` con:

- `metadata.json`: commit, rama, periodo y modo solicitado;
- `resources-before.json`: inventario sanitizado previo;
- `resources-summary.json`: resumen por nombre, tipo y region;
- `rbac-before.json`: asignaciones RBAC sanitizadas;
- `cost-query.json`: respuesta de Cost Management;
- `cost-summary.json`: costos agrupados por servicio y moneda;
- `checksums.sha256`: integridad de los archivos JSON;
- `summary.json`: resultado final;
- `resource-group-exists-after.txt`: solo en cierre destructivo exitoso.

El modo predeterminado no elimina recursos. El cierre destructivo requiere
simultaneamente `--destroy --yes` y solo debe ejecutarse cuando las evidencias
reales de ISS-S2-012 e ISS-S2-013 ya hayan sido aprobadas.

Cost Management puede presentar retraso de varias horas. El reporte refleja los
datos disponibles para el periodo solicitado al momento de ejecutar la prueba.
