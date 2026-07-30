package com.centinela.scoring.application.port.out;

import com.centinela.scoring.domain.model.TransactionEvent;
import com.centinela.scoring.domain.model.TransactionEventNotification;

/** Lee desde Blob el JSON crudo referenciado por {@code transaction-event-v1}. */
@FunctionalInterface
public interface RawTransactionReaderPort {
    TransactionEvent read(TransactionEventNotification notification);
}
