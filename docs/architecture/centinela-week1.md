# Arquitectura Centinela - Semana 1

## Visión General

Centinela es un sistema de procesamiento de transacciones financieras diseñado para validar, almacenar y poner a disposición datos de transacciones en un ambiente seguro y privado.

## Contexto del Sistema

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           ENTORNO AZURE                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                         VNet (Private)                           │   │
│  │  ┌─────────────────┐                                             │   │
│  │  │   App Service   │◄──── Managed Identity                     │   │
│  │  │  (Centinela API) │                                             │   │
│  │  └────────┬────────┘                                             │   │
│  │           │ Private Endpoint                                       │   │
│  │           ▼                                                        │   │
│  │  ┌─────────────────┐                                             │   │
│  │  │  Storage Account │ ◄─── Blobs (raw-transactions)              │   │
│  │  │   (Private)      │                                             │   │
│  │  └─────────────────┘                                             │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│  ┌─────────────────┐         │         ┌─────────────────┐            │
│  │   Entra ID      │◄────────┴────────►│   DevOps/User   │            │
│  │  (Auth/RBAC)    │                   │   (Azure CLI)   │            │
│  └─────────────────┘                   └─────────────────┘            │
└─────────────────────────────────────────────────────────────────────────┘
```

## Componentes Implementados (Semana 1)

### 1. App Service (Centinela API)
- **SKU**: S1 (o configurable via `.env`)
- **Instancias**: 1 (escala elástica disponible)
- **Endpoints**:
  - `/api/v1/transactions` - Acepta transacciones y retorna 202 Accepted
- **Autenticación**: Bearer Token via Entra ID
- **Comunicación**: Private Endpoint hacia Storage

### 2. Storage Account
- **Tipo**: StorageV2 (General Purpose V2)
- **Blob Container**: `raw-transactions`
- **Acceso**: Exclusivamente via Private Endpoint
- **Redundancia**: LRS (configurable)

### 3. Virtual Network
- **Dirección**: 10.0.0.0/16 (configurable)
- **Subnets**:
  - `snet-app` - Para App Service
  - `snet-storage` - Para Private Endpoints

### 4. Entra ID (Azure Active Directory)
- **App Registration**: Centinela API
- **Roles definidos**:
  - `Centinela.Service` - Para el API token de servicio
  - `Centinela.Read` - Para lectura de datos (reservado Semana 2)

## Flujo de Datos (Semana 1)

```
Cliente ──► POST /api/v1/transactions ──► Validación ──► Blob Storage
            (Bearer Token)                    │              │
                                              ▼              ▼
                                       202 Accepted   raw-transactions/
                                                             │
                                                   {accountId}/{date}/
                                                     {transactionId}.json
```

## Lo QUE NO ESTÁ en Semana 1

- ❌ **Queue** - Desconectada del flujo de negocio
- ❌ **Base de datos** - Sin persistencia transaccional
- ❌ **Scoring** - Sin lógica de evaluación
- ❌ **Consumer/Subscriber** - Sin procesamiento asíncrono
- ❌ **Multi-región** - Una sola región
- ❌ **Slots de staging** - Una sola ranura

## Decisiones de Arquitectura Reservadas

Ver: [ADR-001: Arquitectura Hexagonal](./adr/ADR-001-hexagonal.md)  
Ver: [Decisiones Semana 2](../week2/OPEN_DECISIONS.md)

## Seguridad Implementada

1. **Managed Identity** - Sin credenciales en código
2. **Private Endpoints** - Sin exposición pública de Storage
3. **RBAC** - Roles específicos por funcionalidad
4. **TLS** - HTTPS obligatorio en todos los endpoints

## Dependencias de Semana 1

| Issue | Componente | Estado |
|-------|------------|--------|
| ISS-S1-001 | Código base Java/Spring | ✓ |
| ISS-S1-002 | Validación de código | ✓ |
| ISS-S1-003 | Provisionamiento Storage | ✓ |
| ISS-S1-004 | Provisionamiento App Service | ✓ |
| ISS-S1-005 | Endpoints privados | ✓ |
| ISS-S1-006 | RBAC y Entra App | ✓ |
| ISS-S1-007 | Pruebas E2E | ✓ |
| ISS-S1-008 | Documentación HA | ✓ |

## Siguiente Paso

Ver [Decisiones abiertas para Semana 2](../week2/OPEN_DECISIONS.md)
