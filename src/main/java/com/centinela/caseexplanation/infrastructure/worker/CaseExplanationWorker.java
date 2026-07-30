package com.centinela.caseexplanation.infrastructure.worker;

import com.centinela.caseexplanation.application.port.in.GenerateCaseExplanationUseCase;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.Objects;

/**
 * Dispara la generacion de explicaciones en segundo plano.
 *
 * <p>Solo existe cuando {@code centinela.explainer.enabled} es {@code true}. El contenedor
 * de la API lo deja apagado y el contenedor del explicador lo enciende: la misma imagen
 * cumple los dos papeles y detener el explicador se reduce a escalar su Container App a
 * cero replicas, sin tocar la API.
 *
 * <p>Un fallo del lote se registra y se abandona hasta el ciclo siguiente. Propagarlo
 * detendria la planificacion y convertiria un error transitorio — la base de datos
 * inaccesible medio segundo — en una parada permanente que exigiria reinicio manual.
 */
@Component
@ConditionalOnProperty(name = "centinela.explainer.enabled", havingValue = "true")
public class CaseExplanationWorker {

    private static final Logger log = LoggerFactory.getLogger(CaseExplanationWorker.class);

    private final GenerateCaseExplanationUseCase generateCaseExplanation;

    public CaseExplanationWorker(GenerateCaseExplanationUseCase generateCaseExplanation) {
        this.generateCaseExplanation =
                Objects.requireNonNull(generateCaseExplanation, "generateCaseExplanation is required");
        log.info("Case explanation worker enabled");
    }

    @Scheduled(
            fixedDelayString = "${centinela.explainer.poll-interval-ms:5000}",
            initialDelayString = "${centinela.explainer.initial-delay-ms:10000}")
    public void generatePendingExplanations() {
        try {
            generateCaseExplanation.generatePending();
        } catch (RuntimeException exception) {
            log.error("Explanation batch failed; will retry on next cycle", exception);
        }
    }
}
