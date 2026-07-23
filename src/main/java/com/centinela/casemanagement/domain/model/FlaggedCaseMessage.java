package com.centinela.casemanagement.domain.model;

/**
 * Mensaje recibido desde la cola de casos flagged.
 *
 * <p>Este DTO representa el contenido del mensaje en la Storage Queue
 * cuando el consumidor lo procesa.
 */
public record FlaggedCaseMessage(
        String transactionId,
        String accountId,
        String reason,
        String triggeredRules,
        String messageId) {

    /**
     * Valida que el mensaje tenga la información mínima requerida.
     *
     * @throws IllegalArgumentException si transactionId es nulo o vacío
     */
    public FlaggedCaseMessage {
        if (transactionId == null || transactionId.isBlank()) {
            throw new IllegalArgumentException("transactionId is required");
        }
    }
}
