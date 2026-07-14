# 02 — Requisitos backend de Semana 1

## Requisitos funcionales

| ID | Requisito |
|---|---|
| RF-S1-001 | Recibir una transacción mediante `POST /api/v1/transactions`. |
| RF-S1-002 | Validar campos obligatorios y tipos del contrato. |
| RF-S1-003 | Responder con acuse sin ejecutar scoring, reglas ni apertura de casos. |
| RF-S1-004 | Persistir el JSON original de la transacción en Blob Storage. |
| RF-S1-005 | Cargar un documento de verificación mediante la API. |
| RF-S1-006 | Crear una cola y demostrar escritura, lectura y eliminación de un mensaje de prueba. |
| RF-S1-007 | Mantener configuración separada entre producción y `staging`. |

## Seguridad e infraestructura

| ID | Requisito |
|---|---|
| RS-S1-001 | Definir Analista, Administrador, Servicio y Auditor de solo lectura. |
| RS-S1-002 | Impedir que Analista modifique recursos de Azure. |
| RS-S1-003 | Usar Managed Identity para acceder a Storage. |
| RS-S1-004 | No guardar credenciales, claves ni cadenas de conexión en código o repositorio. |
| RI-S1-001 | Crear infraestructura desde scripts Bash con Azure CLI. |
| RI-S1-002 | Deshabilitar acceso público al Storage. |
| RI-S1-003 | Permitir acceso a Storage desde la integración privada de la aplicación. |
| RI-S1-004 | Usar App Service con slot `staging`. |
| RI-S1-005 | Demostrar continuidad al fallar una instancia. |
| RI-S1-006 | Poder destruir y reconstruir los recursos. |

## Requisitos no funcionales

| ID | Requisito |
|---|---|
| RNF-S1-001 | La API no espera análisis de fraude. |
| RNF-S1-002 | El despliegue normal usa una instancia; la segunda se activa solo para la prueba HA. |
| RNF-S1-003 | Región, nombres y SKU se reciben por parámetros. |
| RNF-S1-004 | La solución no debe duplicarse por cada integrante. |

## No requisitos de Semana 1

No son requisitos: publicar automáticamente la transacción en la cola, consumirla, definir el evento de scoring, escoger bases de datos, calcular score, abrir casos, integrar IA o crear CI/CD.
