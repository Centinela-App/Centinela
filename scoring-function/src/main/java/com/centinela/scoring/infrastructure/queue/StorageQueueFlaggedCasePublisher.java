package com.centinela.scoring.infrastructure.queue;

import com.azure.core.util.BinaryData;
import com.azure.storage.queue.QueueClient;
import com.azure.storage.queue.models.SendMessageResult;
import com.centinela.scoring.application.exception.FlaggedCasePublishException;
import com.centinela.scoring.application.port.out.FlaggedCasePublisherPort;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.Score;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Adaptador Storage Queue para publicar casos marcados (flagged-case-v1).
 *
 * <p>Solo se invoca cuando el score supera el umbral configurado.
 * El mensaje sigue el esquema flagged-case-v1 definido en ISS-S2-004.
 */
public final class StorageQueueFlaggedCasePublisher implements FlaggedCasePublisherPort {

    private static final String MESSAGE_VERSION = "1.0";
    private static final String MESSAGE_TYPE = "flagged-case-v1";

    private final QueueClient queueClient;
    private final ObjectMapper objectMapper;

    public StorageQueueFlaggedCasePublisher(QueueClient queueClient, ObjectMapper objectMapper) {
        this.queueClient = queueClient;
        this.objectMapper = objectMapper.copy()
                .setSerializationInclusion(JsonInclude.Include.NON_NULL);
    }

    @Override
    public void publishFlaggedCase(Score score) {
        try {
            String messageBody = buildMessageBody(score);

            // La idempotencia a nivel de mensaje se maneja en el consumidor (ISS-S2-011)
            // usando transactionId como clave de deduplicacion
            SendMessageResult result = queueClient.sendMessage(
                    BinaryData.fromString(messageBody)
            );

            if (result == null || result.getMessageId() == null) {
                throw new FlaggedCasePublishException(
                        "Queue did not return a message ID for transaction: " + score.transactionId()
                );
            }

        } catch (JsonProcessingException e) {
            throw new FlaggedCasePublishException(
                    "Failed to serialize flagged case message for transaction: " + score.transactionId(), e
            );
        } catch (RuntimeException e) {
            throw new FlaggedCasePublishException(
                    "Failed to publish flagged case for transaction: " + score.transactionId(), e
            );
        }
    }

    /**
     * Construye el cuerpo del mensaje siguiendo el esquema flagged-case-v1.
     *
     * <p>Esquema:
     * {
     *   "messageType": "flagged-case-v1",
     *   "version": "1.0",
     *   "transactionId": "...",
     *   "accountId": "...",
     *   "score": 0,
     *   "triggeredRules": [...],
     *   "occurredAt": "...",
     *   "scoredAt": "...",
     *   "messageId": "..."
     * }
     */
    private String buildMessageBody(Score score) throws JsonProcessingException {
        Map<String, Object> message = new HashMap<>();
        message.put("messageType", MESSAGE_TYPE);
        message.put("version", MESSAGE_VERSION);
        message.put("transactionId", score.transactionId());
        message.put("accountId", score.accountId());
        message.put("score", score.totalScore());

        // Resumen de reglas activadas
        List<Map<String, Object>> triggeredRulesData = score.triggeredRules().stream()
                .map(this::ruleHitToSummary)
                .toList();
        message.put("triggeredRules", triggeredRulesData);

        // Timestamps
        // occurredAt vendria del evento original, pero aqui lo inferimos del score
        message.put("scoredAt", score.scoredAt().toString());

        // ID unico del mensaje para trazabilidad
        message.put("messageId", UUID.randomUUID().toString());

        return objectMapper.writeValueAsString(message);
    }

    /**
     * Convierte un RuleHit a un resumen para el mensaje de caso.
     * Solo incluye los campos relevantes para la apertura del caso.
     */
    private Map<String, Object> ruleHitToSummary(RuleHit ruleHit) {
        Map<String, Object> summary = new HashMap<>();
        summary.put("ruleId", ruleHit.ruleId());
        summary.put("ruleName", ruleHit.ruleName());
        summary.put("points", ruleHit.points());
        summary.put("observedValues", ruleHit.observedValues());
        return summary;
    }
}
