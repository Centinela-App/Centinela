package com.centinela.caseexplanation.infrastructure.config;

import com.centinela.caseexplanation.application.port.in.GenerateCaseExplanationUseCase;
import com.centinela.caseexplanation.application.port.out.PendingExplanationPort;
import com.centinela.caseexplanation.application.service.GenerateCaseExplanationService;
import com.centinela.scoringrecord.application.port.out.ScoringDecisionReaderPort;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;

/**
 * Cableado del explicador.
 *
 * <p>Inactivo salvo que {@code centinela.explainer.enabled} sea {@code true}. El
 * contenedor de la API lo deja apagado y el del explicador lo enciende: la misma imagen
 * cumple los dos papeles, y "detener el explicador" —el escenario de fallo obligatorio de
 * la sustentacion— se reduce a escalar su Container App a cero replicas sin tocar la API.
 *
 * <p>El acceso al registro de scoring lo provee {@code ScoringRecordConfiguration}, que
 * debe estar activo tambien en este contenedor.
 */
// @EnableScheduling NO va aqui: vivio aqui y produjo un bug silencioso — con el
// explicador apagado, el worker de extraccion documental quedaba sin planificador.
// La capacidad de planificar es de la aplicacion (SchedulingConfiguration).
@Configuration
@ConditionalOnProperty(name = "centinela.explainer.enabled", havingValue = "true")
public class CaseExplanationConfiguration {

    @Bean
    public GenerateCaseExplanationUseCase generateCaseExplanationUseCase(
            PendingExplanationPort pendingExplanationPort,
            ScoringDecisionReaderPort scoringDecisionReader,
            @Value("${centinela.explainer.batch-size:25}") int batchSize,
            @Value("${centinela.explainer.max-attempts:5}") int maxAttempts) {
        return new GenerateCaseExplanationService(
                pendingExplanationPort, scoringDecisionReader, Clock.systemUTC(), batchSize, maxAttempts);
    }
}
