# ADR-002: Managed Identity

## Contexto

Evitar almacenar credenciales (connection strings, SAS tokens, API keys) en código o configuración. Requerimiento de seguridad RNF-S1-002.

## Decisión

Usar Azure Managed Identity (System-Assigned) para todas las comunicaciones entre App Service y Storage.

## Justificación

1. **Seguridad**: No hay secretos que filtrar o rotar
2. **Simplicidad**: Azure maneja la credencial automáticamente
3. **Cumplimiento**: Elimina vectors de ataque por credenciales hardcodeadas
4. **RBAC**: Facilita asignar permisos mínimos por identidad

## Implementación

```bash
# Habilitar Managed Identity en App Service
az webapp identity assign \
  --resource-group <rg> \
  --name <webapp-name>

# Asignar rol Storage Blob Data Contributor
az role assignment create \
  --assignee <principal-id> \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<storage>"
```

## Estado

**Aceptada** - Implementada.

## Limitaciones de Semana 1

- Solo Storage Blob Data Contributor
- Roles adicionales (Queue, Secretos) reservado para Semana 2

## Revisado

- [x] Aprobado por seguridad
- [x] Documentado para equipo
