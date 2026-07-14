# Diagrama de red — Semana 1

Entregable obligatorio del enunciado (entregable 3): **qué subredes hay, qué vive en cada una, y qué reglas controlan el tráfico entre ellas**. El requisito no negociable que este diseño satisface: **los almacenes de datos no son alcanzables desde internet**; solo la subred de la aplicación llega a ellos.

## Topología

```text
                          INTERNET
                             |
                             |  HTTPS (443) entrante
                             v
                   +---------------------+
                   |   Azure App Service |   (PaaS, con balanceador propio)
                   |   Web App + slot     |
                   |   Managed Identity   |
                   +----------+----------+
                              |  Integración VNet (salida)
                              v
        VNet: vnet-centinela  (ej. 10.10.0.0/16)
        +---------------------------------------------------------------+
        |                                                               |
        |   snet-app-integration          snet-private-endpoints        |
        |   (ej. 10.10.1.0/24)            (ej. 10.10.2.0/24)            |
        |   - Delegada a App Service      - Private Endpoint Blob        |
        |     (integración de salida)     - Private Endpoint Queue       |
        |          |                            ^                        |
        |          |   tráfico privado          |                        |
        |          +----------------------------+                        |
        |                    (resuelto por zonas DNS privadas)           |
        +---------------------------------------------------------------+
                              |
                              v
                   +---------------------+
                   |   Storage Account   |   publicNetworkAccess = Disabled
                   |   Blob + Queue      |   (NO alcanzable desde internet)
                   +---------------------+
```

> Los rangos (`10.10.x.x`) son ilustrativos; el CIDR real es un parámetro del script de despliegue.

## Qué vive en cada subred

| Subred | Contenido | Propósito |
|---|---|---|
| `snet-app-integration` | Integración VNet de salida del App Service (subred delegada) | Es la única ruta desde la que la aplicación alcanza el Storage por IP privada. |
| `snet-private-endpoints` | Private Endpoint de **Blob** y Private Endpoint de **Queue** | Expone el Storage como IP privada dentro de la VNet. Resuelto por zonas DNS privadas. |

El **Storage Account** no está "dentro" de una subred: se proyecta en `snet-private-endpoints` mediante sus Private Endpoints, y su acceso público está deshabilitado.

## Reglas de tráfico (NSG)

Cada subred lleva un Network Security Group. Reglas mínimas de Semana 1 (además de las reglas por defecto de Azure):

### NSG de `snet-app-integration`

| # | Dirección | Origen | Destino | Puerto | Protocolo | Acción | Justificación |
|---|---|---|---|---|---|---|---|
| 100 | Entrada | Internet | App Service | 443 | TCP | Permitir | Recibir transacciones y cargas documentales por HTTPS. |
| 110 | Entrada | Internet | Cualquiera | 80 | TCP | Denegar | No se sirve HTTP sin cifrar. |
| 200 | Salida | snet-app-integration | `snet-private-endpoints` (Storage) | 443 | TCP | Permitir | Persistir Blob y validar Queue por canal privado. |
| 210 | Salida | snet-app-integration | Internet (Storage público) | Cualquiera | TCP | Denegar | Forzar que el Storage se alcance solo por Private Endpoint. |
| 4096 | Ambas | — | — | — | — | Denegar (default) | Todo lo no permitido explícitamente se deniega. |

### NSG de `snet-private-endpoints`

| # | Dirección | Origen | Destino | Puerto | Protocolo | Acción | Justificación |
|---|---|---|---|---|---|---|---|
| 100 | Entrada | `snet-app-integration` | Private Endpoints | 443 | TCP | Permitir | Solo la subred de la app puede llegar a los almacenes. |
| 110 | Entrada | Internet | Private Endpoints | Cualquiera | Cualquiera | Denegar | Los almacenes no son alcanzables desde internet (requisito no negociable). |
| 120 | Entrada | Otras subredes | Private Endpoints | Cualquiera | Cualquiera | Denegar | Ninguna otra subred (ni futuras) accede sin autorización explícita. |
| 4096 | Ambas | — | — | — | — | Denegar (default) | Cierre por defecto. |

## Preparación para Semana 2

`snet-private-endpoints` queda listo para alojar los Private Endpoints de las bases de datos que llegan en Semana 2 (historial de transacciones y casos), bajo la **misma restricción**: alcanzables solo desde `snet-app-integration` (y, cuando exista, desde la subred del cómputo serverless de scoring, que se autorizará con una regla equivalente a la #100). No se abre acceso público en ningún momento.
