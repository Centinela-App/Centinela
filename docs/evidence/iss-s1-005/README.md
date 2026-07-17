# Evidencia — ISS-S1-005 · VNet, subredes, DNS privado y Private Endpoints

**Issue 5 / ISS-S1-005 — alcance ESTRICTO**: conectar la aplicacion con Blob y
Queue por **red privada** manteniendo el Storage **no alcanzable desde internet**.
Se crea **1 VNet** con **2 subredes** (`snet-app-integration` delegada a App Service
y `snet-private-endpoints`), se **integran** produccion y el slot `staging` a la
subred de integracion, se crean los **Private Endpoints de Blob y Queue** y las
**2 zonas DNS privadas** vinculadas a la VNet. `publicNetworkAccess` del Storage
permanece **Disabled**. Nada mas.

- **Rama:** `8-iss-s1-005-crear-vnet-subredes-dns-y-private-endpoints`
- **Entorno objetivo:** Azure Cloud Shell (Bash + Azure CLI preinstalados)
- **Ejecucion:** control plane via ARM inline (declarativo, idempotente) + `az webapp vnet-integration`

## Archivos del alcance estricto

| Ruta | Rol |
|---|---|
| `scripts/provision-network.sh` | VNet + 2 subredes (delegacion + PE policies) + 2 zonas DNS privadas + vinculos, y VNet Integration de produccion y `staging`. |
| `scripts/configure-private-endpoints.sh` | 2 Private Endpoints (blob, queue) + `privateDnsZoneGroups` que publican la IP privada en las zonas. |
| `scripts/tests/validate-network.sh` | TEST-S1-007: subredes, delegacion, integracion, PE, zonas DNS + vinculo + registro A, y bloqueo de acceso publico. |
| `docs/evidence/iss-s1-005/01-syntax-and-arm-render.txt` | `bash -n` + render y validacion estructural de ambos ARM (offline, reproducible). |
| `docs/evidence/iss-s1-005/02-provision-network.txt` | Salida esperada de `provision-network.sh`. |
| `docs/evidence/iss-s1-005/03-configure-private-endpoints.txt` | Salida esperada de `configure-private-endpoints.sh`. |
| `docs/evidence/iss-s1-005/04-validate-network.txt` | Salida esperada de TEST-S1-007 (18 PASS / 0 FAIL). |
| `docs/evidence/iss-s1-005/05-integracion-deploy-week1.txt` | Integracion con `deploy-week1.sh` (pasos ya registrados). |

## Topologia creada (constantes / parametros)

```text
VNet:     <NAME_PREFIX>-vnet-week1     address space  VNET_ADDRESS_SPACE (default 10.10.0.0/16)
  snet-app-integration    SUBNET_APP_PREFIX (10.10.1.0/24)  delegada a Microsoft.Web/serverFarms
  snet-private-endpoints  SUBNET_PE_PREFIX  (10.10.2.0/24)  privateEndpointNetworkPolicies=Disabled
DNS zones (global):  privatelink.blob.core.windows.net   + vnet link
                     privatelink.queue.core.windows.net  + vnet link
Private Endpoints (en snet-private-endpoints):
  <sa>-blob-pe   -> groupId 'blob'   del Storage  + privateDnsZoneGroup (zona blob)
  <sa>-queue-pe  -> groupId 'queue'  del Storage  + privateDnsZoneGroup (zona queue)
VNet Integration:  produccion y slot 'staging'  ->  snet-app-integration
TAGS: project=centinela, week=1, team=celula-centinela, issue=ISS-S1-005
```

El CIDR es **parametrizable** (`VNET_ADDRESS_SPACE` / `SUBNET_APP_PREFIX` /
`SUBNET_PE_PREFIX`), con defaults alineados al `docs/2_Arquitectura/3_Diagrama_Red.md`.
Los nombres de Storage y Web App son deterministas (mismo `sha1(prefix|sub|rg)[:6]`
de ISS-S1-003/004), por lo que no hay parametros nuevos obligatorios.

## Trazabilidad de criterios de aceptacion (§8)

- [x] **Existen exactamente las dos subredes minimas** — `snet-app-integration` y
  `snet-private-endpoints`; el test valida `length(subnets)==2` y ambos nombres.
- [x] **Produccion y staging con VNet Integration** — `virtualNetworkSubnetId`
  apunta a `snet-app-integration` en ambos.
- [x] **Blob y Queue con Private Endpoint y zona DNS vinculada** — 2 PE con groupId
  correcto + 2 zonas privadas con vinculo a la VNet y registro A publicado.
