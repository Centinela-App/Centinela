package com.centinela.transactioningestion.domain.model;

import java.math.BigDecimal;

/**
 * Ubicacion cruda informada por el sistema originador.
 */
public record Location(
        String countryCode,
        String city,
        BigDecimal latitude,
        BigDecimal longitude) {
}
