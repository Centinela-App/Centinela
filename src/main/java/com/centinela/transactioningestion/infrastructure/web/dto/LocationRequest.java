package com.centinela.transactioningestion.infrastructure.web.dto;

import com.fasterxml.jackson.annotation.JsonAnySetter;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;

/**
 * Datos de ubicacion aceptados por el contrato HTTP de Semana 1.
 */
public record LocationRequest(
        @NotBlank @Size(min = 2, max = 2) String countryCode,
        @NotBlank String city,
        @DecimalMin("-90.0") @DecimalMax("90.0") BigDecimal latitude,
        @DecimalMin("-180.0") @DecimalMax("180.0") BigDecimal longitude) {

    /** Rechaza propiedades futuras aunque Jackson este configurado como tolerante. */
    @JsonAnySetter
    public void rejectUnknownProperty(String propertyName, Object value) {
        throw new IllegalArgumentException("Unknown property: " + propertyName);
    }
}
