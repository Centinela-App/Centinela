#!/usr/bin/env bash
#
# scripts/verify/verify-practices.sh
# Comprobaciones de calidad estructural que no dependen de que haya nada
# desplegado: se ejecutan sobre el repositorio.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

fail=0
note() { printf '[verify-practices] %s\n' "$*"; }
problema() { printf '::error::%s\n' "$*"; fail=1; }
ok() { printf '[verify-practices]   OK — %s\n' "$*"; }

# --- 1. Limites de la arquitectura hexagonal --------------------------------
note "Verificando los limites de la arquitectura (ArchUnit)..."
if mvn -B -ntp -q test -Dtest=ArchitectureConventionsTest -DfailIfNoSpecifiedTests=false >/dev/null 2>&1; then
  ok "el dominio no depende de aplicacion ni de infraestructura"
else
  problema "Las reglas de arquitectura fallan. Ejecuta: mvn test -Dtest=ArchitectureConventionsTest"
fi

# --- 2. Suite completa -------------------------------------------------------
note "Ejecutando la suite de pruebas de los dos modulos..."
if mvn -B -ntp -q test >/dev/null 2>&1; then
  ok "modulo principal en verde"
else
  problema "Fallan pruebas del modulo principal."
fi
if mvn -B -ntp -q -f scoring-function/pom.xml test >/dev/null 2>&1; then
  ok "motor de scoring en verde"
else
  problema "Fallan pruebas del motor de scoring."
fi

# --- 3. Cada componente del pipeline esta instrumentado ---------------------
# La instrumentacion tardia es el fallo que el enunciado advierte expresamente.
# Esta comprobacion detecta una etapa declarada que nadie emite.
note "Verificando que toda etapa declarada se emite en algun punto..."
etapas_revisadas=0
while read -r etapa; do
  [ -z "$etapa" ] && continue
  etapas_revisadas=$((etapas_revisadas + 1))
  # El '|| true' no es cosmetico: con 'set -e' y 'pipefail', un grep sin
  # coincidencias aborta el script entero. La comprobacion moriria en silencio
  # justo cuando encuentra el hueco que busca — y el script terminaria sin
  # reportarlo, que es la peor forma posible de fallar para un verificador.
  usos="$(grep -rlF "PipelineStage.$etapa" src/main/java scoring-function/src/main/java 2>/dev/null | wc -l || true)"
  emitido_en_motor="$(grep -rlF "stage=$etapa" scoring-function/src/main/java 2>/dev/null | wc -l || true)"
  # Se busca 'PipelineStage.X', que solo aparece donde se USA: la declaracion en
  # el enumerado es 'X,' a secas y no cuenta. Por eso el umbral es cero usos y no
  # uno — con uno se descartaria como "solo la declaracion" un componente que si
  # esta instrumentado, y el verificador reportaria huecos inexistentes.
  if [ "$usos" -eq 0 ] && [ "$emitido_en_motor" -eq 0 ]; then
    problema "La etapa $etapa esta declarada pero nadie la emite: quedaria un hueco en la traza."
  else
    ok "etapa $etapa instrumentada"
  fi
  # sed portable en vez de grep -P: la extraccion con lookbehind no esta
  # disponible en todos los grep, y fallaba en silencio — el bucle no se
  # ejecutaba y la comprobacion daba OK sin haber comprobado nada, que es
  # exactamente la clase de falso positivo que este script existe para evitar.
done < <(sed -n 's/^    \([A-Z][A-Z_]*\)[,;].*/\1/p' \
           src/main/java/com/centinela/shared/telemetry/PipelineStage.java 2>/dev/null || true)

# Una comprobacion que no comprueba nada es peor que ninguna: da OK y crea
# confianza infundada. Si no se extrajo ninguna etapa, el defecto esta aqui.
if [ "$etapas_revisadas" -eq 0 ]; then
  problema "No se pudo extraer ninguna etapa de PipelineStage.java: la comprobacion de instrumentacion no verifico nada."
fi

# --- 4. Migraciones de base de datos sin huecos -----------------------------
note "Verificando la numeracion de las migraciones..."
esperado=1
for archivo in $(find src/main/resources/db/migration -name 'V*.sql' | sort -V); do
  version="$(basename "$archivo" | sed -E 's/^V([0-9]+)__.*/\1/')"
  if [ "$version" != "$esperado" ]; then
    problema "Hueco en las migraciones: se esperaba V$esperado y se encontro V$version."
  fi
  esperado=$((esperado + 1))
done
ok "$((esperado - 1)) migraciones consecutivas"

# --- 5. Ausencia de credenciales --------------------------------------------
note "Barrido de credenciales en el repositorio..."
if bash scripts/tests/scan-repository.sh >/dev/null 2>&1; then
  ok "sin credenciales en el arbol de trabajo"
else
  problema "El barrido de credenciales encontro hallazgos."
fi

# --- 6. Los scripts de despliegue son analizables ---------------------------
if command -v shellcheck >/dev/null 2>&1; then
  note "Analizando los scripts..."
  if shellcheck -S warning scripts/*.sh scripts/lib/*.sh scripts/verify/*.sh >/dev/null 2>&1; then
    ok "shellcheck sin advertencias"
  else
    problema "shellcheck reporta advertencias. Ejecuta: shellcheck -S warning scripts/*.sh"
  fi
else
  note "shellcheck no disponible; se omite."
fi

echo ""
if [ "$fail" -eq 0 ]; then
  note "RESULTADO: OK"
else
  note "RESULTADO: FALLO"
fi
exit "$fail"
