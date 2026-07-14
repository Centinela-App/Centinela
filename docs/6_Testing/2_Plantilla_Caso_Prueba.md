# 20 — Plantilla de caso de prueba backend completo

## Cuándo usarla

Usar esta plantilla para cada `TEST-*`. No mezclar nivel y categoría en un único campo.

## Identificación

- **ID:** `TEST-SX-000`
- **Nombre:**
- **Nivel:** Estático | Unitario | Contrato | Integración | E2E
- **Categoría:** Arquitectura | Validación | API | Seguridad/RBAC | Infraestructura | Red | Almacenamiento | Queue | Configuración | Disponibilidad | Documentación | Alcance
- **Prioridad:** Crítica | Alta | Media | Baja
- **Ambiente:** Local | CI | Azure integrado | Staging | Producción controlada
- **Requisitos:**
- **Flujo:**
- **Issue(s):**

## Propósito

Riesgo o comportamiento exacto que verifica.

## Precondiciones

- Estado del sistema.
- Identidad requerida.
- Recursos/configuración.

## Datos de prueba

- Fixtures y valores límite.
- Identificadores únicos.
- Prohibición de PII real.

## Dobles y dependencias

- Mocks/fakes para unitarios.
- Recursos reales para integración/E2E cuando corresponda.
- Servicios o scripts requeridos.

## Pasos

1.
2.
3.

## Resultado esperado

- HTTP/resultado.
- Persistencia o recursos.
- Logs/evidencia.
- Efectos que NO deben ocurrir.

## Escenarios Gherkin

```gherkin
Escenario: Camino feliz
  Dado ...
  Cuando ...
  Entonces ...

Escenario: Camino alterno o borde
  Dado ...
  Cuando ...
  Entonces ...

Escenario: Camino de error
  Dado ...
  Cuando ...
  Entonces ...
```

## Automatización

- **Archivo:**
- **Método/escenario:**
- **Comando aislado:**
- **Suite:**

## Evidencia

- **Ruta:**
- **Identificación mínima:** commit, ambiente, runId y timestamp.
- **Contenido sanitizado:**

## Limpieza

Cómo eliminar datos, mensajes o recursos temporales sin afectar otros casos.

## Definition of Done

- [ ] Ejecutado en el nivel y ambiente declarados.
- [ ] Caminos feliz, alterno y de error verificados.
- [ ] Evidencia guardada.
- [ ] Limpieza completada.
- [ ] Trazabilidad actualizada.
- [ ] Sin secretos ni PII.
- [ ] Revisión cruzada aprobada.
