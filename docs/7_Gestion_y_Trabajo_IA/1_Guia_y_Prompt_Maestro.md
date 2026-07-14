# 01 — Guía y prompt maestro

## Instrucción para cualquier agente

Trabaja exclusivamente con `0_Vision/2_Alcance_Semana1.md` y `0_Vision/1_Vision_Producto.md`.

Antes de proponer un cambio, comprueba:

1. ¿Es obligatorio para un entregable o criterio de aceptación de Semana 1?
2. ¿Es una decisión mínima para implementar ese requisito?
3. ¿Respeta el presupuesto compartido de USD 200?
4. ¿Evita cerrar una decisión que pertenece a Semana 2?

Si la respuesta a 1 y 2 es no, no lo agregues como obligación.

## Reglas

- No implementar scoring, casos, IA ni bases de datos futuras.
- No agregar pipelines CI/CD, runners, gateways o servicios adicionales como requisito.
- No fijar región ni tamaño exacto del App Service en la documentación; parametrizarlos.
- No crear secretos si Managed Identity resuelve el acceso.
- No cambiar el contrato de transacción sin actualizar OpenAPI, pruebas y matriz.
- Mantener Java 21, Spring Boot, Maven y arquitectura hexagonal interna.
