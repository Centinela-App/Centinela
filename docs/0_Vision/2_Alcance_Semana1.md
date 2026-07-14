# Centinela — Semana 1



## Contexto

Antes de detectar un solo fraude, Centinela necesita existir. Esta semana construyen los cimientos: la infraestructura en la nube, quién puede hacer qué dentro de ella, cómo se comunican las piezas entre sí de forma privada, y la puerta por donde entran las transacciones.

Piensen en esto como construir la bóveda antes de meter el dinero. Nada de lo que hagan en las semanas 2 y 3 va a funcionar si estos cimientos están mal puestos — y arreglar la red o los permisos cuando ya hay un pipeline encima es mucho más doloroso que hacerlo bien ahora.

Al terminar la semana, su sistema recibe transacciones y las almacena. Todavía no las analiza. Eso es esperado.



## Lo que se solicita

### 1. Infraestructura reproducible

Creen el grupo de recursos y toda la infraestructura de esta semana mediante un **script versionado en su repositorio**, usando la línea de comandos de Azure.

Pueden explorar el portal para entender qué hace cada servicio — de hecho, háganlo. Pero el estado final debe poder reconstruirse ejecutando el script en una suscripción vacía, sin intervención manual.

Documenten en el README cómo se ejecuta ese script.



### 2. Identidad y control de acceso

Definan los cuatro roles del sistema y asígnenles permisos siguiendo el **principio de menor privilegio**: cada rol tiene exactamente lo que necesita para hacer su trabajo, y nada más.

- **Analista de fraude** — revisa y resuelve casos.
- **Administrador** — configura reglas, umbrales y usuarios.
- **Servicio** — la identidad que usan los componentes internos del sistema para hablar entre sí.
- **Auditor (solo lectura)** — puede ver todo, no puede modificar nada.

Presten atención especial al rol **Servicio**. Es tentador darle permisos amplios "para que no falle nada". No lo hagan. Ese rol es exactamente el que un atacante intentaría comprometer, porque es el que corre desatendido. Cada permiso que le den de más es superficie de ataque.

Deben poder demostrar que un usuario con rol Analista no puede modificar la configuración de la infraestructura.



### 3. Red privada

Diseñen la red virtual del sistema con sus subredes y sus reglas de seguridad.

El requisito no negociable: **los almacenes de datos no deben ser alcanzables desde internet.** Solo la subred donde vive la aplicación puede llegar a ellos. Esta semana todavía no tienen bases de datos desplegadas, pero la red debe quedar preparada para recibirlas en la semana 2 bajo esta restricción.

Documenten el diagrama de red: qué subredes hay, qué vive en cada una, y qué reglas controlan el tráfico entre ellas.



### 4. Alta disponibilidad de la ingesta

La API de ingesta es el componente más crítico del sistema. Si se cae, la fintech deja de operar.

Configuren la capa de balanceo necesaria para que la API tolere la caída de una instancia sin perder transacciones. Deben poder tumbar una instancia durante una demostración y que el sistema siga respondiendo.



### 5. La API de ingesta

Desplieguen el esqueleto de la API de transacciones en el servicio de aplicaciones.

**Qué debe hacer:**
- Exponer un endpoint que reciba una transacción.
- Validar la estructura del payload.
- Responder inmediatamente con un acuse de recibo, sin realizar ningún análisis.
- Persistir la transacción cruda.

**Qué NO debe hacer todavía:** calcular scores, aplicar reglas, o abrir casos. Eso es semana 2.

Definan y documenten desde ya el **contrato de la transacción**: qué campos tiene, cuáles son obligatorios, qué tipos, qué representa cada uno. Como mínimo van a necesitar identificador de transacción, identificador de cuenta, monto, marca de tiempo, ubicación geográfica y comercio o categoría. Este contrato es la base de todo el pipeline de la semana 2 — si lo definen mal ahora, lo pagan después.

Configuren un **entorno de staging separado** del de producción, con sus propias variables de entorno. No compartan configuración entre ambientes.



### 6. Almacenamiento

Creen el contenedor de objetos donde se guardarán los **documentos de verificación de identidad** que los analistas subirán al escalar casos. Implementen la carga de un archivo desde la API para validar que funciona.

Creen también una **cola** que servirá como buffer de ingesta. Su propósito: absorber ráfagas de transacciones cuando la carga supera lo que el sistema puede procesar en el momento, para que ninguna transacción se pierda. Esta semana solo la dejan lista y validan que se puede escribir y leer de ella.



## Entregables de la semana

Al cierre de la semana, su repositorio debe contener y su célula debe poder demostrar:

**1. Script de infraestructura**
Ejecutable desde cero, versionado, documentado. Debe crear grupo de recursos, red, almacenamiento y servicio de aplicaciones.

**2. Matriz de roles y permisos**
Documento que liste cada rol, los permisos exactos que tiene y la justificación de por qué necesita cada uno. Debe estar acompañado de la configuración real aplicada.

**3. Diagrama de red**
Subredes, reglas de tráfico, y qué componente vive dónde.

**4. API de ingesta desplegada y funcionando**
Con entorno de staging separado. Recibe una transacción, la valida, responde, la persiste.

**5. Contrato de la transacción documentado**
Especificación de campos, tipos y obligatoriedad. Este es el insumo directo de la semana 2.

**6. Almacenamiento operativo**
Contenedor de objetos con carga funcionando desde la API. Cola creada y validada.

**7. Documento de decisiones de arquitectura**
Empiecen este documento ahora y manténganlo vivo durante las tres semanas. Para esta semana, registren:
- Clasificación de cada componente del sistema según el modelo de servicio en la nube que representa, y por qué.
- Por qué diseñaron la red así.
- Qué permisos le dieron al rol Servicio y por qué cada uno es necesario.



## Criterios de aceptación

Su trabajo de esta semana está listo cuando:

- [ ] Se puede borrar toda la infraestructura y reconstruirla ejecutando el script, sin tocar el portal.
- [ ] Un usuario con rol Analista intenta modificar la configuración de recursos y el sistema se lo impide.
- [ ] La API responde a una transacción válida en tiempo de acuse, sin ejecutar lógica de análisis.
- [ ] La API rechaza una transacción con payload inválido, con un código de estado correcto.
- [ ] Se puede tumbar una instancia de la API y el sistema sigue respondiendo.
- [ ] Se sube un archivo al contenedor de objetos desde la API.
- [ ] No hay una sola credencial, cadena de conexión o clave escrita en el código o en el repositorio.


## Advertencias

**No dejen la red para después.** Es la decisión más costosa de revertir. Si en la semana 2 despliegan las bases de datos y resulta que están expuestas a internet, van a tener que rehacer configuración con el pipeline ya encima.

**No sobredimensionen los permisos.** "Le doy acceso total y después lo restrinjo" es una frase que nunca termina en restricción. Empiecen restrictivo y abran solo lo que falle.

**El contrato de la transacción es un compromiso.** Piénsenlo bien esta semana. Cambiarlo en la semana 2 significa tocar la API, el motor de scoring y los almacenes al mismo tiempo.

**Los secretos van en el gestor de secretos desde el día uno.** No los pongan "temporalmente" en el código para moverlos después. Un secreto en un commit queda en el historial de git aunque lo borren en el siguiente commit.
