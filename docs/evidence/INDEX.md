# Índice de Evidencias - Semana 1

Este índice documenta todas las evidencias generadas durante Semana 1, con referencias a commits, ambientes y rutas de archivos.

## Notas Importantes

⚠️ **SANITIZACIÓN**: Todos los IDs sensibles han sido reemplazados con marcadores como `<subscription-id>`, `<resource-id>`, `<tenant-id>`.

⚠️ **SECRETS**: No se incluyen credenciales reales. Usar `.env` local para valores sensibles.

---

## Evidencia por Issue

### ISS-S1-001: Código Base
| Fecha | Commit | Run | Descripción | Ruta |
|-------|--------|-----|-------------|------|
| 2026-07-20 | 9bd51be | - | Código inicial Java/Spring | `src/` |
| 2026-07-20 | - | - | Tree de dependencias | `docs/evidence/iss-s1-001/` |

### ISS-S1-002: Validación de Código
| Fecha | Commit | Run | Descripción | Ruta |
|-------|--------|-----|-------------|------|
| 2026-07-20 | 9bd51be | run-01 | ShellCheck limpio | `docs/evidence/iss-s1-002/` |
| 2026-07-20 | 9bd51be | run-01 | Validación sin recursos | `docs/evidence/iss-s1-002/` |

### ISS-S1-003: Provisionamiento Storage
| Fecha | Commit | Run | Descripción | Ruta |
|-------|--------|-----|-------------|------|
| 2026-07-20 | 9bd51be | run-01 | Provisionamiento exitoso | `docs/evidence/iss-s1-003/` |
| 2026-07-20 | 9bd51be | run-01 | Recursos finales Azure | `docs/evidence/iss-s1-003/08-azure-resources-final.txt` |

### ISS-S1-004: App Service
| Fecha | Commit | Run | Descripción | Ruta |
|-------|--------|-----|-------------|------|
| 2026-07-20 | 9bd51be | run-01 | Provisionamiento | `docs/evidence/iss-s1-004/` |
| 2026-07-20 | 9bd51be | run-01 | Validación SKU | `docs/evidence/iss-s1-004/02-sku-validation.txt` |

### ISS-S1-005: Private Endpoints
| Fecha | Commit | Run | Descripción | Ruta |
|-------|--------|-----|-------------|------|
| 2026-07-20 | 9bd51be | run-01 | Configuración endpoints | `docs/evidence/iss-s1-005/` |
| 2026-07-20 | 9bd51be | run-01 | Validación red | `docs/evidence/iss-s1-005/04-validate-network.txt` |

### ISS-S1-006: RBAC y Entra
| Fecha | Commit | Run | Descripción | Ruta |
|-------|--------|-----|-------------|------|
| 2026-07-20 | 9bd51be | run-01 | Roles asignados | `docs/evidence/iss-s1-006/` |
| 2026-07-20 | 9bd51be | run-01 | Validación RBAC | `docs/evidence/iss-s1-006/04-validate-rbac.txt` |

### ISS-S1-007: Pruebas E2E
| Fecha | Commit | Run | Descripción | Ruta |
|-------|--------|-----|-------------|------|
| 2026-07-20 | 9bd51be | run-01 | Suite completa | `docs/evidence/iss-s1-007/runs/` |
| 2026-07-20 | 9bd51be | run-01 | Resultados OpenAPI lint | `docs/evidence/iss-s1-007/03-openapi-lint.txt` |

### ISS-S1-008: Documentación HA
| Fecha | Commit | Run | Descripción | Ruta |
|-------|--------|-----|-------------|------|
| 2026-07-20 | 9bd51be | run-01 | Scripts HA | `docs/evidence/iss-s1-008/runs/` |

### HA (Alta Disponibilidad)
| Fecha | Commit | Run | Descripción | Ruta |
|-------|--------|-----|-------------|------|
| - | - | - | Script de prueba HA | `docs/evidence/ha/` |

### Queue
| Fecha | Commit | Run | Descripción | Ruta |
|-------|--------|-----|-------------|------|
| - | - | - | Validación queue | `docs/evidence/queue/` |

---

## Comandos para Generar Evidencia

```bash
# Generar evidencia de issue específica
cd docs/evidence/iss-s1-003/
../capture-evidence.sh

# Generar toda la evidencia
find docs/evidence -name "capture-evidence.sh" -exec {} \;
```

---

## Estructura de Evidencia

```
docs/evidence/
├── INDEX.md                    # Este archivo
├── ha/                         # Alta disponibilidad
├── identity/                   # Managed identity
├── iss-s1-001/                 # Issue específica
│   ├── 01-*.txt               # Capturas numbered
│   ├── 02-*.txt
│   └── README.md              # Metadata
├── iss-s1-002/
├── ... (más issues)
├── queue/                      # Validación queue
└── examples/                  # Templates de evidencia
```

---

## Criterios de Calidad de Evidencia

- [x] Sin secrets reales
- [x] IDs sensibles sanitizados
- [x] Timestamps en formato ISO 8601
- [x] Commits referenciados
- [x] Descripción clara del contenido
- [x] Rutas relativas al repo

---

## Actualización del Índice

Este índice debe actualizarse cada vez que se genere nueva evidencia:

1. Agregar entrada con fecha, commit, run
2. Verificar sanitización de IDs
3. Confirmar que la evidencia es reproducible
4. Hacer commit del cambio

---

## Referencias

- [Matriz de Trazabilidad](../5_Issues_y_Trazabilidad/2_Matriz_Trazabilidad.md)
- [README Principal](../../README.md)
- [Arquitectura](../2_Arquitectura/centinela-week1.md)
