package com.centinela.documentstorage.application.exception;

/**
 * Indica que el documento recibido no cumple las validaciones tecnicas minimas.
 */
public final class InvalidVerificationDocumentException extends RuntimeException {

    public InvalidVerificationDocumentException(String message) {
        super(message);
    }

    public InvalidVerificationDocumentException(String message, Throwable cause) {
        super(message, cause);
    }
}
