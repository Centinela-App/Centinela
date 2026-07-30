package com.centinela.caseinquiry.application.service;

import com.centinela.caseinquiry.application.port.in.QueryCaseUseCase;
import com.centinela.caseinquiry.application.port.out.CaseQueryPort;
import com.centinela.caseinquiry.domain.model.CaseView;
import com.centinela.scoringrecord.application.port.out.ScoringDecisionReaderPort;
import com.centinela.scoringrecord.domain.model.ScoringDecision;

import java.util.Objects;
import java.util.Optional;

/**
 * Responde consultas de solo lectura sobre el resultado del analisis.
 *
 * <p>No calcula ni corrige nada: cada respuesta es lo que quedo registrado en el momento de
 * la decision. Recalcular aqui produciria respuestas que cambian con el tiempo — el umbral
 * es configurable en caliente — y haria imposible auditar por que se abrio un caso.
 */
public final class CaseInquiryService implements QueryCaseUseCase {

    private final ScoringDecisionReaderPort scoringDecisionReader;
    private final CaseQueryPort caseQueryPort;

    public CaseInquiryService(
            ScoringDecisionReaderPort scoringDecisionReader,
            CaseQueryPort caseQueryPort) {
        this.scoringDecisionReader =
                Objects.requireNonNull(scoringDecisionReader, "scoringDecisionReader is required");
        this.caseQueryPort = Objects.requireNonNull(caseQueryPort, "caseQueryPort is required");
    }

    @Override
    public Optional<ScoringDecision> findAnalysis(String transactionId) {
        return requireIdentifier(transactionId)
                .flatMap(scoringDecisionReader::findByTransactionId);
    }

    @Override
    public Optional<CaseView> findCase(String transactionId) {
        return requireIdentifier(transactionId)
                .flatMap(caseQueryPort::findByTransactionId);
    }

    private static Optional<String> requireIdentifier(String transactionId) {
        return Optional.ofNullable(transactionId)
                .map(String::trim)
                .filter(value -> !value.isEmpty());
    }
}
