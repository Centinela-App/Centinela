package com.centinela.shared.trace;

import java.util.Optional;

/**
 * Portador del {@link TraceContext} activo durante el procesamiento de una peticion.
 *
 * <p>Existe porque el contexto de traza se establece en el borde HTTP
 * ({@code TracePropagationFilter}) pero se necesita mucho mas abajo, en el adaptador
 * que publica el evento en Event Grid. Pasarlo como parametro obligaria a que el caso
 * de uso de ingesta — que es logica de aplicacion pura — cargara con un dato que solo
 * le sirve a la telemetria. El {@code ThreadLocal} mantiene esa preocupacion fuera del
 * contrato del dominio.
 *
 * <p><b>Limitacion asumida.</b> El contexto no cruza fronteras de hilo por si solo. La
 * ingesta de Centinela es sincrona dentro de la peticion, asi que basta. Donde el
 * trabajo salta de hilo o de proceso — el consumidor de la cola, el explicador — el
 * contexto viaja explicitamente dentro del mensaje, que es justamente por lo que los
 * contratos transportan {@code traceparent}.
 *
 * <p>Quien establece el valor es responsable de limpiarlo en un bloque {@code finally}:
 * los hilos del contenedor de servlets se reutilizan y un contexto olvidado se filtra a
 * la peticion siguiente, atribuyendo su trabajo a la traza equivocada.
 */
public final class TraceContextHolder {

    private static final ThreadLocal<TraceContext> CURRENT = new ThreadLocal<>();

    private TraceContextHolder() {
    }

    /** Contexto activo, o vacio si el hilo actual no esta dentro de una traza. */
    public static Optional<TraceContext> current() {
        return Optional.ofNullable(CURRENT.get());
    }

    /**
     * Contexto activo en su forma textual, abriendo una traza nueva si no hay ninguna.
     *
     * <p>Lo usan los productores de mensajes: siempre deben emitir un {@code traceparent}
     * valido, incluso cuando el trabajo no nace de una peticion HTTP.
     */
    public static String currentTraceparentOrNew() {
        return current().map(TraceContext::toTraceparent).orElseGet(TraceContext::newRootTraceparent);
    }

    public static void set(TraceContext context) {
        if (context == null) {
            clear();
            return;
        }
        CURRENT.set(context);
    }

    public static void clear() {
        CURRENT.remove();
    }
}
