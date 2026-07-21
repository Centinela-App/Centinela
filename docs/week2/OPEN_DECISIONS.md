# Decisiones Reservadas para Semana 2

Este documento enumera las decisiones técnicas que fueron identificadas durante Semana 1 pero no fueron resueltas. El propósito es preservarlas para referencia futura, **sin proponer soluciones**.

---

## 1. Persistencia Transaccional

### Estado: ABIERTO

**Pregunta**: ¿Se requiere una base de datos para persistir el estado de las transacciones?

**Contexto de Semana 1**:
- Actualmente solo se almacenan blobs en Storage
- No hay forma de consultar el estado de una transacción
- El sistema es "fire-and-forget"

**Consideraciones pendientes**:
- Azure SQL, Cosmos DB, o PostgreSQL flexible
- Esquema de datos por definir
- Estrategia de migraciones

---

## 2. Procesamiento Asíncrono (Queue)

### Estado: ABIERTO

**Pregunta**: ¿Cómo se conectará Azure Queue Storage al flujo de negocio?

**Contexto de Semana 1**:
- Queue fue aprovisionada pero desconectada del flujo
- No hay publisher de mensajes
- No hay consumer/processor

**Consideraciones pendientes**:
- Pattern: Event-Driven o Job-Based
-dead-letter handling
- Retry policy

---

## 3. Motor de Scoring

### Estado: ABIERTO

**Pregunta**: ¿Cómo se implementará la lógica de evaluación/scoring de transacciones?

**Contexto de Semana 1**:
- La API solo recibe y almacena
- No hay lógica de decisión
- No hay evaluación de riesgo

**Consideraciones pendientes**:
- Reglas simples vs ML
- Thresholds configurables
- Auditoría de decisiones

---

## 4. Staging vs Production Físico

### Estado: ABIERTO

**Pregunta**: ¿Se requiere separación física de recursos para staging?

**Contexto de Semana 1**:
- Separación solo lógica por prefijos
- Un solo App Service
- No hay deployment slots

**Consideraciones pendientes**:
- App Service Deployment Slots
- Traffic Manager para producción
- Blue/Green deployments

---

## 5. Multi-Región / DR

### Estado: ABIERTO

**Pregunta**: ¿Se requiere alta disponibilidad multirregión?

**Contexto de Semana 1**:
- Una sola región (eastus2)
- Un solo Storage Account
- No hay failover

**Consideraciones pendientes**:
- Geo-redundant Storage (GRS)
- Multi-region App Service
- Failover strategy

---

## 6. Contrato de Eventos

### Estado: ABIERTO

**Pregunta**: ¿Cómo serán los eventos publicados para consumo externo?

**Contexto de Semana 1**:
- Sin publisher de eventos
- Sin esquema de eventos definido
- Sin consumers externos

**Consideraciones pendientes**:
- Event Grid vs Event Hub
- Schema Registry
- Versioning strategy

---

## 7. Consumer/Subscriber Externo

### Estado: ABIERTO

**Pregunta**: ¿Quién consumirá los eventos de Centinela?

**Contexto de Semana 1**:
- No hay subscribers definidos
- Sin API de consulta para terceros
- Sin webhooks

**Consideraciones pendientes**:
- API de solo lectura para consumers
- Webhook endpoints
- Rate limiting

---

## 8. Monitoreo y Observabilidad

### Estado: ABIERTO

**Pregunta**: ¿Qué stack de monitoreo se implementará?

**Contexto de Semana 1**:
- Sin Application Insights
- Sin dashboards
- Sin alertas configuradas

**Consideraciones pendientes**:
- Application Insights
- Azure Monitor
- Alert rules y thresholds

---

## 9. API de Consulta/Lectura

### Estado: ABIERTO

**Pregunta**: ¿Cómo consultarán los usuarios los datos almacenados?

**Contexto de Semana 1**:
- PUT-only API
- No hay endpoints GET
- No hay paginación

**Consideraciones pendientes**:
- GET /transactions/{id}
- Filtros y búsqueda
- Autorización de lectura (Centinela.Read)

---

## 10. Backups y Retención

### Estado: ABIERTO

**Pregunta**: ¿Cuál es la política de backup y retención de datos?

**Contexto de Semana 1**:
- Storage con LRS por defecto
- Sin lifecycle policies
- Sin backup de aplicación

**Consideraciones pendientes**:
- Blob lifecycle management
- Point-in-time restore
- Compliance requirements

---

## Proceso para Resolver

Cuando el equipo esté listo para abordar una decisión:

1. **Crear ADR** en `docs/adr/` siguiendo el template
2. **Discutir** en issue dedicada de Semana 2
3. **Decidir** con consenso del equipo
4. **Documentar** la decisión en ADR
5. **Implementar** en Sprint de Semana 2

---

## NO Incluir en Semana 2

Las siguientes decisiones están **explícitamente fuera** del alcance de Centinela:

- ❌ Diseño de UI/Dashboard
- ❌ Aplicación móvil
- ❌ Integración con sistemas bancarios específicos
- ❌ Procesamiento de pagos (no es un Payment Gateway)
- ❌ AML/KYC completo
- ❌ Soporte multi-tenant

---

## Referencias

- [Arquitectura Semana 1](../2_Arquitectura/centinela-week1.md)
- [ADR-001: Hexagonal](./adr/ADR-001-hexagonal.md)
- [ADR-002: Managed Identity](./adr/ADR-002-managed-identity.md)
- [ADR-003: Private Storage](./adr/ADR-003-private-storage.md)
- [ADR-004: Environment Separation](./adr/ADR-004-environment-separation.md)
