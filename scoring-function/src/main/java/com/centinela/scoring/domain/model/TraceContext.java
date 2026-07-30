package com.centinela.scoring.domain.model;

import java.security.SecureRandom;
import java.util.HexFormat;
import java.util.Locale;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Contexto de traza distribuida en formato <b>W3C Trace Context</b>.
 *
 * <p>Replica deliberada de {@code com.centinela.shared.trace.TraceContext} del modulo
 * principal. El motor de scoring se empaqueta y despliega como artefacto independiente
 * — imagen de contenedor propia, ciclo de vida propio — y no comparte classpath con la
 * API de ingesta. La alternativa seria extraer un modulo comun, lo que acoplaria el
 * despliegue de ambos por una clase de cuarenta lineas.
 *
 * <p>Las dos copias deben mantenerse en el mismo formato porque el {@code traceparent}
 * cruza de una a otra dentro de {@code transaction-event-v1}. El JSON Schema del
 * contrato es el arbitro: ambas validan contra el mismo patron.
 */
public record TraceContext(String traceId, String spanId, boolean sampled) {

    public static final String VERSION = "00";
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

    public static TraceContext newRoot() {
        return new TraceContext(randomHex(16), randomHex(8), true);
    }

    public static String newRootTraceparent() {
        return newRoot().toTraceparent();
    }

    public static Optional<TraceContext> parse(String traceparent) {
        if (traceparent == null || traceparent.isBlank()) {
            return Optional.empty();
        }
        Matcher matcher = TRACEPARENT.matcher(traceparent.trim().toLowerCase(Locale.ROOT));
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
     * <p>Un {@code traceparent} corrupto degrada la correlacion, nunca la deteccion de
     * fraude: la transaccion se puntua igual.
     */
    public static TraceContext parseOrNewRoot(String traceparent) {
        return parse(traceparent).orElseGet(TraceContext::newRoot);
    }

    public static boolean isValid(String traceparent) {
        return parse(traceparent).isPresent();
    }

    /** Deriva la etapa siguiente conservando el {@code traceId}. */
    public TraceContext childSpan() {
        return new TraceContext(traceId, randomHex(8), sampled);
    }

    public String toTraceparent() {
        return VERSION + "-" + traceId + "-" + spanId + "-" + (sampled ? "01" : "00");
    }

    private static String randomHex(int bytes) {
        byte[] buffer = new byte[bytes];
        RANDOM.nextBytes(buffer);
        String hex = HEX.formatHex(buffer);
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
