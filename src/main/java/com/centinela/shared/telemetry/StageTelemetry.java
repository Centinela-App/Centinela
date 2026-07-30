package com.centinela.shared.telemetry;

import com.centinela.shared.trace.TraceContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;

import java.util.Objects;

/**
 * Emite una linea de telemetria por etapa completada, con su duracion y su desenlace.
 *
 * <p>Estas lineas son la materia prima de las cinco preguntas que el sistema debe poder
 * responder en ejecucion. Todas llevan {@code transactionId} y {@code traceId}, de modo que
 * la traza de <b>una</b> transaccion se obtiene filtrando por su identificador y ordenando
 * por tiempo — que es precisamente lo que un panel de metricas agregadas no permite hacer.
 *
 * <p>El formato es de pares clave-valor y no prosa. Un mensaje redactado obliga a extraer
 * los campos con expresiones regulares en el momento de consultar, y cualquier cambio de
 * redaccion rompe las consultas en silencio.
 *
 * <p><b>Nunca lanza.</b> Un fallo al instrumentar no puede tumbar la etapa que estaba
 * midiendo: seria el instrumento estropeando lo que observa.
 */
public final class StageTelemetry {

    /** Un unico logger, para que todas las etapas se consulten por la misma categoria. */
    private static final Logger log = LoggerFactory.getLogger("centinela.pipeline");

    public static final String OUTCOME_SUCCESS = "SUCCESS";
    public static final String OUTCOME_FAILURE = "FAILURE";

    private StageTelemetry() {
    }

    /**
     * Registra una etapa completada con exito.
     *
     * @param durationMs tiempo de la etapa; se mide con {@link #startedAt()}
     */
    public static void success(
            PipelineStage stage, String transactionId, String traceparent, long durationMs) {
        emit(stage, transactionId, traceparent, durationMs, OUTCOME_SUCCESS, null);
    }

    /**
     * Registra una etapa fallida.
     *
     * <p>Es la linea que responde "en que punto exacto fallo una transaccion que no genero
     * caso": la ultima etapa de esa transaccion aparece con desenlace {@code FAILURE} y su
     * motivo.
     */
    public static void failure(
            PipelineStage stage, String transactionId, String traceparent, long durationMs, String reason) {
        emit(stage, transactionId, traceparent, durationMs, OUTCOME_FAILURE, reason);
    }

    /** Marca de tiempo monotona para medir la duracion de una etapa. */
    public static long startedAt() {
        return System.nanoTime();
    }

    /** Milisegundos transcurridos desde {@link #startedAt()}. */
    public static long elapsedMillis(long startedAtNanos) {
        return (System.nanoTime() - startedAtNanos) / 1_000_000L;
    }

    private static void emit(
            PipelineStage stage,
            String transactionId,
            String traceparent,
            long durationMs,
            String outcome,
            String reason) {
        try {
            String traceId = TraceContext.parse(traceparent)
                    .map(TraceContext::traceId)
                    .orElseGet(() -> MDC.get("traceId"));

            log.info("stage={} transactionId={} traceId={} durationMs={} outcome={}{}",
                    stage.stageName(),
                    Objects.toString(transactionId, "unknown"),
                    Objects.toString(traceId, "unknown"),
                    durationMs,
                    outcome,
                    reason == null ? "" : " reason=\"" + sanitize(reason) + "\"");
        } catch (RuntimeException exception) {
            // Deliberadamente silencioso: la instrumentacion no puede alterar el resultado
            // de la etapa que mide.
            log.debug("Could not emit stage telemetry", exception);
        }
    }

    /** Evita que un salto de linea o una comilla rompan el parseo de la consulta. */
    private static String sanitize(String reason) {
        String single = reason.replaceAll("\\s+", " ").replace('"', '\'').trim();
        return single.length() <= 300 ? single : single.substring(0, 300) + "…";
    }
}
