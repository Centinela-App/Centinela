# Matriz de roles y permisos — Semana 1

Entregable obligatorio del enunciado (entregable 2): cada rol, los permisos exactos que tiene y la **justificación** de por qué necesita cada uno, bajo el **principio de menor privilegio**. Debe acompañarse de la configuración real aplicada (ver `4_Infraestructura_y_Despliegue/1_Deployment.md`, script `assign-rbac.sh`, y `ISS-S1-006`).

Los roles operan en dos planos que no deben confundirse:
- **Plano de aplicación** — app roles de Microsoft Entra ID, convertidos por Spring Security a authorities `ROLE_*`. Controlan qué endpoint puede invocar cada quién.
- **Plano de Azure (control) / RBAC** — quién puede ver o modificar recursos de Azure.

---

## 1. Roles del sistema (los cuatro del enunciado)

| Rol | Qué hace en el producto | Estado en Semana 1 |
|---|---|---|
| **Analista de fraude** | Revisa y resuelve casos; escala subiendo documentos. | En Semana 1 solo ejerce la **carga técnica de documentos**. La gestión de casos es Semana 2. |
| **Administrador** | Configura reglas, umbrales y usuarios. | En Semana 1 **no hay** endpoints de configuración; no recibe escritura sobre endpoints de negocio. |
| **Servicio** | Identidad de los componentes internos para hablar entre sí (corre desatendido). | Entrega transacciones a la ingesta. Es el rol más sensible → mínimo estricto. |
| **Auditor (solo lectura)** | Ve todo, no modifica nada. | Solo lectura; sin operaciones de escritura. |

---

## 2. Matriz — plano de aplicación (endpoints)

| Acción | `SERVICE` | `ANALYST` | `ADMINISTRATOR` | `AUDITOR` |
|---|:---:|:---:|:---:|:---:|
| `POST /api/v1/transactions` | ✅ único autorizado | ❌ 403 | ❌ 403 | ❌ 403 |
| `POST /api/v1/verification-documents` | ❌ 403 | ✅ único autorizado | ❌ 403 | ❌ 403 |
| Sin token válido | 401 | 401 | 401 | 401 |

**Justificación por rol:**
- **SERVICE** → solo `POST /api/v1/transactions`, porque su única función en Semana 1 es entregar la transacción. No carga documentos ni lee: cada permiso extra sería superficie de ataque en el rol que corre desatendido.
- **ANALYST** → solo `POST /api/v1/verification-documents`, porque la carga documental es la única acción de analista disponible esta semana.
- **ADMINISTRATOR** → sin escritura de negocio, porque los endpoints de configuración/umbral/usuarios pertenecen a semanas posteriores; no existe aún nada legítimo que administrar por API.
- **AUDITOR** → ninguna escritura, por definición de solo lectura.

---

## 3. Matriz — plano de Azure (RBAC / control)

| Identidad | Asignación | Alcance | Justificación |
|---|---|---|---|
| **Identidad de despliegue** (quien corre `deploy-week1.sh`) | Solo lo necesario para crear los recursos | Resource Group del proyecto | Reproducir la infraestructura sin ser Owner de la suscripción. |
| **Managed Identity del App Service** (prod y staging) | Rol de **datos de Blob** acotado | Contenedores que usa la API | Persistir JSON crudo y documentos. Acceso de **datos**, no de administración. |
| **Managed Identity del App Service** | **Sin** rol de Queue | — | La cola no participa del flujo de negocio en Semana 1. |
| **Analista** (usuario) | `Reader` (demostrativo) | Resource Group | Demostrar consulta sin poder modificar → cumple "Analista no puede modificar la configuración" (`TEST-S1-009`). |
| **Auditor** (usuario) | `Reader` | Resource Group | Ver todo, modificar nada. |
| **Identidad de la prueba de Queue** | Permiso mínimo de cola, **temporal** | Cuenta de Storage | Solo para el roundtrip de conectividad; se revoca al terminar si se asignó solo para la prueba. |

**Regla dura:** ninguna identidad recibe `Contributor` ni `Owner` automáticamente. Ver `ADR-003` en `2_Arquitectura/2_ADR_Decisiones_Arquitectura.md` para el detalle del rol Servicio.

---

## 4. Cómo se demuestra el mínimo privilegio

| Afirmación a demostrar | Prueba |
|---|---|
| Analista no puede modificar recursos de Azure | `TEST-S1-009` (RBAC: intenta modificar tag/Storage/eliminar → denegado) |
| Roles y autorización por endpoint (401/403) | `TEST-S1-008`, `TEST-S1-021`, `TEST-S1-022` |
| La Managed Identity no tiene rol de Queue | `TEST-S1-010` |
| No hay secretos en código/repositorio | `TEST-S1-002`, `TEST-S1-010`, script `scan-repository.sh` |

---

## 5. Mapa app role → authority Spring

| App role (Entra ID) | Authority Spring |
|---|---|
| `SERVICE` | `ROLE_SERVICE` |
| `ANALYST` | `ROLE_ANALYST` |
| `ADMINISTRATOR` | `ROLE_ADMINISTRATOR` |
| `AUDITOR` | `ROLE_AUDITOR` |

La conversión la hace un convertidor de OAuth2 Resource Server (JWT); el claim `roles` no debe confundirse con los roles de Azure RBAC.
