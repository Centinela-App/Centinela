package com.centinela.shared.event;

import java.time.OffsetDateTime;
import java.util.List;

/**
 * Contrato {@code flagged-case-v1}: mensaje que la Function encola cuando el score
 * de una transaccion supera el umbral (Function -&gt; Storage Queue -&gt; consumidor).
 *
 * <p>Es el <b>disparador de apertura de caso</b>. Viaja por una cola (no por una
 * llamada directa) para garantizar el procesamiento aunque el consumidor este caido.
 * El {@code transactionId} es la clave de idempotencia: reprocesar el mismo mensaje
 * no debe abrir un caso duplicado.
 *
 * <p>Solo transporta un <b>resumen</b> de las reglas activadas
 * ({@link TriggeredRuleSummary}). El detalle completo con los valores observados se
 * persiste en Cosmos junto a la transaccion (ISS-S2-009), no aqui.
 *
 * <p>El esquema autoritativo es
 * {@code docs/1_Requisitos_y_Contrato/schemas/flagged-case-v1.json}. La coherencia
 * entre este record y el esquema se verifica en {@code EventContractTest}.
 *
 * @param transactionId  transaccion que disparo el caso (clave de idempotencia)
 * @param accountId      cuenta asociada al caso
 * @param score          puntaje total que supero el umbral
 * @param triggeredRules resumen de las reglas activadas (id + puntos)
 * @param occurredAt     momento en que ocurrio la transaccion (RFC 3339)
 * @param scoredAt       momento en que se calculo el score (RFC 3339)
 */
public record FlaggedCaseMessage(
        String transactionId,
        String accountId,
        int score,
        List<TriggeredRuleSummary> triggeredRules,
        OffsetDateTime occurredAt,
        OffsetDateTime scoredAt) {

    /** Version del contrato de este mensaje. */
    public static final String SCHEMA_VERSION = "flagged-case-v1";

    /**
     * Resumen de una regla activada: identificador y puntos aportados. No incluye
     * los valores observados (esos se persisten en Cosmos para el explicador de
     * Semana 3), manteniendo el mensaje pequeno y estable.
     *
     * @param ruleId identificador de la regla activada
     * @param points puntos que la regla aporto al score total
     */
    public record TriggeredRuleSummary(String ruleId, int points) {
    }
}
