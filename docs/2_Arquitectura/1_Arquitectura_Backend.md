# 04 — Arquitectura backend

## Vista de Semana 1

```text
Sistema originador
      |
      v
Azure App Service
      |
      v
Controller -> Input Port -> Use Case -> Blob Port -> Azure Blob Storage

Analista/Admin
      |
      v
Document Controller -> Input Port -> Use Case -> Document Blob Port
```

Queue Storage existe como buffer preparado y validado, pero no se conecta todavía al flujo de negocio.

## Estructura interna

```text
com.centinela
  transactioningestion
    domain
    application
      port.in
      port.out
      service
    infrastructure
      web
      azure
  documentstorage
    domain
    application
    infrastructure
  identityaccess
  shared
```

## Reglas hexagonales

- Controller depende de un puerto de entrada, no de SDK de Azure.
- Casos de uso dependen de puertos de salida.
- Adaptadores implementan Azure Blob Storage.
- DTO, dominio y objetos del SDK se mantienen separados.

## Clasificación por modelo de servicio en la nube

Entregable obligatorio del enunciado (decisión de arquitectura). Cada componente se clasifica según el **modelo de servicio** que representa y por qué. El detalle y la justificación ampliada están en `2_Arquitectura/2_ADR_Decisiones_Arquitectura.md`.

| Componente | Modelo | Por qué |
|---|---|---|
| **Azure App Service (Web App + slot)** | **PaaS** | Azure gestiona SO, runtime y parches; la célula solo despliega el artefacto Java. Da balanceo y escalado horizontal sin administrar VMs. |
| **Azure Blob Storage** | **PaaS / Almacenamiento gestionado** | Servicio de objetos administrado; no se gestiona infraestructura subyacente. Se consume por SDK con Managed Identity. |
| **Azure Queue Storage** | **PaaS / Mensajería gestionada** | Cola administrada; misma cuenta de almacenamiento. Buffer preparado, sin consumidor en Semana 1. |
| **Microsoft Entra ID** | **SaaS / Identidad gestionada** | Directorio y emisión de tokens como servicio; no se opera infraestructura de identidad. |
| **Managed Identity** | **PaaS (capacidad de identidad)** | Identidad administrada por la plataforma para acceder a datos sin secretos. |
| **VNet, Subredes, Private Endpoints, DNS privado** | **IaaS (capa de red)** | Recursos de red definidos y controlados por la célula (rangos, subredes, reglas). Es la porción de infraestructura que sí se administra. |

> En Semana 1 **no hay IaaS de cómputo** (ninguna VM ni Kubernetes): el cómputo es PaaS (App Service). El único IaaS es la red. Esta elección es deliberada por costo y por menor superficie de administración.

## Red mínima

```text
Internet -> App Service
               |
               | VNet Integration
               v
        snet-app-integration
               |
               v
      Private DNS + Private Endpoint
               |
               v
          Storage Account

snet-private-endpoints contiene los Private Endpoints.
```

El diagrama de red completo, con las subredes, qué vive en cada una y las **reglas de tráfico (NSG)** que controlan el flujo entre ellas, está en `2_Arquitectura/3_Diagrama_Red.md`.

## Preparación para Semana 2

Se deja un punto de extensión en la capa de aplicación para introducir mensajería posteriormente. No se define todavía:

- nombre ni esquema final del evento;
- consumidor;
- servicio serverless;
- base histórica;
- base de casos.

Esto evita acoplar la Semana 1 a decisiones aún no entregadas.
