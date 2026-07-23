# ADR-001: Arquitectura Hexagonal

> **Fuente canónica:** este es el ADR resumido de Semana 1. El registro de decisiones detallado y vivo (ADR-001…006, con contexto, alternativas y consecuencias) es [`docs/2_Arquitectura/2_ADR_Decisiones_Arquitectura.md`](../2_Arquitectura/2_ADR_Decisiones_Arquitectura.md). Ante cualquier discrepancia, ese documento prevalece.

## Contexto

Necesidad de separar la lógica de negocio de los mecanismos de entrada/salida para facilitar pruebas, mantenimiento y evolución del sistema.

## Decisión

Implementar arquitectura hexagonal (Ports & Adapters) en el código Java:

- **Dominio (Core)**: Entidades y lógica de negocio pura
- **Puertos (Ports)**: Interfaces que definen cómo la aplicación se comunica con el exterior
- **Adaptadores (Adapters)**: Implementaciones concretas de los puertos

## Justificación

1. **Testabilidad**: Permite probar lógica de negocio sin infraestructura real
2. **Flexibilidad**: Cambiar un adaptador (ej. Storage) sin afectar dominio
3. **Claridad**: Separa responsabilidades explícitamente
4. **Evolución**: Facilita agregar nuevos puertos (Queue, BD) en Semana 2

## Implementación Actual (Semana 1)

```
┌─────────────────────────────────────────────────┐
│                  APPLICATION                     │
│  ┌─────────────────────────────────────────┐    │
│  │              DOMAIN (Core)               │    │
│  │  ┌──────────┐  ┌──────────────────┐    │    │
│  │  │Entities  │  │    Services      │    │    │
│  │  └──────────┘  └──────────────────┘    │    │
│  └─────────────────────────────────────────┘    │
│  ┌───────────────┐  ┌────────────────────┐    │
│  │    Ports      │  │      Ports          │    │
│  │ (Inbound)     │  │     (Outbound)      │    │
│  │ REST API      │  │  Storage Repository │    │
│  └───────┬───────┘  └──────────┬───────────┘    │
└──────────┼────────────────────┼─────────────────┘
           │                    │
           ▼                    ▼
┌──────────────────┐  ┌──────────────────┐
│ REST Controller  │  │  Blob Adapter     │
│ (Adapter In)     │  │  (Adapter Out)   │
└──────────────────┘  └──────────────────┘
```

## Estado

**Aceptada** - Implementada parcialmente en Semana 1.

## Consecuencias

- Requiere disciplina en no mezclar capas
- Los adaptadores de Queue/DB serán necesarios en Semana 2

## Revisado

- [x] Entendido por el equipo
- [x] Consistente con objetivos de mantenibilidad
