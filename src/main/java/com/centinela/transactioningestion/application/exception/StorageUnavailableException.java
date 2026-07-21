package com.centinela.transactioningestion.application.exception;

/**
 * Indica que la transaccion no pudo conservarse por indisponibilidad tecnica
 * del almacenamiento.
 *
 * <p>La excepcion pertenece a aplicacion para que los adaptadores de entrada no
 * dependan de excepciones del SDK de Azure.
 */
public class StorageUnavailableException extends RuntimeException {

    public StorageUnavailableException(String message, Throwable cause) {
        super(message, cause);
    }
}
