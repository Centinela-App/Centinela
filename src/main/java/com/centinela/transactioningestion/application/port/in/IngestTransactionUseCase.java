package com.centinela.transactioningestion.application.port.in;

import com.centinela.transactioningestion.application.command.IngestTransactionCommand;

/**
 * Puerto de entrada de la ingesta de transacciones.
 *
 * <p>La implementacion real y la persistencia Blob se agregan en ISS-S1-008.
 */
@FunctionalInterface
public interface IngestTransactionUseCase {

    /**
     * Procesa una transaccion valida.
     *
     * <p>El metodo solo termina normalmente cuando el caso de uso confirma su
     * trabajo. En ISS-S1-008 eso significara que Blob confirmo la escritura.
     */
    void ingest(IngestTransactionCommand command);
}
