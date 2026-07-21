# ADR-003: Private Storage

## Contexto

Requerimiento de que el Storage Account no tenga puntos de acceso públicos. Toda comunicación debe fluir dentro de la VNet privada.

## Decisión

Usar Azure Private Endpoints para Storage Account, deshabilitando todo acceso público.

## Justificación

1. **Seguridad**: El tráfico nunca sale de la red de Azure
2. **Compliance**: Cumple requisitos de datos financieros sensibles
3. **Aislamiento**: No hay exposición a internet
4. **Integración**: Works seamlessly con Private DNS Zone

## Arquitectura

```
┌──────────────────────────────────────────────────────┐
│                    VNet Privada                        │
│                                                      │
│  ┌──────────────┐      Private Endpoint              │
│  │  App Service  │◄──────────────────────────────────►│
│  └──────────────┘         (10.0.1.4)                  │
│                              │                        │
│                              │ Private DNS Zone       │
│                              ▼                        │
│                      ┌──────────────────┐             │
│                      │ Storage Account  │             │
│                      │ (mystorage.blob) │             │
│                      │  network.acls    │             │
│                      │  = deny all      │             │
│                      └──────────────────┘             │
└──────────────────────────────────────────────────────┘
```

## Configuración

```bash
# Storage Account: Disable public access
az storage account update \
  --name <storage> \
  --resource-group <rg> \
  --default-action Deny \
  --public-network-access Disabled

# Crear Private Endpoint
az network private-endpoint create \
  --name <pe-name> \
  --resource-group <rg> \
  --vnet-name <vnet> \
  --subnet <subnet> \
  --private-connection-resource-id <storage-id> \
  --connection-name <conn> \
  --group-id blob
```

## Estado

**Aceptada** - Implementada en ISS-S1-005.

## Compromisos

- DevTools no puede acceder Storage directamente
- Requiere VPN o Bastion para debugging

## Revisado

- [x] Aprobado por equipo de seguridad
- [x] Consistente con arquitectura zero-trust
