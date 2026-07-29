package com.centinela.caseinquiry.infrastructure.config;

import com.centinela.caseinquiry.application.port.in.QueryCaseUseCase;
import com.centinela.caseinquiry.application.port.out.CaseQueryPort;
import com.centinela.caseinquiry.application.service.CaseInquiryService;
import com.centinela.scoringrecord.application.port.out.ScoringDecisionReaderPort;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Cableado de la API de consulta.
 *
 * <p>Requiere {@code centinela.scoring-record.enabled}: sin acceso al registro del motor
 * solo se podria responder por los casos abiertos, y quedaria sin respuesta la pregunta
 * mas frecuente de la demostracion — "esta transaccion normal, que score saco".
 */
@Configuration
@ConditionalOnProperty(name = "centinela.inquiry.enabled", havingValue = "true")
public class CaseInquiryConfiguration {

    @Bean
    public QueryCaseUseCase queryCaseUseCase(
            ScoringDecisionReaderPort scoringDecisionReader,
            CaseQueryPort caseQueryPort) {
        return new CaseInquiryService(scoringDecisionReader, caseQueryPort);
    }
}
