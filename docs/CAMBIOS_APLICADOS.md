# Cambios aplicados en la reorganización

Esta carpeta (`Centinela_Documentacion/`) es la documentación principal reorganizada temáticamente y es ahora la **única** copia de la documentación. Los archivos originales sueltos (`Azure-Semana1.md`, `Centinela.md`, `CHECKPOINT_CENTINELA.md`, `REPORTE_VALIDACION_FINAL.md`, la carpeta `Kit_Documentacion_Backend_Centinela_Semana1/` y su `.zip`) **fueron eliminados** tras verificar que su contenido quedó íntegro aquí.

Ningún contenido se perdió: los 26 documentos fueron reubicados y renombrados con nombres claros, sus referencias internas se actualizaron a las nuevas rutas, y se aplicaron las correcciones de la revisión de consistencia.

## Correcciones de contenido

| ID | Severidad | Qué se corrigió | Dónde |
|---|---|---|---|
| **I-1** | 🔴 Alta | Se añadió la **clasificación IaaS/PaaS/SaaS** de cada componente (entregable obligatorio del enunciado que faltaba por completo). | `2_Arquitectura/1_Arquitectura_Backend.md` (resumen) y `2_Arquitectura/2_ADR_Decisiones_Arquitectura.md` (ADR-001, detallado) |
| **I-2** | 🔴 Alta | Se creó el **diagrama de red con reglas de tráfico (NSG)**, que el enunciado exige y no estaba documentado. | `2_Arquitectura/3_Diagrama_Red.md` (nuevo) |
| **I-3** | 🔴 Media | Se **unificó el prefijo `/api/v1`** en las rutas de la configuración de seguridad (antes `/transactions` y `/verification-documents` sin prefijo en 3 líneas). | `5_Issues_y_Trazabilidad/1_Historias_Issues.md` |
| **I-4** | 🟠 Media | Se documentó el **trade-off explícito de alta disponibilidad** (1 instancia normal vs. 2 solo en la demo → no hay HA real 24/7). | `2_Arquitectura/2_ADR_Decisiones_Arquitectura.md` (ADR-004) |
| **I-5** | 🟠 Menor | Se corrigió la evidencia de `ISS-S1-007`: el `202` real pertenece a `ISS-S1-008`; la issue de contrato produce el recibo con puerto simulado, no un 202 de persistencia. | `5_Issues_y_Trazabilidad/1_Historias_Issues.md` |
| **I-6** | 🟠 Menor | El **orden de lectura ahora incluye el contrato de la transacción y la guía maestra** (el índice del kit los omitía). | `README.md` |
| **I-7** | 🟠 Menor | Se corrigió el **defecto de formato Markdown** `### Resultado esperado` pegado a la línea anterior en los **28 casos** de prueba. | `6_Testing/1_Testing_Backend.md` |
| **I-8** | 🟠 Menor | Se añadió la **ruta del endpoint** `POST /api/v1/verification-documents` en el flujo de carga documental (antes sin ruta). | `2_Arquitectura/4_Flujos_y_Casos_Uso.md` |
| **Nota** | 🟡 Info | Se documentó que `currency` obligatorio y `merchant.name` + `merchant.category` son **endurecimientos deliberados** del contrato sobre el mínimo del enunciado. | `1_Requisitos_y_Contrato/2_Contrato_Transaccion.md` |

## Documentos nuevos creados

- `README.md` — índice maestro y punto de entrada.
- `CAMBIOS_APLICADOS.md` — este registro.
- `2_Arquitectura/2_ADR_Decisiones_Arquitectura.md` — documento vivo de decisiones (entregable 7).
- `2_Arquitectura/3_Diagrama_Red.md` — diagrama de red y reglas NSG (entregable 3).
- `3_Seguridad/2_Matriz_Roles_Permisos.md` — matriz de roles y permisos consolidada (entregable 2).

## Lo que NO se tocó (por diseño)

- El texto del **enunciado** (`0_Vision/2_Alcance_Semana1.md`) y la **visión** (`0_Vision/1_Vision_Producto.md`) se conservan como fuentes autoritativas sin modificación.
- No se agregó nada de alcance de Semana 2 (scoring, reglas, umbral, casos, IA, consumidor de cola, bases de datos).
