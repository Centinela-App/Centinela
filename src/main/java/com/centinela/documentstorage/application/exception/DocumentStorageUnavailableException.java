package com.centinela.documentstorage.application.exception;

/**
 * Error de aplicacion para ocultar detalles del SDK o del proveedor de almacenamiento.
 */
public final class DocumentStorageUnavailableException extends RuntimeException {

    public DocumentStorageUnavailableException(String message, Throwable cause) {
        super(message, cause);
    }
}
