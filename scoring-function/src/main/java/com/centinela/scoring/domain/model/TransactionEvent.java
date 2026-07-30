package com.centinela.scoring.domain.model;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

/**
 * Evento {@code transaction-event-v1} recibido desde Event Grid.
 *
 * <p>Representa la transaccion a puntuar. No contiene score ni reglas: eso se
 * calcula en este modulo y se persiste por separado (ISS-S2-009).
 */
public record TransactionEvent(
        String transactionId,
        String accountId,
        BigDecimal amount,
        String currency,
        OffsetDateTime occurredAt,
        EventLocation location,
        EventMerchant merchant) {

    public record EventLocation(
            String countryCode,
            String city,
            BigDecimal latitude,
            BigDecimal longitude) {
    }

    public record EventMerchant(String name, String category) {
    }
}
