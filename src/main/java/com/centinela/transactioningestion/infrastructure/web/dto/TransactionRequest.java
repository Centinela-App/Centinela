package com.centinela.transactioningestion.infrastructure.web.dto;

import com.fasterxml.jackson.annotation.JsonAnySetter;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

/**
 * Payload de entrada de una transaccion cruda.
 */
public record TransactionRequest(
        @NotBlank String transactionId,
        @NotBlank String accountId,
        @NotNull @DecimalMin(value = "0.0", inclusive = false) BigDecimal amount,
        @NotBlank @Size(min = 3, max = 3) String currency,
        @NotNull OffsetDateTime occurredAt,
        @NotNull @Valid LocationRequest location,
        @NotNull @Valid MerchantRequest merchant) {

    /** Rechaza score, caseId y cualquier propiedad no declarada. */
    @JsonAnySetter
    public void rejectUnknownProperty(String propertyName, Object value) {
        throw new IllegalArgumentException("Unknown property: " + propertyName);
    }
}
