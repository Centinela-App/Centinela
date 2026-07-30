package com.centinela.caseexplanation.application.service;

import com.centinela.caseexplanation.application.port.in.GenerateCaseExplanationUseCase;
import com.centinela.caseexplanation.application.port.out.PendingExplanationPort;
import com.centinela.scoringrecord.application.port.out.ScoringDecisionReaderPort;
import com.centinela.caseexplanation.domain.explanation.ExplanationTemplate;
import com.centinela.scoringrecord.domain.model.ScoringDecision;
import com.centinela.shared.telemetry.PipelineStage;
import com.centinela.shared.telemetry.StageTelemetry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Clock;
import java.util.List;
import java.util.Objects;
import java.util.Optional;

/**
 * Genera las explicaciones pendientes.
 *
 * <p>Se ejecuta <b>despues</b> de que el caso existe y en un proceso aparte, de modo que
 * su latencia no entra en la ruta de la ingesta: el cliente ya recibio su acuse mucho
 * antes de que este componente toque nada.
 *
 * <p>Cada caso se procesa de forma aislada. Un caso que no se puede explicar — porque el
 * motor no registro lo suficiente — no impide explicar los demas; se contabiliza el
 * intento y se sigue. Detener el lote ante el primer fallo convertiria un caso defectuoso
 * en una parada de todo el backlog.
 */
public final class GenerateCaseExplanationService implements GenerateCaseExplanationUseCase {

    private static final Logger log = LoggerFactory.getLogger(GenerateCaseExplanationService.class);

    private final PendingExplanationPort pendingExplanationPort;
    private final ScoringDecisionReaderPort scoringDecisionReader;
    private final Clock clock;
    private final int batchSize;
    private final int maxAttempts;

    public GenerateCaseExplanationService(
            PendingExplanationPort pendingExplanationPort,
            ScoringDecisionReaderPort scoringDecisionReader,
            Clock clock,
            int batchSize,
            int maxAttempts) {
        this.pendingExplanationPort =
                Objects.requireNonNull(pendingExplanationPort, "pendingExplanationPort is required");
        this.scoringDecisionReader =
                Objects.requireNonNull(scoringDecisionReader, "scoringDecisionReader is required");
        this.clock = Objects.requireNonNull(clock, "clock is required");
        if (batchSize <= 0) throw new IllegalArgumentException("batchSize must be positive");
        if (maxAttempts <= 0) throw new IllegalArgumentException("maxAttempts must be positive");
        this.batchSize = batchSize;
        this.maxAttempts = maxAttempts;
    }

    @Override
    public int generatePending() {
        List<PendingExplanationPort.PendingCase> pending = pendingExplanationPort.findPending(batchSize);
        int generated = 0;
        for (PendingExplanationPort.PendingCase pendingCase : pending) {
            if (explain(pendingCase)) {
                generated++;
            }
        }
        if (!pending.isEmpty()) {
            log.info("explainer batch processed pending={} generated={}", pending.size(), generated);
        }
        return generated;
    }

    private boolean explain(PendingExplanationPort.PendingCase pendingCase) {
        long startedAt = StageTelemetry.startedAt();
        try {
            Optional<ScoringDecision> decision =
                    scoringDecisionReader.findByTransactionId(pendingCase.transactionId());

            if (decision.isEmpty()) {
                // El caso existe pero su decision no esta en el almacen. Puede ser una
                // lectura adelantada a la replicacion: se reintenta en el siguiente ciclo.
                String reason = "No se encontro el registro de scoring de la transaccion "
                        + pendingCase.transactionId();
                pendingExplanationPort.recordFailure(pendingCase.caseId(), maxAttempts, reason);
                StageTelemetry.failure(PipelineStage.EXPLANATION, pendingCase.transactionId(),
                        pendingCase.traceparent(), StageTelemetry.elapsedMillis(startedAt), reason);
                return false;
            }

            String explanation = ExplanationTemplate.render(decision.get());
            pendingExplanationPort.attachExplanation(pendingCase.caseId(), explanation, clock.instant());
            StageTelemetry.success(PipelineStage.EXPLANATION, pendingCase.transactionId(),
                    pendingCase.traceparent(), StageTelemetry.elapsedMillis(startedAt));
            log.info("explanation generated caseId={} transactionId={} traceparent={}",
                    pendingCase.caseId(), pendingCase.transactionId(), pendingCase.traceparent());
            return true;

        } catch (RuntimeException exception) {
            log.error("explanation failed caseId={} transactionId={} attempt={} reason={}",
                    pendingCase.caseId(), pendingCase.transactionId(),
                    pendingCase.attempts() + 1, exception.getMessage());
            pendingExplanationPort.recordFailure(pendingCase.caseId(), maxAttempts, exception.getMessage());
            StageTelemetry.failure(PipelineStage.EXPLANATION, pendingCase.transactionId(),
                    pendingCase.traceparent(), StageTelemetry.elapsedMillis(startedAt),
                    exception.getMessage());
            return false;
        }
    }
}
