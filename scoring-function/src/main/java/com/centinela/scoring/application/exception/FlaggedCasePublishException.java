package com.centinela.scoring.application.exception;

/**
 * Excepcion lanzada cuando la publicacion del caso marcado falla.
 */
public final class FlaggedCasePublishException extends RuntimeException {

    public FlaggedCasePublishException(String message) {
        super(message);
    }

    public FlaggedCasePublishException(String message, Throwable cause) {
        super(message, cause);
    }
}
