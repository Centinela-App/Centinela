# Índice de evidencias — Semana 3

## Cómo se genera

```bash
bash scripts/tests/capture-week3-evidence.sh
```

Cada corrida crea `docs/evidence/iss-s3-XXX/run-<sello-UTC>/` con:

- `00-metadata.txt` — commit, rama, instante, versión de Java y de Maven.
- Un archivo por comprobación, con el comando ejecutado, su salida completa y una línea
  `# RESULTADO: OK` o `# RESULTADO: FALLO (codigo N)`.

**La evidencia se genera, no se pega.** Una salida copiada a mano en un documento no dice con qué
versión del código se obtuvo, y en cuanto el código cambia deja de ser evidencia para convertirse
en decoración. Cada archivo lleva su commit, así que se puede saber exactamente qué se ejecutó.

## Qué significa cada resultado

| Marca | Significado |
|---|---|
| `# RESULTADO: OK` | El comando se ejecutó y su criterio se cumple. |
| `# RESULTADO: FALLO` | El comando se ejecutó y **no** se cumple. Es un hallazgo, no un error del script. |
| `01-no-verificable.txt` | La comprobación exige un recurso ausente en este entorno. Se declara en vez de dejar una carpeta vacía que parezca evidencia. |

La distinción del tercer caso importa. Una carpeta vacía se lee como «no se hizo»; un archivo que
dice *«esta issue está implementada, pero su criterio exige ejecutar contra un recurso que no está
disponible»* dice exactamente qué falta y por qué.

## Qué prueba cada carpeta

| Issue | Evidencia | Qué demuestra |
|---|---|---|
| `iss-s3-001` | Contexto de traza, contrato, esquemas | El `traceparent` sobrevive los saltos asíncronos y los esquemas están sincronizados con los records |
| `iss-s3-002` | Detalle de activación, suite del motor | Cada afirmación de la explicación objetivo tiene su valor registrado, y la detección no cambió |
| `iss-s3-003` | Migración V4, apertura de caso | El caso nace `PENDING` con cuenta y traza |
| `iss-s3-004` | API de consulta, autorización | Una transacción limpia tiene análisis pero no caso |
| `iss-s3-005` | Etapas instrumentadas | Ninguna etapa declarada queda sin emisor |
| `iss-s3-006` | Construcción de imagen, barrido de capas | La imagen no contiene credenciales en ninguna capa |
| `iss-s3-007` | Construcción de la imagen del motor | El motor se empaqueta conservando su disparador |
| `iss-s3-008` | Plan del registro | Aprovisionamiento reproducible sin crear nada |
| `iss-s3-009` | Plan de Container Apps | Reglas de escalado justificadas |
| `iss-s3-010` | Observación de réplicas | Aumento y reducción bajo carga real |
| `iss-s3-011` | Plan de OIDC | Credencial federada sin contraseña |
| `iss-s3-012` | Suite completa, barrido de secretos | Lo que el pipeline de CI ejecuta |
| `iss-s3-013` | Encadenamiento de etapas | Una prueba fallida detiene el pipeline |
| `iss-s3-014` | ADR-008 | Criterio, contrapartida y contexto inverso |
| `iss-s3-015` | Tamaño de imágenes | Medidas de optimización y su efecto |
| `iss-s3-016` | Consultas de operación | Las cinco preguntas tienen consulta |
| `iss-s3-017` | Traza individual | Recorrido con tiempos por etapa |
| `iss-s3-018` | Disparo de la alerta | La condición provoca la notificación |
| `iss-s3-019` | Agentes y verificación de prácticas | Auditoría reproducible sin depender de una IA |
| `iss-s3-020` | Reporte de crédito | Consumo final del proyecto |
| `iss-s3-021` | Correspondencia estricta | La explicación no afirma de más ni de menos |
| `iss-s3-022` | Resiliencia del explicador | Detenido no impide abrir casos |
| `iss-s3-023` | Manejo de fallos documentales | Ningún desenlace interrumpe el flujo |
| `iss-s3-024` | Escenarios del banco de pruebas | Cada escenario genera la forma de tráfico que promete |
| `iss-s3-025` | ADR cerrado | Decisiones de las tres semanas |

## Lo que esta captura no puede demostrar

Las issues `010`, `017`, `018` y `020` exigen un sistema desplegado en Azure y, en dos casos,
provocar una condición en vivo. No hay forma honesta de sustituir eso por una comprobación local:
el enunciado es explícito en que una configuración documentada no es evidencia de que el escalado
ocurra, y lo mismo vale para una alerta que nunca se ha disparado.

Para completarlas hay que ejecutar, en este orden:

```bash
bash scripts/provision-container-registry.sh
bash scripts/provision-container-apps.sh
CENTINELA_ALERT_EMAIL="..." bash scripts/provision-observability.sh
CENTINELA_GITHUB_REPO="Centinela-App/Centinela" bash scripts/provision-github-oidc.sh
bash scripts/deploy-containers.sh --tag "$(git rev-parse HEAD)"

# Y después, con tráfico real generado desde centinela-lab:
bash scripts/verify/verify-scaling.sh                    # ISS-S3-010
bash scripts/verify/verify-trace.sh <transactionId>      # ISS-S3-017
bash scripts/verify/verify-explainer-correspondence.sh <transactionId>
```

## Hallazgos de la propia captura

La primera corrida encontró cuatro defectos, **todos en las herramientas de verificación y
ninguno en el código de producción**. Vale la pena registrarlo porque es el modo de fallo más
peligroso: un verificador roto no avisa de que está roto, da OK y crea confianza infundada.

1. El barrido de credenciales se detectaba a sí mismo — `verify-image-secrets.sh` contiene los
   patrones que busca. Resuelto con la convención que el propio escáner ya usaba.
2. GUIDs reales sin enmascarar en una evidencia de Semana 1, versionados. Ver
   `docs/SECURITY-remediacion-env-leak.md`.
3. La comprobación de instrumentación moría en silencio por usar `grep -P` con *lookbehind*, no
   soportado en todos los entornos. Al arreglarla, su umbral resultó estar mal y reportaba huecos
   inexistentes en cinco etapas.
4. `INGEST_API` estaba declarada y nadie la emitía — un hueco genuino, encontrado por la
   comprobación una vez arreglada.
