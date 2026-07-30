package com.centinela.shared.trace;

import java.security.SecureRandom;
import java.util.HexFormat;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Contexto de traza distribuida en formato <b>W3C Trace Context</b>.
 *
 * <p>Es la pieza que permite responder la pregunta del enunciado de Semana 3: dado un
 * identificador de transaccion, reconstruir su recorrido completo con los tiempos de
 * cada etapa. El recorrido cruza cuatro procesos distintos (API de ingesta, Event Grid,
 * motor de scoring, consumidor de casos y explicador), asi que el contexto <b>no puede
 * viajar en memoria</b>: se serializa dentro de los propios contratos de mensaje.
 *
 * <p>La representacion textual es la cabecera {@code traceparent}:
 *
 * <pre>
 *   00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
 *   ^   ^                                ^                ^
 *   |   trace-id (16 bytes)              span-id (8 bytes) flags
 *   version
 * </pre>
 *
 * <p>El {@code traceId} identifica la transaccion de extremo a extremo y no cambia
 * nunca. El {@code spanId} identifica la etapa concreta y se renueva en cada salto
 * mediante {@link #childSpan()}, de modo que el backend de telemetria puede reconstruir
 * el arbol padre-hijo y medir la duracion de cada componente por separado.
 *
 * <p><b>Por que se valida y no se confia.</b> El {@code traceparent} entra por una
 * cabecera HTTP publica: es entrada no confiable. Un valor con formato invalido no debe
 * abortar la ingesta de una transaccion — la telemetria nunca es motivo para rechazar
 * trabajo de negocio. Por eso {@link #parse(String)} devuelve vacio en lugar de lanzar,
 * y {@link #parseOrNewRoot(String)} degrada a una traza nueva.
 */
public record TraceContext(String traceId, String spanId, boolean sampled) {

    /** Unica version del formato definida por la especificacion W3C. */
    public static final String VERSION = "00";

    /** Nombre de la cabecera HTTP y del campo en los contratos de mensaje. */
    public static final String HEADER = "traceparent";

    /** Expresion regular replicada en los JSON Schema de los dos contratos. */
    public static final String PATTERN = "^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$";

    /** Misma forma que {@link #PATTERN}, con grupos para extraer cada campo. */
    private static final Pattern TRACEPARENT =
            Pattern.compile("^00-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})$");
    private static final String ALL_ZERO_TRACE_ID = "0".repeat(32);
    private static final String ALL_ZERO_SPAN_ID = "0".repeat(16);
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final HexFormat HEX = HexFormat.of();

    public TraceContext {
        requireHex(traceId, 32, "traceId");
        requireHex(spanId, 16, "spanId");
        if (ALL_ZERO_TRACE_ID.equals(traceId)) {
            throw new IllegalArgumentException("traceId must not be all zeroes");
        }
        if (ALL_ZERO_SPAN_ID.equals(spanId)) {
            throw new IllegalArgumentException("spanId must not be all zeroes");
        }
    }

    /**
     * Abre una traza nueva. Se usa cuando la peticion llega sin {@code traceparent},
     * es decir, cuando Centinela es el primer eslabon de la cadena.
     */
    public static TraceContext newRoot() {
        return new TraceContext(randomHex(16), randomHex(8), true);
    }

    /** Atajo para los productores que solo necesitan la representacion textual. */
    public static String newRootTraceparent() {
        return newRoot().toTraceparent();
    }

    /**
     * Interpreta una cabecera {@code traceparent}.
     *
     * @return el contexto, o vacio si el valor es nulo, esta mal formado o usa los
     *         identificadores todo-ceros que la especificacion declara invalidos
     */
    public static Optional<TraceContext> parse(String traceparent) {
        if (traceparent == null || traceparent.isBlank()) {
            return Optional.empty();
        }
        Matcher matcher = TRACEPARENT.matcher(traceparent.trim().toLowerCase(java.util.Locale.ROOT));
        if (!matcher.matches()) {
            return Optional.empty();
        }
        String traceId = matcher.group(1);
        String spanId = matcher.group(2);
        if (ALL_ZERO_TRACE_ID.equals(traceId) || ALL_ZERO_SPAN_ID.equals(spanId)) {
            return Optional.empty();
        }
        boolean sampled = (HEX.parseHex(matcher.group(3))[0] & 0x01) == 0x01;
        return Optional.of(new TraceContext(traceId, spanId, sampled));
    }

    /**
     * Continua la traza recibida o abre una nueva si el valor no es utilizable.
     *
     * <p>Nunca lanza: un {@code traceparent} corrupto degrada la correlacion, no la
     * disponibilidad.
     */
    public static TraceContext parseOrNewRoot(String traceparent) {
        return parse(traceparent).orElseGet(TraceContext::newRoot);
    }

    /** {@code true} si el valor puede interpretarse como contexto de traza valido. */
    public static boolean isValid(String traceparent) {
        return parse(traceparent).isPresent();
    }

    /**
     * Deriva la etapa siguiente: conserva el {@code traceId} y renueva el {@code spanId}.
     * Es lo que convierte una lista plana de registros en un arbol con tiempos por etapa.
     */
    public TraceContext childSpan() {
        return new TraceContext(traceId, randomHex(8), sampled);
    }

    /** Representacion textual que viaja en la cabecera HTTP y en los contratos. */
    public String toTraceparent() {
        return VERSION + "-" + traceId + "-" + spanId + "-" + (sampled ? "01" : "00");
    }

    private static String randomHex(int bytes) {
        byte[] buffer = new byte[bytes];
        RANDOM.nextBytes(buffer);
        String hex = HEX.formatHex(buffer);
        // Probabilidad despreciable, pero la especificacion prohibe el valor todo-ceros.
        return hex.chars().allMatch(character -> character == '0') ? randomHex(bytes) : hex;
    }

    private static void requireHex(String value, int length, String field) {
        if (value == null || value.length() != length) {
            throw new IllegalArgumentException(field + " must be " + length + " hexadecimal characters");
        }
        for (int index = 0; index < length; index++) {
            char character = value.charAt(index);
            boolean isLowerHex = (character >= '0' && character <= '9') || (character >= 'a' && character <= 'f');
            if (!isLowerHex) {
                throw new IllegalArgumentException(field + " must be lowercase hexadecimal");
            }
        }
    }
}
