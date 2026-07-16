# Evidencia — ISS-S1-001 · Preparar repositorio Java y estructura hexagonal

- **Fecha de ejecución:** 2026-07-15
- **Rama:** `docs/context`
- **Entorno:** Java 21.0.10 (Microsoft OpenJDK LTS) · Apache Maven 3.9.14 · Windows 11
- **Estado:** Pruebas obligatorias de la issue en verde. Evidencia sanitizada (sin secretos).

Esta carpeta contiene la evidencia reproducible que exige el Definition of Done de la
issue (ver `docs/5_Issues_y_Trazabilidad/1_Historias_Issues.md`, sección ISS-S1-001).

## Archivos

| Archivo | Contenido |
|---|---|
| `01-mvn-clean-verify.txt` | Salida resumida de `mvn clean verify` (compila + unit + ArchUnit). |
| `02-package-tree.txt` | Árbol de paquetes y archivos fuente/test/scripts versionados. |
| `03-scan-repository.txt` | Resultado del escaneo de secretos (`scripts/tests/scan-repository.sh`). |

## Criterios de aceptación (verificados)

| Criterio | Resultado | Evidencia |
|---|---|---|
| `mvn clean verify` termina correctamente con Java 21 | ✅ | `01-mvn-clean-verify.txt` → `BUILD SUCCESS` |
| Dominio y aplicación no importan Spring Web ni SDK de Azure | ✅ | `ArchitectureConventionsTest` → 5 tests, 0 fallos |
| Los cuatro módulos lógicos de Semana 1 son identificables | ✅ | `02-package-tree.txt` |
| El repositorio no contiene secretos ni cadenas de conexión | ✅ | `03-scan-repository.txt` → exit 0 |
| La aplicación inicia con el perfil de prueba sin conectarse a Azure | ✅ | `application-test.yml` sin datasources/credenciales; build en verde |

## Pruebas catalogadas cubiertas

- **TEST-S1-001** (Estático · Arquitectura) — compilación y límites hexagonales → `mvn clean verify` + ArchUnit.
- **TEST-S1-002** (Estático · Seguridad e higiene) — detección de secretos → `scan-repository.sh`.
- **TEST-S1-028** (Posterior de integración · Control de alcance) — trazada; se ejecuta al cerrar la Semana 1.

## Cómo reproducir

```bash
mvn clean verify
bash scripts/tests/scan-repository.sh
```

## Desviaciones corregidas

- Se eliminó la carpeta `centinela/` (scaffold duplicado de Spring Initializr con paquete
  `com.java.centinela`) por no estar entre los archivos autorizados de la issue. El proyecto
  válido es el de la raíz con paquete `com.centinela`.

## Pendiente para cerrar formalmente

- Revisión cruzada de Persona 5 (revisor asignado a esta issue).
