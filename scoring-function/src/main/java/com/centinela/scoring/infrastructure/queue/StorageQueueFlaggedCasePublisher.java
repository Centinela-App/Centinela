package com.centinela.scoring.infrastructure.queue;

import com.azure.core.util.BinaryData;
import com.azure.storage.queue.QueueClient;
import com.azure.storage.queue.models.SendMessageResult;
import com.centinela.scoring.application.exception.FlaggedCasePublishException;
import com.centinela.scoring.application.port.out.FlaggedCasePublisherPort;
import com.centinela.scoring.domain.model.Score;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.time.Instant;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Objects;

/** Publica exactamente el contrato {@code flagged-case-v1}, sin campos adicionales. */
public final class StorageQueueFlaggedCasePublisher implements FlaggedCasePublisherPort {
    private final QueueClient queueClient;
    private final ObjectMapper objectMapper;

    public StorageQueueFlaggedCasePublisher(QueueClient queueClient, ObjectMapper objectMapper) {
        this.queueClient = Objects.requireNonNull(queueClient, "queueClient is required");
        this.objectMapper = Objects.requireNonNull(objectMapper, "objectMapper is required");
    }

    @Override
    public void publishFlaggedCase(Score score) {
        try {
            FlaggedCasePayload payload = new FlaggedCasePayload(
                    score.transactionId(),
                    score.accountId(),
                    score.totalScore(),
                    score.triggeredRules().stream()
                            .map(hit -> new TriggeredRulePayload(hit.ruleId(), hit.points()))
                            .toList(),
                    formatTimestamp(score.occurredAt().toInstant()),
                    formatTimestamp(score.scoredAt()),
                    score.traceparent());

            SendMessageResult result = queueClient.sendMessage(
                    BinaryData.fromString(objectMapper.writeValueAsString(payload)));
            if (result == null || result.getMessageId() == null) {
                throw new FlaggedCasePublishException(
                        "Queue did not return a message ID for transaction " + score.transactionId());
            }
        } catch (JsonProcessingException exception) {
            throw new FlaggedCasePublishException(
                    "Failed to serialize flagged-case-v1 for transaction " + score.transactionId(), exception);
        } catch (FlaggedCasePublishException exception) {
            throw exception;
        } catch (RuntimeException exception) {
            throw new FlaggedCasePublishException(
                    "Failed to publish flagged-case-v1 for transaction " + score.transactionId(), exception);
        }
    }

    private static String formatTimestamp(Instant timestamp) {
        return DateTimeFormatter.ISO_INSTANT.format(timestamp);
    }

    record FlaggedCasePayload(
            String transactionId,
            String accountId,
            int score,
            List<TriggeredRulePayload> triggeredRules,
            String occurredAt,
            String scoredAt,
            String traceparent) {
    }

    record TriggeredRulePayload(String ruleId, int points) {
    }
}
