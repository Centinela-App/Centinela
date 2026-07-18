package com.centinela.transactioningestion.domain.model;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

/**
 * Transaccion cruda aprobada para Semana 1.
 *
 * <p>No contiene score, decision, reglas activadas ni identificadores de caso.
 */
public record Transaction(
        String transactionId,
        String accountId,
        BigDecimal amount,
        String currency,
        OffsetDateTime occurredAt,
        Location location,
        Merchant merchant) {
}
