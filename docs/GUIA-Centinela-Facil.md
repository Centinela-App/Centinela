# Centinela explicado fácil 🛡️

> Una guía para entender **qué es**, **cómo funciona** y **cómo se usa** Centinela,
> sin necesidad de ser experto. Si nunca viste el proyecto, empieza aquí.
>
> 💡 A lo largo de la guía verás cajas **📁 dónde está en el código** que te llevan al
> archivo exacto que implementa cada cosa, por si quieres ir a verlo.

---

## 1. La idea en una imagen

Imagina la **oficina de correos certificados** de un banco.

Cada vez que un cliente hace una compra o transferencia, es como si llegara **un sobre**.
Centinela es el **empleado de la ventanilla**: recibe el sobre, te da un **acuse de recibo
al instante**, y lo guarda intacto en un archivador seguro.

Lo importante de esta semana (Semana 1):

- ✅ El empleado ya **recibe** los sobres y los **guarda**.
- ⏳ Todavía **no los abre ni decide si son fraude** — eso viene en las próximas semanas.

> En una frase: **construimos la oficina y contratamos al empleado de la ventanilla.
> Todavía no contratamos al detective.**

---

## 2. El proyecto tiene 3 "mundos"

Para no perderte, piensa que Centinela vive en tres mundos que trabajan juntos:

| Mundo | Qué es | Analogía | 📁 Dónde vive |
|---|---|---|---|
| ☁️ **La nube (Azure)** | Los recursos donde todo vive: el servidor, el archivador, la puerta con candado. | El **edificio** con su bóveda, cámaras y cerraduras. | (en Azure, creado por los scripts) |
| 🛠️ **Los scripts** | Programas que **construyen y revisan** el edificio automáticamente. | El **equipo de obra** que levanta el edificio siguiendo un plano. | `scripts/` |
| 💻 **La aplicación (el código Java)** | El programa que **atiende** todos los días una vez el edificio está listo. | El **empleado** que trabaja en la ventanilla. | `src/main/java/com/centinela/` |

La clave para entender todo:

> **Los scripts CONSTRUYEN el edificio (de vez en cuando).
> La aplicación TRABAJA dentro del edificio (todo el tiempo).**

---

## 3. ☁️ El mundo de la nube (Azure) — el edificio

Estos son los "cuartos" del edificio que se construyeron. Cada uno lo **crea un script** y,
si el empleado lo usa, lo **usa un archivo de código**:

| Recurso de Azure | Analogía | 📁 Lo crea el script... | 📁 Lo usa el código... |
|---|---|---|---|
| **App Service** | La **oficina** donde trabaja el empleado. | `scripts/provision-app-service.sh` | (es donde corre toda la app) |
| **Blob Storage** | El **archivador** con carpetas. | `scripts/provision-storage.sh` | `.../infrastructure/azure/blob/AzureRawTransactionBlobAdapter.java` |
| **Queue Storage** | La **fila** cuando llega mucha gente junta. | `scripts/provision-storage.sh` | (aún sin uso; se valida con `scripts/validate-queue.sh`) |
| **Entra ID** | El **sistema de credenciales** y llaves. | `scripts/provision-entra-app.sh` | `.../identityaccess/SecurityConfiguration.java` |
| **Managed Identity** | Una **llave mágica** sin combinación que anotar. | `scripts/provision-app-service.sh` (la activa) + `scripts/assign-rbac.sh` (permisos) | los adaptadores `azure/blob/*Adapter.java` |
| **Red privada (VNet)** | Un **pasillo interno** sin puerta a la calle. | `scripts/provision-network.sh` + `scripts/configure-private-endpoints.sh` | (protege al archivador; el código no la "toca") |

**Dos reglas de oro del diseño:**

1. 🔒 **El archivador no tiene puerta a la calle.** Nadie desde internet puede llegar a los
   datos; solo la oficina, por un pasillo interno.
2. 🔑 **No hay contraseñas escritas en ningún lado.** La app usa una "llave mágica"
   (Managed Identity) para entrar al archivador. Cero secretos que se puedan filtrar.

---

## 4. 🛠️ El mundo de los scripts — el equipo de obra

Un **script** es una lista de instrucciones que la computadora ejecuta sola. En vez de que
alguien arme el edificio a mano (haciendo clic en el portal de Azure), **los scripts lo
construyen automáticamente** siguiendo un plano. Ventaja enorme: si borras todo, con **un
solo comando** vuelves a tenerlo idéntico.

Los scripts vienen en 4 tipos:

### 🧰 Las herramientas compartidas
La "caja de herramientas" que usan todos los demás: mensajes en pantalla, reintentos si algo
falla, y **ocultar datos sensibles** en los registros.
> 📁 `scripts/lib/common.sh` (herramientas) y `scripts/lib/parameters.sh` (leer tu plano `.env`).

