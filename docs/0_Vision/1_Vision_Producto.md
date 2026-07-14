# Centinela

**Motor de detección de fraude transaccional en tiempo real sobre Azure**

Proyecto integrador · 3 semanas · Trabajo por células


## Qué es Centinela

Centinela es un sistema que vigila el flujo de transacciones financieras de una fintech y detecta, en tiempo real, cuáles son potencialmente fraudulentas.

Cada vez que un cliente hace una compra, transferencia o retiro, la transacción entra a Centinela. El sistema la analiza contra un conjunto de reglas de riesgo, calcula un puntaje (*score*) y decide en cuestión de milisegundos:

- **Score bajo** → la transacción sigue su curso normal. El cliente ni se entera.
- **Score alto** → la transacción se marca, se abre un caso de fraude y un analista humano lo revisa con toda la evidencia en la mano.

El producto final es la plataforma completa: la API que recibe transacciones, el motor que las puntúa, el sistema de gestión de casos para los analistas, y toda la infraestructura en la nube que lo sostiene.



## El objetivo real del proyecto

Detectar fraude con reglas no es lo difícil. Lo difícil —y lo que van a construir aquí— es sostener ese análisis bajo las restricciones de un sistema financiero real:

**El cliente no puede esperar.** Cuando alguien pasa su tarjeta, la respuesta debe ser inmediata. No es aceptable que la transacción se quede colgada mientras el sistema hace cálculos pesados, consulta historial o llama a un servicio de IA. 

**El volumen no es constante.** Un viernes a las 6pm entran muchísimas más transacciones que un martes a las 3am. El sistema debe absorber picos sin perder datos ni degradarse.

**El sistema no se puede caer.** Si Centinela deja de responder, la fintech deja de operar. 

Al terminar las tres semanas, deben poder tomar una transacción, enviarla al sistema, y trazar exactamente por dónde pasó, cuánto tardó cada etapa, por qué se marcó o no, y todo eso sobre una infraestructura desplegada automáticamente desde su repositorio.



## El motor de detección: cómo funciona

La detección se basa en **reglas heurísticas**. No usan Machine Learning: cada regla es lógica que ustedes implementan y pueden explicar. Cada regla que se dispara aporta puntos al score total de la transacción.

### Reglas base (obligatorias)

**1. Velocidad de transacción**
Demasiadas transacciones desde la misma cuenta en una ventana corta de tiempo. Una cuenta que hace 8 compras en 3 minutos es sospechosa.

**2. Monto atípico**
El monto está muy por encima del comportamiento histórico de esa cuenta. Si una cuenta suele mover $50.000 y de repente intenta $4.000.000, algo pasa.

**3. Ubicación geográficamente imposible**
Dos transacciones de la misma cuenta desde ubicaciones que no se pueden recorrer en el tiempo transcurrido entre ellas. Una compra en Medellín y otra en Madrid con 10 minutos de diferencia significa que una de las dos no la hizo el titular.

**4. Comercio o categoría de riesgo**
La transacción va hacia un comercio o categoría marcada previamente como sospechosa.

### Cómo se combinan

Cada regla que se dispara suma puntos. La suma total es el score de la transacción. Si el score supera un **umbral configurable**, la transacción se marca y se abre un caso.

El umbral debe ser configurable, no un número quemado en el código. Van a tener que defender el valor que eligieron: un umbral muy bajo genera falsos positivos y satura a los analistas; uno muy alto deja pasar fraude real.

### Sobre la IA

En este proyecto la IA **no detecta el fraude** — lo detectan sus reglas. La IA cumple dos funciones distintas, ambas concretas:

- **Explicabilidad:** cuando una transacción se marca, un servicio de IA redacta en lenguaje natural la razón por la que se marcó, para que el analista entienda el caso sin leer código ni logs.
- **Verificación de identidad:** cuando un analista escala un caso, sube un documento del titular (cédula, extracto bancario) y un servicio de IA extrae automáticamente sus datos para verificarlos.



## Los actores del sistema

| Rol | Qué hace |
|---|---|
| **Cliente** | No interactúa con Centinela directamente. Solo origina transacciones que entran al sistema. |
| **Analista de fraude** | Revisa los casos marcados, ve la evidencia y la explicación generada, y resuelve: confirma el fraude o lo descarta como falso positivo. Puede escalar un caso subiendo documentos de verificación. |
| **Administrador** | Configura las reglas, ajusta el umbral de scoring, gestiona comercios de riesgo y administra usuarios. |
| **Auditor** | Puede consultar la información y la trazabilidad del sistema, pero no puede modificar configuraciones, reglas, casos, usuarios ni recursos. |
| **Servicio** | La identidad que usan los componentes internos del sistema para hablar entre sí. Tiene únicamente los permisos que necesita para operar el pipeline, nada más. |