- [x] **`publicNetworkAccess` del Storage Disabled** — verificado en PE y en el test.
- [x] **Resolucion desde la app devuelve direcciones privadas** — cableado por
  control plane (zona vinculada + A record del `privateDnsZoneGroup`); ver nota en `04`.

## Idempotencia

- `provision-network.sh`: `assert_network_compliant_if_exists` omite el ARM si la
  VNet, subredes (delegacion/policies) y zonas DNS vinculadas ya cumplen — evita
  reescribir la subred y romper el `serviceAssociationLink` de la integracion.
  La VNet Integration se asegura con verificacion previa (no se recrea si ya existe).
- `configure-private-endpoints.sh`: ARM declarativo; reejecutar converge.

## Escenarios Gherkin cubiertos (§10)

- **Acceso privado operativo** → integracion + PE + DNS (`02`/`03`/`04`).
- **Acceso publico bloqueado** → `publicNetworkAccess=Disabled` + intento anonimo
  HTTP rechazado en el test (paso 8 de `04`).
- **DNS privado incompleto** → si se elimina un vinculo de zona, el test falla e
  identifica el vinculo faltante (nota al pie de `04`).

## Como probarlo en Azure Cloud Shell

```bash
cd ~ && git clone https://github.com/Centinela-App/Centinela.git && cd Centinela
git checkout 8-iss-s1-005-crear-vnet-subredes-dns-y-private-endpoints

# Variables (.env en la raiz o export). CIDR opcional:
export SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export LOCATION="eastus2"; export RESOURCE_GROUP="rg-centinela-week1"
export NAME_PREFIX="cent"; export APP_SERVICE_SKU="S1"
# export VNET_ADDRESS_SPACE="10.20.0.0/16" SUBNET_APP_PREFIX="10.20.1.0/24" SUBNET_PE_PREFIX="10.20.2.0/24"

# Prerequisitos (ISS-S1-003 y ISS-S1-004):
bash scripts/provision-storage.sh
bash scripts/provision-app-service.sh

# ISS-S1-005:
chmod +x scripts/provision-network.sh scripts/configure-private-endpoints.sh scripts/tests/validate-network.sh
bash scripts/provision-network.sh                # VNet + subredes + DNS + integracion
bash scripts/configure-private-endpoints.sh      # Private Endpoints Blob/Queue + DNS zone groups
bash scripts/tests/validate-network.sh           # TEST-S1-007 (18 PASS / 0 FAIL)
```

### Verificar en el portal
1. "Virtual networks" → `cent-vnet-week1` → "Subnets": 2 subredes; `snet-app-integration`
   con delegacion a `Microsoft.Web/serverFarms`.
2. "App Service" → "Networking" → "VNet integration": produccion y `staging` en
   `snet-app-integration`.
3. "Private endpoints": `...-blob-pe` y `...-queue-pe` en estado *Approved*.
4. "Private DNS zones": las 2 zonas `privatelink.*` con "Virtual network links" y
   un registro A por Private Endpoint.
5. Storage → "Networking": "Public network access: Disabled".

## Archivos autorizados

- **Creados:** `scripts/provision-network.sh`, `scripts/configure-private-endpoints.sh`,
  `scripts/tests/validate-network.sh` (§5 de la issue).
- **Modificables no modificados:** `scripts/deploy-week1.sh`, `scripts/validate-week1.sh`,
  `scripts/destroy-week1.sh` — ambos pasos ya estaban registrados en `PROVISION_STEPS`
  (posiciones 3 y 4) y `destroy-week1.sh` borra el RG completo (ver `05`).
- **Prohibidos:** no se creo `scripts/provision-vm.sh`, `scripts/provision-apim.sh`
  ni nada bajo `.github/workflows/**`.

## Desviaciones y decisiones

- **NSGs:** el `docs/2_Arquitectura/3_Diagrama_Red.md` documenta reglas NSG por
  subred, pero la descripcion tecnica §3 y los criterios §8 de esta issue no las
  exigen. Se mantuvo el alcance estricto (como ISS-S1-003/004) para no arriesgar
  el trafico de salida del App Service (adquisicion de token de Managed Identity).
  Las NSG pueden añadirse como refuerzo sin cambiar la topologia.
- **Nombre de la VNet:** `<prefix>-vnet-week1` (consistente con `<prefix>-asp-week1`),
  en vez del `vnet-centinela` ilustrativo del diagrama.

## Pendiente fuera de este cambio

- Ejecucion real en vivo con `az login` (Persona 2/Persona 4) — captura de
  `02`/`03`/`04` con salidas reales de Azure.
- Revision cruzada de Persona 1.
- RBAC minimo de la identidad sobre el Storage: lo aporta ISS-S1-006.
