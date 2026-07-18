package com.centinela.shared.web;

/**
 * Respuesta de error publica y sanitizada.
 */
public record ErrorResponse(String code, String message) {
}
