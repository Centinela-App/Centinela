# 19 - Plantilla Completa de Feature, Historia de Usuario e Issue Técnica

## Objetivo

Estandarizar la creación del backlog con la jerarquía correcta y entregar a una persona o IA una unidad de trabajo implementable sin ambigüedad.

# 1. Jerarquía

```text
Épica de producto
  └── Feature
        └── Historia de usuario
              └── Issue técnica, solo si la historia necesita dividirse
```

No se crean épicas por módulo, tecnología, integrante o semana.

# 2. Plantilla de Feature

## FEAT-XXX - Título

- **Épica:** EPIC-XXX
- **Objetivo de negocio:**
- **Resultado demostrable:**
- **Actores beneficiados:**
- **Flujos relacionados:**
- **Requisitos relacionados:**
- **Fuera de alcance:**
- **Métrica o evidencia de éxito:**
- **Historias que la componen:**

# 3. Plantilla de Historia de Usuario

## HU-XXX - Título

**Como** [actor]  
**Quiero** [capacidad]  
**Para** [valor]

- **Feature:** FEAT-XXX
- **Flujo:** FM/FT-XXX
- **Requisitos:** RF/RNF/RS/RA-XXX
- **Precondiciones:**
- **Reglas de negocio:**
- **Criterios de aceptación de la historia:**
- **Escenarios Gherkin de alto nivel:**
- **Necesita dividirse:** Sí/No
- **Issues derivadas:**

# 4. Plantilla de Issue Técnica Completa

## ISS-XXX - Título

### Metadatos

- **Historia:** HU-XXX
- **Feature:** FEAT-XXX
- **Responsable:**
- **Revisor:**
- **Dependencias para iniciar:**
- **Estimación:**
- **Flujo:**
- **Requisitos:**
- **Pruebas catalogadas:** TEST-XXX

### 1. Objetivo

Resultado único y verificable.

### 2. Contexto y razón técnica

Por qué existe, qué riesgo reduce y con qué contratos debe coincidir.

### 3. Descripción técnica

- Componentes que deben implementarse.
- Puertos, adaptadores, DTOs, recursos o scripts involucrados.
- Algoritmo o secuencia esperada.
- Manejo de errores.
- Seguridad y observabilidad.

### 4. Fuera de alcance

- Cambios prohibidos.
- Módulos que no deben tocarse.
- Funcionalidad futura excluida.

### 5. Archivos que deben crearse

```text
src/main/...
src/test/...
scripts/...
```

### 6. Archivos que pueden modificarse

```text
Pendiente.
```

### 7. Archivos prohibidos

```text
Pendiente.
```

### 8. Criterios de aceptación

```text
[ ] Observables y medibles.
[ ] Relacionados con requisitos y flujo.
[ ] Incluyen casos felices, alternos y errores.
```


### 9. Casos de prueba asociados

| ID | Momento | Nivel | Categoría | Archivo de prueba | Resultado esperado |
|---|---|---|---|---|---|
| TEST-XXX | Obligatoria para cerrar / Posterior de integración | Estático/Unitario/Contrato/Integración/E2E | Seguridad/API/etc. | `src/test/...` | Pendiente |

Las pruebas posteriores no pueden generar una dependencia hacia una issue con número mayor; bloquean el cierre de la Semana, no el cierre temprano de la issue.

### 10. Escenarios Gherkin

```gherkin
Escenario: Caso feliz
  Dado ...
  Cuando ...
  Entonces ...

Escenario: Validación o caso borde
  Dado ...
  Cuando ...
  Entonces ...

Escenario: Error o dependencia no disponible
  Dado ...
  Cuando ...
  Entonces ...
```

### 11. Definition of Done específica

```text
[ ] Criterios cumplidos.
[ ] Archivos creados/modificados dentro del alcance.
[ ] Pruebas catalogadas ejecutadas.
[ ] Evidencia enlazada.
[ ] Contratos y documentación actualizados.
[ ] Seguridad y logs revisados.
[ ] Sin secretos ni datos sensibles.
[ ] Revisión cruzada aprobada.
```

### 12. Comandos de validación

```bash
mvn test
mvn verify
# comandos adicionales concretos
```

### 13. Evidencia esperada

- Pull request.
- Reporte de pruebas.
- Respuesta HTTP, log seguro o evidencia Azure.
- Captura o salida sanitizada.

### 14. Instrucción para IA

Antes de implementar debe resumir objetivo, archivos, pruebas, riesgos y fuera de alcance. Después debe listar cambios, pruebas realmente ejecutadas, evidencia, pendientes y cualquier desviación.

# 5. Regla para dividir una issue

Dividir nuevamente cuando tenga más de una responsabilidad principal, toque varios módulos sin necesidad, requiera decisiones no aprobadas, mezcle infraestructura y negocio de manera no verificable o no pueda completarse/revisarse en aproximadamente un día.