---

## Recorrido de una transacción

Este es el camino que hace una transacción desde que entra hasta que un analista la ve. Entender este flujo es entender el proyecto.

1. **Ingesta.** La API recibe la transacción y responde de inmediato con un acuse. No espera al análisis.
2. **Publicación del evento.** La transacción se publica como un evento en el sistema de mensajería. Aquí termina la responsabilidad de la API.
3. **Scoring.** Un componente serverless reacciona al evento, consulta el historial reciente de esa cuenta, aplica las reglas y calcula el score.
4. **Decisión.** Si el score supera el umbral, se encola un caso de fraude. Si no, la transacción simplemente queda registrada.
5. **Apertura del caso.** El caso se crea en la base de datos de gestión, listo para ser asignado a un analista.
6. **Explicación.** Se genera la explicación en lenguaje natural del porqué de la marca.
7. **Resolución.** El analista revisa, decide y cierra el caso. Todo queda auditado.

El punto crítico: **entre el paso 1 y el paso 7 pueden pasar segundos, pero el cliente ya recibió su respuesta en el paso 1.** Si su arquitectura hace que el cliente espere por el paso 6, está mal diseñada.



## Dónde vive cada dato

El sistema maneja tres tipos de información con necesidades completamente distintas. Elegir el almacén correcto para cada una es parte del ejercicio, y tendrán que justificar sus decisiones.

**Transacciones y scores — almacén de alto volumen y baja latencia**
Millones de registros, escritura constante, y una consulta dominante: *"dame las transacciones recientes de esta cuenta"*. El diseño de este almacén determina si el sistema escala o se ahoga. La clave está en cómo particionan los datos para no escanear todo el almacén en cada scoring.

**Casos de fraude — almacén relacional y transaccional**
Volumen bajo comparado con las transacciones, pero con relaciones (caso ↔ analista ↔ resolución ↔ auditoría), reportería y necesidad de trazabilidad legal. Aquí importan la integridad referencial y las transacciones ACID.

**Documentos de verificación — almacén de objetos**
Archivos binarios (PDFs, imágenes de documentos) que los analistas suben al escalar un caso.



## Reglas del juego

**El lenguaje es libre.** Pueden construir el backend y los componentes serverless en el lenguaje que su célula domine: C#/.NET, Node.js, Python, Java. Nadie va a ser evaluado por elegir un stack en vez de otro.

**Lo que no es libre es el contrato.** La forma de los eventos y los payloads que cruzan el pipeline debe estar definida y documentada por la célula desde el inicio, porque de eso depende que las piezas encajen entre sí.

**La infraestructura se crea por script, no a mano.** Toda la infraestructura debe poder recrearse desde cero ejecutando un script versionado en su repositorio. Si la única forma de reconstruir su sistema es que alguien recuerde qué botones apretó en el portal, no cuenta como reproducible.

**Ningún secreto vive en el código.** Cadenas de conexión, claves de API, credenciales: todas van en un gestor de secretos. Un secreto en un commit es un secreto comprometido, aunque después lo borren.

**Todo se justifica.** No se evalúa que hayan usado un servicio, sino que sepan por qué lo usaron y qué les costó. Las decisiones de arquitectura se documentan: por qué esa clave de partición, por qué ese nivel de consistencia, por qué mensajería en vez de una llamada directa.



## Estructura de las tres semanas

**Semana 1 — Fundamentos.** Levantar la infraestructura, la identidad, la red, el almacenamiento y la puerta de entrada del sistema. Al final, la API recibe, valida y almacena transacciones; también quedan operativas la carga técnica de documentos y la cola que usará el pipeline posterior. Todavía no se calculan scores ni se abren casos.

**Semana 2 — El motor.** Construir el pipeline serverless de scoring y los almacenes de datos. Al final, una transacción que entra se puntúa automáticamente y abre un caso si corresponde. Los servicios concretos, el contrato del evento y el modelo de persistencia se definirán cuando se entregue el documento específico de Semana 2.

**Semana 3 — Producción.** Automatizar el despliegue, integrar los servicios de IA y hacer el sistema observable. Al final, tienen un producto desplegado y trazable de punta a punta.

Cada semana tiene su propio documento con lo que se solicita y lo que se entrega.



## Lo que se espera

Al cierre del proyecto, su célula debe poder pararse frente a alguien que nunca vio el sistema, enviarle una transacción fraudulenta en vivo, y mostrarle:

- que fue detectada por las reglas correctas,
- que el cliente recibió respuesta antes de que terminara el análisis,
- que el analista tiene un caso abierto con una explicación clara,
- que todo el recorrido es visible en la herramienta de monitoreo,
- y que si borran toda la infraestructura, pueden reconstruirla ejecutando un script.

