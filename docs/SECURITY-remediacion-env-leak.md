# 🔴 Remediación — filtración de `.env` en la historia de git

> **Severidad: crítica.** Requiere acción coordinada de las 5 personas de la célula.
> Este documento describe el procedimiento; **no lo ejecutes de forma aislada**: una
> reescritura de historia con `force-push` puede destruir el trabajo de tus compañeros
> si alguien tiene commits sin publicar.

## Qué pasó

El commit **`3ea6b91`** (“feat: issue 2 finalizada”) versionó el archivo `.env` con
valores **reales** de Azure (`SUBSCRIPTION_ID`, `RESOURCE_GROUP`, `NAME_PREFIX`).
El archivo se quitó después y hoy **no está en el HEAD**, pero **sigue recuperable**
desde la historia de `develop`:

```bash
git show 3ea6b91:.env      # aún imprime los valores reales
```

Un `revert` del merge (que ya se hizo para PR19) **no borra el blob**: solo agrega un
commit que deshace los cambios, pero el objeto sigue en la base de datos de git.

El subscription filtrado (`44dc85d0…`) es **el mismo** que sigue en uso en los `.env`
locales del equipo → hay que tratarlo como **comprometido**.

## Orden de remediación

### 1. Rotar / revalidar lo expuesto (PRIMERO, antes de tocar la historia)

Reescribir la historia **no “des-filtra”** un secreto que ya pudo ser clonado. Lo
primero es reducir el valor de lo expuesto:

- [ ] **Subscription ID:** un subscription ID por sí solo no es una credencial (no da
      acceso sin autenticación), pero sí es información de reconocimiento. Confirmar
      con quien administra la cuenta de Azure si conviene migrar el entorno a un
      subscription/Resource Group nuevo, dado que también se filtró en evidencia.
- [ ] **Revisar que NO se hayan filtrado credenciales reales** junto al subscription:
      claves de Storage, client secrets, SAS tokens. Revisar el contenido completo:
      ```bash
      git show 3ea6b91:.env
      ```
      Si aparece cualquier `AccountKey`, `client secret` o SAS → **rotar esa credencial
      inmediatamente** en el portal de Azure / Entra ID.
- [ ] Confirmar que el diseño actual usa **Managed Identity** (sin connection strings),
      lo que limita el daño (ADR-005).

### 2. Coordinar con el equipo (bloqueante)

- [ ] Avisar a las 5 personas: **nadie hace push ni merge** durante la limpieza.
- [ ] Todos suben (push) su trabajo pendiente a sus ramas antes de empezar.
- [ ] Definir una ventana corta y una sola persona ejecutora.

### 3. Reescribir la historia (elige UNA herramienta)

**Opción A — git filter-repo (recomendada):**
```bash
# instalar: pip install git-filter-repo
cd Centinela
git filter-repo --path .env --invert-paths --force
```

**Opción B — BFG Repo-Cleaner:**
```bash
bfg --delete-files .env
git reflog expire --expire=now --all && git gc --prune=now --aggressive
```

Verificar que el blob desapareció (no debe imprimir nada):
```bash
git log --all --oneline -- .env
git show 3ea6b91:.env    # debe fallar con "does not exist"
```

### 4. Publicar la historia reescrita

```bash
git push origin --force --all
git push origin --force --tags
```

- [ ] Cada compañero **re-clona** el repo (o hace `git fetch` + `git reset --hard`
      sobre las ramas reescritas). Sus clones viejos conservan el blob: deben borrarlos.

### 5. Cerrar

- [ ] Confirmar en GitHub que el archivo ya no aparece en “History” del repo.
- [ ] Si el repo estuvo público en algún momento, asumir el secreto como divulgado
      permanentemente y priorizar la rotación del paso 1.
- [ ] Registrar el incidente en `docs/5_Issues_y_Trazabilidad/5_Registro_Bugs.md`.

## Prevención (ya aplicada / por aplicar)

- [x] `.gitignore` protege `.env`, `*.env`, `*.pem`, `*.key`, `*secret*`.
- [x] `scripts/tests/scan-repository.sh` ahora detecta GUIDs reales de
      subscription/tenant/objectId (segunda pasada), no solo cadenas de conexión.
- [ ] Instalar un **pre-commit hook** que corra `scan-repository.sh` antes de cada commit.
- [ ] Activar `gitleaks` como gate obligatorio en CI (capa 4 del diseño).
