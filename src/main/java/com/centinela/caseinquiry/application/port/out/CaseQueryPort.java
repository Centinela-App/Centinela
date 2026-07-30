package com.centinela.caseinquiry.application.port.out;

import com.centinela.caseinquiry.domain.model.CaseView;

import java.util.Optional;

/** Lectura de casos y de sus documentos adjuntos. */
public interface CaseQueryPort {

    /** @return el caso abierto para esa transaccion, o vacio si no se marco */
    Optional<CaseView> findByTransactionId(String transactionId);
}
