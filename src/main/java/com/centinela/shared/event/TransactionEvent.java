package com.centinela.shared.event;

import com.centinela.shared.trace.TraceContext;

import java.time.OffsetDateTime;

/**
 * Contrato {@code transaction-event-v1}: evento que la API publica tras persistir
 * una transaccion cruda (API -&gt; Event Grid -&gt; Function).
 *
 * <p>Su proposito es <b>notificar la ocurrencia</b> de la transaccion para que el
 * motor de scoring reaccione de forma desacoplada. Por eso <b>no</b> transporta
 * score ni decision: esos se calculan despues, a partir del historial de la cuenta.
 *
 * <p>El esquema autoritativo es
 * {@code docs/1_Requisitos_y_Contrato/schemas/transaction-event-v1.json}. La
 * coherencia entre este record y el esquema se verifica en
 * {@code EventContractTest}. Cualquier cambio debe ser <b>aditivo</b> y compatible
 * hacia atras (ver politica de versionado en
 * {@code 4_Contrato_Evento_Transaccion.md}).
 *
 * @param transactionId identificador de la transaccion que origina el evento
 * @param accountId     cuenta duena de la transaccion y clave de particion del historial
 * @param occurredAt    momento en que ocurrio la transaccion (RFC 3339)
 * @param blobPath      ubicacion del JSON crudo en Blob Storage
 * @param eventId       identificador unico del evento (trazabilidad/correlacion)
 * @param traceparent   contexto de traza W3C; ver {@link #traceparent()}
 * @param schemaVersion discriminador de version; siempre {@link #SCHEMA_VERSION}
 */
public record TransactionEvent(
        String eventId,
        String transactionId,
        String accountId,
        OffsetDateTime occurredAt,
        String blobPath,
        String traceparent,
        String schemaVersion) {

    /** Version del contrato transportada en {@link #schemaVersion()}. */
    public static final String SCHEMA_VERSION = "transaction-event-v1";

    /**
     * Normaliza el contexto de traza sin rechazar el evento.
     *
     * <p>Un {@code traceparent} ausente o corrupto abre una traza nueva. La alternativa
     * — lanzar — subordinaria la ingesta de una transaccion real a la correccion de un
     * dato de telemetria.
     */
    public TransactionEvent {
        traceparent = TraceContext.parseOrNewRoot(traceparent).toTraceparent();
    }

    /**
     * Contexto de traza W3C heredado de la peticion HTTP que origino la ingesta.
     *
     * <p>Es el hilo que cose las etapas: el motor de scoring lo continua al puntuar, lo
     * reemite en {@code flagged-case-v1} y el explicador lo hereda al generar el texto.
     * Sin el, la traza se corta en cada salto asincrono y solo quedan metricas agregadas,
     * que el enunciado declara explicitamente insuficientes.
     */
    @Override
    public String traceparent() {
        return traceparent;
    }
}
