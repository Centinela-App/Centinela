package com.centinela.transactioningestion.infrastructure.web.dto;

import com.fasterxml.jackson.annotation.JsonAnySetter;
import jakarta.validation.constraints.NotBlank;

/**
 * Datos del comercio aceptados por el contrato HTTP de Semana 1.
 */
public record MerchantRequest(
        @NotBlank String name,
        @NotBlank String category) {

    /** Rechaza propiedades futuras aunque Jackson este configurado como tolerante. */
    @JsonAnySetter
    public void rejectUnknownProperty(String propertyName, Object value) {
        throw new IllegalArgumentException("Unknown property: " + propertyName);
    }
}
