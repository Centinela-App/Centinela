package com.centinela.transactioningestion.infrastructure.web.mapper;

import com.centinela.transactioningestion.application.command.IngestTransactionCommand;
import com.centinela.transactioningestion.domain.model.Location;
import com.centinela.transactioningestion.domain.model.Merchant;
import com.centinela.transactioningestion.domain.model.Transaction;
import com.centinela.transactioningestion.infrastructure.web.dto.TransactionRequest;
import org.springframework.stereotype.Component;

/**
 * Traduce el contrato HTTP a tipos internos de aplicacion y dominio.
 */
@Component
public class TransactionWebMapper {

    public IngestTransactionCommand toCommand(TransactionRequest request) {
        Location location = new Location(
                request.location().countryCode(),
                request.location().city(),
                request.location().latitude(),
                request.location().longitude());

        Merchant merchant = new Merchant(
                request.merchant().name(),
                request.merchant().category());

        Transaction transaction = new Transaction(
                request.transactionId(),
                request.accountId(),
                request.amount(),
                request.currency(),
                request.occurredAt(),
                location,
                merchant);

        return new IngestTransactionCommand(transaction);
    }
}
