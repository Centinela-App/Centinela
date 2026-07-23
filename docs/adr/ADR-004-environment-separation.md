# ADR-004: Separación Lógica Staging/Production

> **Fuente canónica:** este es el ADR resumido de Semana 1. El registro de decisiones detallado y vivo (ADR-001…006, con contexto, alternativas y consecuencias) es [`docs/2_Arquitectura/2_ADR_Decisiones_Arquitectura.md`](../2_Arquitectura/2_ADR_Decisiones_Arquitectura.md). Ante cualquier discrepancia, ese documento prevalece.

## Contexto

Necesidad de mantener múltiples ambientes (desarrollo, staging, producción) sin multiplicar recursos de Azure innecesariamente.

## Decisión

Implementar separación lógica mediante convenciones de nomenclatura y prefijos, no mediante recursos separados de Azure.

## Justificación

1. **Costo**: Evitar el costo de recursos duplicados en desarrollo
2. **Simplicidad**: Una sola cuenta de Storage con prefijos por ambiente
3. **Velocidad**: Despliegue rápido sin esperar aprovisionamiento
4. **Precaución**: Ambiente de staging físico requiere validación adicional

## Implementación

### Prefijos de recursos

| Ambiente    | Prefijo       | Ejemplo                    |
|-------------|---------------|----------------------------|
| Development | `dev-{user}-` | `dev-juan-centinela-api`   |
| Staging     | `stg-`        | `stg-centinela-api`        |
| Production  | (sin prefijo) | `centinela-api`            |

### Containers de Storage

```
storage-account/
├── raw-transactions-dev-juan/
├── raw-transactions-stg/
├── raw-transactions-prod/
```

### Consideraciones de Semana 2

- Staging real podría requerir slots de App Service
- Production real podría requerir Traffic Manager
- Estos decisions están ABiertos para Semana 2

## Estado

**Aceptada** - Implementada conceptualmente en prefix `NAME_PREFIX`.

## Compromisos

- Un solo App Service compartido conceptualmente
- Logs y métricas compartidas entre ambientes lógicos
- No hay aislamiento real de recursos

## Revisado

- [x] Entendido por equipo
- [x] Requiere disciplina en uso de prefijos
