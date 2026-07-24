package com.centinela.scoring.application.exception;

/**
 * Excepcion lanzada cuando la persistencia del score falla.
 */
public final class ScorePersistenceException extends RuntimeException {

    public ScorePersistenceException(String message) {
        super(message);
    }

    public ScorePersistenceException(String message, Throwable cause) {
        super(message, cause);
    }
}
