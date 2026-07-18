package com.centinela.transactioningestion.application.command;

import com.centinela.transactioningestion.domain.model.Transaction;

import java.util.Objects;

/**
 * Comando de entrada para conservar una transaccion cruda.
 */
public record IngestTransactionCommand(Transaction transaction) {

    public IngestTransactionCommand {
        Objects.requireNonNull(transaction, "transaction is required");
    }
}
