package com.centinela.scoring.domain.model;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

/**
 * Proyeccion minima de una transaccion pasada de la MISMA cuenta, recuperada
 * de una sola particion de Cosmos (clave de particion {@code accountId}).
 *
 * <p>Solo contiene los campos que necesitan las reglas de dominio (ISS-S2-008):
 * no expone tipos del SDK de Cosmos ni el documento completo.
 */
public record HistoricalTransaction(
        String transactionId,
        BigDecimal amount,
        OffsetDateTime occurredAt,
        BigDecimal latitude,
        BigDecimal longitude) {
}