### 🎬 Los orquestadores
Los "jefes de obra". Tú solo llamas a estos tres:
- **Construir todo** el edificio, en orden → 📁 `scripts/deploy-week1.sh`
- **Revisar** que todo esté bien, sin construir ni romper nada → 📁 `scripts/validate-week1.sh`
- **Demoler** todo (con una confirmación de seguridad) → 📁 `scripts/destroy-week1.sh`

### 🧱 Los constructores
Cada uno levanta un "cuarto" del edificio. El jefe de obra (`deploy-week1.sh`) los llama en
el orden correcto:
- El archivador y las colas → 📁 `scripts/provision-storage.sh`
- La oficina y su copia de pruebas → 📁 `scripts/provision-app-service.sh`
- El pasillo interno (red privada) → 📁 `scripts/provision-network.sh` + `scripts/configure-private-endpoints.sh`
- Las credenciales y permisos → 📁 `scripts/provision-entra-app.sh` + `scripts/assign-rbac.sh`
- Subir el programa del empleado (el `.jar`) → 📁 `scripts/deploy-application.sh`

### ✅ Las inspecciones
El "inspector de calidad". Después de construir, revisan que cada cosa quedó como debía.
> 📁 `scripts/tests/` — por ejemplo: `validate-storage.sh` (el archivador), `validate-network.sh`
> (el pasillo), `validate-rbac.sh` (los permisos), `scan-repository.sh` (que no se filtren secretos).

---

## 5. 💻 El mundo de la aplicación — el empleado

Una vez el edificio está listo, la aplicación Java es quien **atiende**. Está organizada con
una idea simple llamada **arquitectura hexagonal**, que en cristiano significa:

> **Separar “qué hace” de “cómo lo hace”**, para poder cambiar la tecnología sin romper la lógica.

Piénsalo en 3 anillos, de adentro hacia afuera:

```
   ┌─────────────────────────────────────────┐
   │  INFRAESTRUCTURA  (el "cómo" técnico)    │   ← habla con internet y con Azure
   │   ┌───────────────────────────────────┐  │
   │   │  APLICACIÓN  (el "qué" hace)       │  │   ← las reglas del trabajo
   │   │   ┌─────────────────────────────┐  │  │
   │   │   │  DOMINIO  (las reglas puras) │  │  │   ← el corazón, sin tecnología
   │   │   └─────────────────────────────┘  │  │
   │   └───────────────────────────────────┘  │
   └─────────────────────────────────────────┘
```

- **Dominio** = las reglas puras (qué es una transacción válida). No sabe nada de Azure.
  > 📁 `src/main/java/com/centinela/*/domain/` (ej: `transactioningestion/domain/model/Transaction.java`)
- **Aplicación** = el guion de trabajo ("primero guardo, después respondo").
  > 📁 `src/main/java/com/centinela/*/application/` (ej: `.../application/service/IngestTransactionService.java`)
- **Infraestructura** = el único anillo que toca internet y Azure (recibe la petición web,
  escribe en el archivador).
  > 📁 `src/main/java/com/centinela/*/infrastructure/` (ej: `.../infrastructure/web/TransactionController.java`)

Ventaja: si mañana cambias de Azure a otra nube, solo tocas el **anillo de afuera**. El
corazón no se entera.

> Los dos "empleados" del sistema están en `transactioningestion/` (recibe transacciones) y
> `documentstorage/` (recibe documentos). La seguridad vive aparte en `identityaccess/`.

---

## 6. 🔄 El flujo: qué pasa cuando llega una transacción

Esta es la historia completa, paso a paso, con el archivo que hace cada cosa:

```
1. 📨 Llega una transacción a la puerta (POST /api/v1/transactions)
      📁 TransactionController.java

2. 🛂 El portero revisa la credencial
      ¿Tiene permiso de "Servicio"?
      → Sin credencial ........ ❌ 401 (no pasas)      📁 RestAuthenticationEntryPoint.java
      → Credencial equivocada .. ❌ 403 (no autorizado) 📁 RestAccessDeniedHandler.java
      → Credencial correcta .... ✅ sigue
      📁 SecurityConfiguration.java + EntraRolesJwtAuthenticationConverter.java

3. 📋 El empleado revisa que el sobre esté bien lleno
      ¿Tiene todos los datos obligatorios?
      → Mal llenado ............ ❌ 400 (rechazado)     📁 ApiExceptionHandler.java
      → Bien llenado ........... ✅ sigue
      📁 reglas del sobre: TransactionRequest.java

4. 🗄️ Guarda el sobre en el archivador (Azure Blob)
      Lo guarda tal cual llegó, en una carpeta por fecha.
      📁 orquesta: IngestTransactionService.java
      📁 escribe:  AzureRawTransactionBlobAdapter.java  (+ BlobPathFactory.java para la ruta)

5. 🧾 Entrega el acuse de recibo ..... ✅ 202 "Recibido"
      📁 TransactionReceiptResponse.java
      ⚡ Esto pasa de inmediato. El cliente NO espera ningún análisis.
```

