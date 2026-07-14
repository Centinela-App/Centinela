# CHECKPOINT — Centinela, Semana 1 ajustada al alcance

## 1. Fuentes autoritativas

La documentación debe interpretarse en este orden:

1. `0_Vision/2_Alcance_Semana1.md`: alcance obligatorio de la Semana 1.
2. `0_Vision/1_Vision_Producto.md`: objetivo global de las tres semanas.
3. Este kit: traducción técnica de esas dos fuentes.

Si el kit agrega una obligación que no es necesaria para cumplir esas dos fuentes, prevalecen los dos documentos anteriores.

## 2. Equipo y presupuesto

- Equipo de cinco personas.
- Una sola suscripción de Azure para el entorno integrado.
- Crédito gratuito total disponible: USD 200 para el equipo.
- No se crean cinco infraestructuras completas.
- Cada integrante debe usar su propia identidad; no se comparte la contraseña de la cuenta propietaria.
- Los recursos se eliminan al terminar las pruebas o la demostración.

## 3. Alcance exacto de la Semana 1

Se implementa:

- Infraestructura reproducible con Bash y Azure CLI.
- Microsoft Entra ID, roles y mínimo privilegio.
- VNet, subred de integración de App Service y subred de Private Endpoints.
- Storage sin acceso público.
- App Service con slot `staging` y configuración separada.
- Alta disponibilidad demostrada temporalmente con dos instancias.
- API que recibe, valida y persiste la transacción cruda.
- Carga técnica de documentos de verificación desde la API.
- Cola creada y validada mediante escritura, lectura y eliminación de un mensaje de prueba.
- README, matriz de roles, diagrama de red y decisiones de arquitectura.

No se implementa:

- Scoring.
- Reglas de fraude.
- Umbral de riesgo.
- Consumo automático de la cola.
- Apertura o gestión de casos.
- Bases de datos de transacciones históricas o casos.
- IA.
- CI/CD obligatorio.
- GitHub runners privados.
- Servicios no exigidos por los documentos fuente.

## 4. Decisiones de implementación de bajo costo

- Java 21, Spring Boot y Maven como stack elegido por el equipo.
- Una aplicación modular, no microservicios separados en Semana 1.
- Un Resource Group.
- Una VNet con dos subredes.
- Un Storage Account con recursos separados lógicamente por ambiente.
- Un App Service Plan compatible con slot y escala horizontal; el SKU concreto es un parámetro y debe ser como mínimo de una categoría que soporte esas capacidades.
- Una Web App con producción y un slot `staging`.
- Una instancia normalmente; dos solo durante la prueba de alta disponibilidad.
- Región parametrizada, no fijada en la documentación.
- Key Vault solo si aparece un secreto real. La solución base usa Managed Identity para evitar secretos.
- `destroy-week1.sh` elimina los recursos creados.

## 5. Contrato estable para continuar

Semana 1 deja estable:

- `POST /api/v1/transactions`.
- El contrato de la transacción.
- `transactionId` como identificador de extremo a extremo.
- Persistencia del JSON original en Blob Storage.
- La cola de ingesta disponible.
- Separación mediante puertos y adaptadores para poder conectar el pipeline posterior.

## 6. Decisiones deliberadamente abiertas para Semana 2

Hasta recibir `Azure-Semana2.md`, no se debe decidir como obligación:

- Qué componente consume la cola.
- Qué servicio serverless se usará.
- El formato definitivo del evento de scoring.
- Si la cola actual se conserva o evoluciona a otro servicio de mensajería.
- Qué almacén conserva el historial de transacciones.
- Qué base de datos gestiona los casos.
- Las reglas, puntuaciones y umbral.
- La estructura definitiva del caso de fraude.

La Semana 2 podrá incorporar estas decisiones sin cambiar el endpoint de ingreso ni el JSON crudo ya almacenado.

## 7. Orden final de trabajo para cinco personas

- Persona 1: `ISS-S1-001` a `ISS-S1-004`.
- Persona 2: `ISS-S1-005` a `ISS-S1-009`.
- Persona 3: `ISS-S1-010` a `ISS-S1-011`.
- Persona 4: `ISS-S1-012` a `ISS-S1-013`.
- Persona 5: `ISS-S1-014` y revisión cruzada del cierre.

Ninguna issue depende de una issue con número mayor. Los archivos compartidos se entregan secuencialmente entre bloques para reducir conflictos.

## 8. Estrategia de pruebas

Las 14 issues se verifican mediante 28 casos porque una issue puede requerir varios niveles:

- Estático.
- Unitario.
- Contrato.
- Integración.
- E2E.

Seguridad, infraestructura, red, API, disponibilidad y arquitectura son categorías, no niveles. Gherkin describe los caminos feliz, alterno y de error de cualquier nivel.

## 9. Semana 2 permanece abierta

No se define consumidor, scoring, reglas, casos, bases de datos, IA ni contrato de evento futuro. Semana 1 deja estable únicamente la API de entrada, el contrato, el JSON crudo, la red/seguridad y una cola técnicamente operativa.
