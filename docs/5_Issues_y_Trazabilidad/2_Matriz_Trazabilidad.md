# 11 — Matriz de trazabilidad de Semana 1

| Requisito | Issue(s) | Prueba(s) | Evidencia principal |
|---|---|---|---|
| `RF-S1-001` | ISS-S1-007, ISS-S1-008 | TEST-S1-011, 012, 016 | Endpoint, contrato y E2E. |
| `RF-S1-002` | ISS-S1-007 | TEST-S1-011, 012, 017 | Contrato y payloads inválidos. |
| `RF-S1-003` | ISS-S1-007, ISS-S1-008 | TEST-S1-013, 014, 016, 028 | Acuse sin análisis. |
| `RF-S1-004` | ISS-S1-003, ISS-S1-008 | TEST-S1-005, 015, 016 | JSON crudo en Blob. |
| `RF-S1-005` | ISS-S1-009, ISS-S1-011 | TEST-S1-018, 019, 022 | Carga documental solo por Analista. |
| `RF-S1-006` | ISS-S1-003, ISS-S1-010 | TEST-S1-005, 020 | Roundtrip Queue técnico. |
| `RF-S1-007` | ISS-S1-004, ISS-S1-008, ISS-S1-009 | TEST-S1-006, 023 | Aislamiento staging/production. |
| `RS-S1-001` | ISS-S1-006, ISS-S1-011 | TEST-S1-008, 021, 022 | Roles y autorización. |
| `RS-S1-002` | ISS-S1-006 | TEST-S1-009 | Analista sin modificación Azure. |
| `RS-S1-003` | ISS-S1-006, ISS-S1-008, ISS-S1-009 | TEST-S1-010, 015, 019 | Managed Identity y Blob. |
| `RS-S1-004` | ISS-S1-001, ISS-S1-002, ISS-S1-006, ISS-S1-013 | TEST-S1-002, 010 | Sin credenciales. |
| `RI-S1-001` | ISS-S1-002..ISS-S1-006, ISS-S1-014 | TEST-S1-003, 026, 027 | Despliegue por scripts. |
| `RI-S1-002` | ISS-S1-003, ISS-S1-005 | TEST-S1-005, 007 | Storage privado. |
| `RI-S1-003` | ISS-S1-005 | TEST-S1-007 | Acceso privado desde aplicación. |
| `RI-S1-004` | ISS-S1-004 | TEST-S1-006, 023 | App Service y staging. |
| `RI-S1-005` | ISS-S1-012 | TEST-S1-024 | Alta disponibilidad. |
| `RI-S1-006` | ISS-S1-002, ISS-S1-014 | TEST-S1-004, 027 | Destruir/reconstruir. |
| `RNF-S1-001` | ISS-S1-001, ISS-S1-007, ISS-S1-008, ISS-S1-013 | TEST-S1-001, 013, 014, 016, 028 | Sin análisis de fraude. |
| `RNF-S1-002` | ISS-S1-012, ISS-S1-014 | TEST-S1-024, 027 | Dos instancias solo en prueba. |
| `RNF-S1-003` | ISS-S1-002 | TEST-S1-003, 026 | Parámetros no rígidos. |
| `RNF-S1-004` | ISS-S1-002, ISS-S1-013, ISS-S1-014 | TEST-S1-003, 026, 027 | Un entorno compartido. |

## Reglas de lectura

- Una issue puede tener varias pruebas de diferentes niveles.
- Una prueba puede cubrir más de una issue cuando verifica integración o E2E.
- Las 14 issues permanecen dentro de Semana 1.
- No existe trazabilidad hacia scoring, casos, IA, consumidor o bases de Semana 2.