El punto más importante: **el cliente recibe su acuse al instante** (paso 5), sin esperar a
que nadie analice nada. El análisis de fraude vendrá después, por separado, sin hacer esperar
al cliente.

> Hay un flujo gemelo para **documentos**: un analista sube un archivo (una cédula, un
> extracto) y el empleado lo guarda en otro archivador, devolviendo un acuse. Igual de simple.
> 📁 `VerificationDocumentController.java` → `StoreVerificationDocumentService.java` →
> `AzureVerificationDocumentBlobAdapter.java`.

---

## 7. 🎮 Modos de uso — cómo se usa Centinela en la práctica

Aquí es donde conectas todo. Hay dos grandes formas de "usar" Centinela:

### A. Como constructor (usas los scripts)

Tú eres el jefe de obra. Antes de nada, escribes tus datos en un archivo `.env` (tu "plano":
qué suscripción de Azure, qué región, qué nombre). Luego:

| Quiero... | Comando | 📁 Archivo |
|---|---|---|
| 🔎 **Revisar** que mi entorno está listo | `./scripts/validate-week1.sh` | `scripts/validate-week1.sh` |
| 🏗️ **Construir** todo el edificio | `./scripts/deploy-week1.sh` | `scripts/deploy-week1.sh` |
| 💥 **Demoler** todo (ahorrar costos) | `./scripts/destroy-week1.sh` | `scripts/destroy-week1.sh` |

> 📁 Tu plano de datos se copia de `.env.example` → `.env` (y **nunca** se sube al repositorio).
>
> ⚠️ **Costos:** el equipo comparte un crédito de Azure. Por eso, cuando terminas de trabajar
> o de hacer una demo, se ejecuta `destroy-week1.sh` para no gastar de más.

### B. Como usuario del sistema (usas la aplicación)

Una vez construido, la app atiende peticiones. No la "ejecutas" tú a mano; ya vive en Azure.
Se le habla enviándole peticiones web:

| Quiero... | Acción | 📁 Lo atiende... |
|---|---|---|
| 📨 **Enviar una transacción** | `POST /api/v1/transactions` con credencial de "Servicio". | `TransactionController.java` |
| 📎 **Subir un documento** | `POST /api/v1/verification-documents` con credencial de "Analista". | `VerificationDocumentController.java` |
| ❤️ **Ver si está viva** | Consultar `/actuator/health`. | configurado en `src/main/resources/application.yml` |

### C. Modo demostración (probar que aguanta caídas)

Existe un modo especial para **demostrar alta disponibilidad**: se levanta temporalmente una
segunda copia de la oficina, se "tumba" una, y se comprueba que la atención **sigue sin
interrupción**. Al terminar, se vuelve a una sola copia.
> 📁 `scripts/test-ha.sh` (+ `scripts/tests/send-transaction-load.sh` y `reconcile-accepted-transactions.sh`)

---

## 8. 🔗 Cómo se conecta TODO (el resumen visual)

```
    TÚ (con tu plano .env)
          │
          │  ejecutas
          ▼
   🛠️ deploy-week1.sh  ──llama en orden a──▶  🧱 los constructores (provision-*)
          │                                          │
          │                                          │  crean
          ▼                                          ▼
   ✅ las inspecciones (tests)  ◀──revisan──   ☁️ el edificio en Azure
                                                     │  (archivador, oficina, red, credenciales)
                                                     │
                                                     │  dentro vive y corre
                                                     ▼
                                              💻 la aplicación Java
                                                     │
                                                     │  atiende peticiones
                                                     ▼
                                          📨 transacciones y 📎 documentos
```

- **Los scripts** (`scripts/`) construyen y revisan **el edificio** (de vez en cuando).
- **La aplicación** (`src/main/java/`) vive dentro del edificio y **atiende** (todo el tiempo).
- **Tú** manejas los scripts con tu plano (`.env`), y los usuarios finales le hablan a la app.

---

## 9. 📌 ¿Dónde va el proyecto?

| Semana | Meta | Estado |
|---|---|---|
| **Semana 1 — Cimientos** | Construir el edificio, recibir y guardar transacciones. | ✅ **Hecho** (esta guía) |
| **Semana 2 — El detective** | Analizar cada transacción y decidir si es fraude. | ⏳ Próximo |
| **Semana 3 — Producción** | Automatizar despliegue, sumar IA y monitoreo. | ⏳ Futuro |

**Lo que HOY funciona:** recibir una transacción, validarla, responder al instante y
guardarla; subir documentos; y poder reconstruir toda la infraestructura con un comando.

**Lo que TODAVÍA no existe (a propósito):** detección de fraude, apertura de casos,
inteligencia artificial y bases de datos de análisis. Eso llega después.

---

> 📚 **¿Quieres más detalle?**
> - Mapa técnico completo de archivos, con todas las rutas → [`RESUMEN-Semana1.md`](RESUMEN-Semana1.md)
> - Visión completa del producto → [`0_Vision/1_Vision_Producto.md`](0_Vision/1_Vision_Producto.md)
