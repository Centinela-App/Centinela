# 10 — Despliegue de Semana 1

## Principio

La infraestructura se crea con Bash y Azure CLI. GitHub Actions no es un requisito de Semana 1.

## Parámetros mínimos

```bash
SUBSCRIPTION_ID=
LOCATION=
RESOURCE_GROUP=
NAME_PREFIX=
APP_SERVICE_SKU=
```

`LOCATION` y `APP_SERVICE_SKU` no están fijados en la documentación. El SKU elegido debe soportar deployment slots y escala horizontal.

## Recursos mínimos

- Un Resource Group.
- Una VNet.
- `snet-app-integration`.
- `snet-private-endpoints`.
- Un Storage Account.
- Cuatro contenedores: raw y documentos, separados por staging/production.
- Dos colas, separadas por staging/production.
- Un App Service Plan.
- Una Web App.
- Slot `staging`.
- Managed Identity para producción y staging.
- Private Endpoints y zonas DNS privadas necesarias para Blob y Queue.

No se crean runners, máquinas virtuales, API Management, Application Gateway, Front Door, Kubernetes ni infraestructuras duplicadas por integrante.

## Scripts

```text
scripts/
  deploy-week1.sh
  destroy-week1.sh
  validate-week1.sh
  validate-queue.sh
  test-ha.sh
```

## Orden de despliegue

1. Seleccionar suscripción y validar parámetros.
2. Crear Resource Group y presupuesto/alerta si la suscripción lo permite.
3. Crear VNet y subredes.
4. Crear Storage y recursos lógicos.
5. Crear App Service Plan, Web App y slot.
6. Activar Managed Identity.
7. Configurar Private Endpoints y DNS.
8. Aplicar RBAC mínimo.
9. Desplegar la aplicación.
10. Ejecutar validaciones.

## Control de costos

- Una instancia durante el trabajo normal.
- Dos instancias únicamente durante la prueba HA.
- Volver a una instancia inmediatamente después.
- Un solo entorno integrado para cinco personas.
- Ejecutar `destroy-week1.sh` al terminar la práctica o demostración.
