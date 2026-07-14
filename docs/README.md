# Centinela — Documentación principal (Semana 1)

**Motor de detección de fraude transaccional en tiempo real sobre Azure.**
Proyecto integrador · 3 semanas · células de 5 personas · crédito compartido USD 200.

Esta carpeta es la **documentación principal y organizada** del proyecto. Reemplaza en claridad al kit original (que se conserva intacto fuera de esta carpeta). Todos los cambios y correcciones aplicados están registrados en `CAMBIOS_APLICADOS.md`.

---

## Idea general en un párrafo

Cada transacción financiera entra por una **API de ingesta** que responde de inmediato con un acuse y persiste el dato crudo — **sin analizar nada todavía**. El análisis (scoring por reglas heurísticas, apertura de casos, IA de explicabilidad y verificación) ocurre después, de forma asíncrona, y llega en Semanas 2 y 3. La **Semana 1 construye los cimientos**: infraestructura reproducible por script, identidad con menor privilegio, red privada donde los almacenes no son alcanzables desde internet, alta disponibilidad de la ingesta, la API que recibe/valida/almacena, y el almacenamiento (Blob para documentos + una cola como buffer, solo dejada lista).

---

> **Convención de rutas.** Todas las referencias entre documentos de esta carpeta se escriben **relativas a la raíz** `Centinela_Documentacion/` (por ejemplo, `2_Arquitectura/3_Diagrama_Red.md`). Las rutas que empiezan por `docs/`, `scripts/` o similares se refieren a archivos del **repositorio de código** que el equipo crea, no a documentos de esta carpeta.

## Jerarquía de fuentes (orden de autoridad)

Si dos documentos se contradicen, mandan los de arriba:

1. `0_Vision/2_Alcance_Semana1.md` — **enunciado**, alcance obligatorio de la semana.
2. `0_Vision/1_Vision_Producto.md` — objetivo global de las 3 semanas.
3. Todo lo demás — traducción técnica de esas dos fuentes.

---

## Orden de lectura recomendado

| # | Documento | Para qué |
|---|---|---|
| 1 | `0_Vision/1_Vision_Producto.md` | Entender qué es Centinela y el pipeline completo. |
| 2 | `0_Vision/2_Alcance_Semana1.md` | Qué se pide y qué se entrega esta semana (enunciado). |
| 3 | `0_Vision/3_Checkpoint_Alcance.md` | Alcance exacto: qué sí y qué no se implementa. |
| 4 | `1_Requisitos_y_Contrato/1_Requisitos.md` | Requisitos funcionales, de seguridad e infra. |
| 5 | `1_Requisitos_y_Contrato/2_Contrato_Transaccion.md` | **El contrato de la transacción** (campos, tipos, obligatoriedad). |
| 6 | `1_Requisitos_y_Contrato/3_API_OpenAPI.md` + `openapi-centinela-semana1.yaml` | Contrato ejecutable de la API. |
| 7 | `2_Arquitectura/1_Arquitectura_Backend.md` | Estructura hexagonal y clasificación IaaS/PaaS/SaaS. |
| 8 | `2_Arquitectura/2_ADR_Decisiones_Arquitectura.md` | **Decisiones justificadas** (entregable vivo). |
| 9 | `2_Arquitectura/3_Diagrama_Red.md` | Subredes, qué vive dónde y reglas de tráfico (NSG). |
| 10 | `2_Arquitectura/4_Flujos_y_Casos_Uso.md` | Flujos de ingesta, carga, cola y reconstrucción. |
| 11 | `3_Seguridad/1_Seguridad_Backend.md` + `3_Seguridad/2_Matriz_Roles_Permisos.md` | Seguridad y **matriz de roles** (entregable). |
| 12 | `4_Infraestructura_y_Despliegue/` | Despliegue por script e integraciones. |
| 13 | `5_Issues_y_Trazabilidad/` | Las 14 issues, matriz de trazabilidad y plantillas. |
| 14 | `6_Testing/` | Los 28 casos de prueba y su plantilla. |
| 15 | `7_Gestion_y_Trabajo_IA/` | Guía para trabajar con IA, reglas anti-caos y reporte de validación. |

> El orden anterior **incluye el contrato de la transacción (paso 5)** y la guía maestra, que el índice del kit original omitía.

---

## Mapa de la carpeta

```text
Centinela_Documentacion/
├── README.md                         (este índice maestro)
├── CAMBIOS_APLICADOS.md              (registro de correcciones)
├── 0_Vision/
│   ├── 1_Vision_Producto.md
│   ├── 2_Alcance_Semana1.md          (enunciado — fuente autoritativa)
│   └── 3_Checkpoint_Alcance.md
├── 1_Requisitos_y_Contrato/
│   ├── 1_Requisitos.md
│   ├── 2_Contrato_Transaccion.md     ← nota de decisión currency/merchant
│   ├── 3_API_OpenAPI.md
│   └── openapi-centinela-semana1.yaml
├── 2_Arquitectura/
│   ├── 1_Arquitectura_Backend.md     ← + clasificación IaaS/PaaS/SaaS
│   ├── 2_ADR_Decisiones_Arquitectura.md   ← NUEVO (entregable vivo)
│   ├── 3_Diagrama_Red.md             ← NUEVO (subredes + reglas NSG)
│   ├── 4_Flujos_y_Casos_Uso.md
│   └── 5_Contexto_para_IA.md
├── 3_Seguridad/
│   ├── 1_Seguridad_Backend.md
│   └── 2_Matriz_Roles_Permisos.md    ← NUEVO (entregable)
├── 4_Infraestructura_y_Despliegue/
│   ├── 1_Deployment.md
│   └── 2_Integraciones_Externas.md
├── 5_Issues_y_Trazabilidad/
│   ├── 1_Historias_Issues.md         ← rutas /api/v1 unificadas
│   ├── 2_Matriz_Trazabilidad.md
│   ├── 3_Plantilla_Issue.md
│   ├── 4_Plantilla_Feature_Historia.md
│   ├── 5_Registro_Bugs.md
│   └── 6_Definition_of_Done.md
├── 6_Testing/
│   ├── 1_Testing_Backend.md          ← formato de encabezados corregido
│   └── 2_Plantilla_Caso_Prueba.md
└── 7_Gestion_y_Trabajo_IA/
    ├── 1_Guia_y_Prompt_Maestro.md
    ├── 2_Trabajo_con_IA.md
    ├── 3_Reglas_Agentes_IA.md
    ├── 4_Checklist_Anti_Caos.md
    └── 5_Reporte_Validacion.md
```

---

## Cierre de la Semana 1 (checklist del enunciado)

- [ ] La infraestructura se borra y reconstruye ejecutando el script, sin tocar el portal.
- [ ] Un Analista intenta modificar recursos y el sistema se lo impide.
- [ ] La API responde a una transacción válida con acuse, sin lógica de análisis.
- [ ] La API rechaza un payload inválido con el código de estado correcto.
- [ ] Se puede tumbar una instancia y el sistema sigue respondiendo.
- [ ] Se sube un archivo al contenedor de objetos desde la API.
- [ ] No hay una sola credencial, cadena de conexión o clave en el código o el repositorio.

**Entregables:** script de infraestructura · matriz de roles (`3_Seguridad/2_Matriz_Roles_Permisos.md`) · diagrama de red (`2_Arquitectura/3_Diagrama_Red.md`) · API desplegada con staging · contrato de transacción (`1_Requisitos_y_Contrato/2_Contrato_Transaccion.md`) · almacenamiento operativo · documento de decisiones (`2_Arquitectura/2_ADR_Decisiones_Arquitectura.md`).
