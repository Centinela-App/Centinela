package com.centinela.transactioningestion.infrastructure.web.dto;

/**
 * Acuse contractual devuelto despues de que el puerto termina correctamente.
 */
public record TransactionReceiptResponse(String transactionId, String status) {

    private static final String RECEIVED = "RECEIVED";

    public static TransactionReceiptResponse received(String transactionId) {
        return new TransactionReceiptResponse(transactionId, RECEIVED);
    }
}
