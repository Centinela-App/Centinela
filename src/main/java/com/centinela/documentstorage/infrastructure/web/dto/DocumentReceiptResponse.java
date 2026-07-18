package com.centinela.documentstorage.infrastructure.web.dto;

/**
 * Acuse HTTP despues de almacenar el documento.
 */
public record DocumentReceiptResponse(String documentId, String status) {

    public static DocumentReceiptResponse stored(String documentId) {
        return new DocumentReceiptResponse(documentId, "STORED");
    }
}
