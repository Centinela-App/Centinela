package com.centinela.shared.telemetry;

/**
 * Etapas por las que pasa una transaccion desde que entra hasta que su caso se cierra.
 *
 * <p>El enunciado exige poder responder, en ejecucion, cual es el componente de mayor
 * latencia y en que punto exacto fallo una transaccion que no genero caso. Ninguna de las
 * dos preguntas se puede responder con una latencia global: hace falta que cada etapa se
 * identifique con un nombre estable y comparable entre ejecuciones.
 *
 * <p>Que sea un enumerado y no una cadena libre es deliberado. Un nombre de etapa escrito
 * a mano en cada punto de instrumentacion diverge — {@code "scoring"}, {@code "Scoring"},
 * {@code "score"} — y las consultas de operacion dejan de agrupar correctamente justo
 * cuando se necesitan.
 */
public enum PipelineStage {

    /** Recepcion HTTP, validacion y acuse al cliente. */
    INGEST_API,

    /** Escritura del JSON crudo en el contenedor de objetos. */
    RAW_PERSIST,

    /** Publicacion de {@code transaction-event-v1} en Event Grid. */
    EVENT_PUBLISH,

    /** Evaluacion de reglas y calculo del score en el motor serverless. */
    SCORING,

    /** Consumo de {@code flagged-case-v1} y apertura del caso. */
    CASE_OPEN,

    /** Generacion asincrona de la explicacion. */
    EXPLANATION,

    /** Extraccion de datos del documento de identidad. */
    DOCUMENT_EXTRACTION;

    /** Nombre estable usado en las consultas de operacion. */
    public String stageName() {
        return name();
    }
}
