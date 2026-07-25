# PostgreSQL con Managed Identity

## Propósito

La Web App de producción y el slot `staging` se conectan a PostgreSQL sin password. Cada identidad administrada se vincula a un rol de PostgreSQL mediante su Object ID.

## Ejecución

PostgreSQL solo es alcanzable por Private Endpoint. Por tanto, el siguiente comando debe ejecutarse desde un runner con resolución DNS privada y conectividad a la VNet:

```bash
bash scripts/configure-postgres-managed-identity.sh
```

El script:

1. Obtiene un token Entra del administrador configurado en PostgreSQL.
2. Crea la base `centinela` si no existe.
3. Crea los principales `NAME_PREFIX_case_prod` y `NAME_PREFIX_case_staging` asociados a las Managed Identities reales.
4. Otorga permisos sobre el esquema y sobre las tablas/secuencias que ya existan.
5. Configura JDBC passwordless y la cola correspondiente como settings sticky de producción y staging.

`deploy-week2.sh` despliega primero en producción para que Flyway cree o actualice el esquema con la identidad de producción. Después vuelve a ejecutar el bootstrap de permisos y despliega el mismo artefacto en `staging`. Así ambos ambientes usan el mismo modelo sin compartir contraseñas.

No abre acceso público ni almacena el token o una contraseña.
