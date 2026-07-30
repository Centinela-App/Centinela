# Estrategia de respaldo — Almacén relacional de casos (PostgreSQL Flexible Server)

**Issue:** ISS-S2-002 · **Requisito:** RD-S2-006 (estrategia de respaldo documentada:
periodicidad, retención, RPO) · **Recurso:** `<prefix>-pg-<hash6>` (Burstable B1ms, Free tier).

## 1. Alcance y por qué existe este documento

El almacén relacional guarda **casos de fraude** (modelo Caso/Estado/Asignación/Resolución
y **auditoría inmutable**, ISS-S2-010). Estos datos tienen valor legal y de trazabilidad:
su pérdida no es recuperable reejecutando el pipeline. Por eso el enunciado exige una
estrategia de respaldo **explícita** con periodicidad, retención y RPO.

## 2. Mecanismo: respaldo automático gestionado por la plataforma

PostgreSQL Flexible Server realiza respaldos **automáticos** sin infraestructura adicional:

| Parámetro | Valor configurado | Nota |
|---|---|---|
| **Periodicidad** | Full diario + **diferenciales** cada pocas horas + **WAL continuo** | Gestionado por Azure; no requiere job propio. |
| **Retención** | **7 días** (`POSTGRES_BACKUP_RETENTION`, configurable 7–35) | 7 días es el mínimo y cabe en el Free tier. |
| **Redundancia** | **LRS** (local); geo-redundante **Disabled** | Geo-redundancia tiene costo → fuera del Free tier. |
| **RPO** | **≈ 5 minutos** | El WAL continuo permite *Point-in-Time Restore* (PITR) a cualquier instante dentro de la ventana de retención. |
| **RTO** | Minutos–horas (restore crea un servidor nuevo) | Depende del tamaño; para B1ms es bajo. |

El script `scripts/provision-postgres.sh` fija estos valores en la creación
(`--backup-retention 7 --geo-redundant-backup Disabled`).

## 3. Recuperación (Point-in-Time Restore)

Ante corrupción o borrado accidental, se restaura a un **servidor nuevo** en el instante
previo al incidente (no sobrescribe el original):

```bash
az postgres flexible-server restore \
  --resource-group "$RESOURCE_GROUP" \
  --name "<prefix>-pg-<hash6>-restore" \
  --source-server "<prefix>-pg-<hash6>" \
  --restore-time "2026-07-23T10:00:00Z"
```

Tras validar el servidor restaurado, se reapunta la aplicación/consumidor por configuración
(sin cambios de código).

## 4. Consistencia con el requisito de aislamiento (RD-S2-005)

El servidor **no es alcanzable desde internet**: `publicNetworkAccess=Disabled` y el único
camino de entrada es un **Private Endpoint** en `snet-private-endpoints`, resuelto por la zona
DNS privada `privatelink.postgres.database.azure.com`. Esto reutiliza el patrón de Semana 1
para Storage (`configure-private-endpoints.sh`). El respaldo automático opera dentro del plano
de la plataforma y **no** abre ninguna superficie pública.

## 5. Autenticación sin secretos (RS-S2-001/002)

El servidor usa **autenticación Microsoft Entra ID exclusiva** (`passwordAuth=Disabled`): no
existe ninguna contraseña de conexión que respaldar, rotar ni guardar en Key Vault. La app y el
consumidor se conectan por **Managed Identity** (token). Durante la creación se usa una
contraseña **efímera aleatoria** que se anula al deshabilitar la autenticación por password;
nunca se persiste ni se versiona.

## 6. Verificación

`scripts/tests/validate-postgres.sh` (TEST-S2-002) comprueba, vía control plane:
SKU de nivel gratuito, `publicNetworkAccess=Disabled`, `activeDirectoryAuth=Enabled`,
`passwordAuth=Disabled`, `backupRetentionDays`, el Private Endpoint (`postgresqlServer`,
estado `Approved`) y el registro A en la zona DNS privada.
