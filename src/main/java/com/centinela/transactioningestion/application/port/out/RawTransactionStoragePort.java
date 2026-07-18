package com.centinela.transactioningestion.application.port.out;

import com.centinela.transactioningestion.domain.model.Transaction;

import java.time.Instant;

/**
 * Puerto de salida para conservar una transaccion cruda.
 *
 * <p>No expone tipos del SDK de Azure ni detalles del contenedor fisico.
 */
@FunctionalInterface
public interface RawTransactionStoragePort {

    /**
     * Conserva la transaccion usando la fecha de recepcion UTC para construir
     * su ruta fisica.
     */
    void store(Transaction transaction, Instant receivedAt);
}
