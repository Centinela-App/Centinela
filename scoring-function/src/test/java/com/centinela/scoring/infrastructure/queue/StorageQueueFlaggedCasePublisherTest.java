package com.centinela.scoring.infrastructure.queue;

import com.azure.core.util.BinaryData;
import com.azure.storage.queue.QueueClient;
import com.azure.storage.queue.models.SendMessageResult;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.Score;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class StorageQueueFlaggedCasePublisherTest {
    @Test
    void publishes_exact_flagged_case_v1_shape() throws Exception {
        QueueClient queue = mock(QueueClient.class);
        SendMessageResult result = mock(SendMessageResult.class);
        when(result.getMessageId()).thenReturn("message-1");
        when(queue.sendMessage(org.mockito.ArgumentMatchers.any(BinaryData.class))).thenReturn(result);
        ObjectMapper mapper = new ObjectMapper().registerModule(new JavaTimeModule());
        StorageQueueFlaggedCasePublisher publisher = new StorageQueueFlaggedCasePublisher(queue, mapper);
        String traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";
        Score score = new Score(
                "tx-001", "acc-001", 60, 50,
                List.of(new RuleHit("VELOCITY", "Velocidad", 60, Map.of("count", 8))),
                OffsetDateTime.parse("2026-07-25T14:59:00Z"),
                Instant.parse("2026-07-25T15:00:00Z"),
                traceparent);

        publisher.publishFlaggedCase(score);

        ArgumentCaptor<BinaryData> body = ArgumentCaptor.forClass(BinaryData.class);
        verify(queue).sendMessage(body.capture());
        JsonNode json = mapper.readTree(body.getValue().toString());
        assertThat(fieldNames(json)).containsExactlyInAnyOrder(
                "transactionId", "accountId", "score", "triggeredRules", "occurredAt", "scoredAt", "traceparent");
        assertThat(fieldNames(json.get("triggeredRules").get(0)))
                .containsExactlyInAnyOrder("ruleId", "points");
        assertThat(json.get("occurredAt").asText()).isEqualTo("2026-07-25T14:59:00Z");
        assertThat(json.get("scoredAt").asText()).isEqualTo("2026-07-25T15:00:00Z");
    }

    @Test
    void propagates_the_incoming_trace_context_unchanged() throws Exception {
        QueueClient queue = mock(QueueClient.class);
        SendMessageResult result = mock(SendMessageResult.class);
        when(result.getMessageId()).thenReturn("message-2");
        when(queue.sendMessage(org.mockito.ArgumentMatchers.any(BinaryData.class))).thenReturn(result);
        ObjectMapper mapper = new ObjectMapper().registerModule(new JavaTimeModule());
        StorageQueueFlaggedCasePublisher publisher = new StorageQueueFlaggedCasePublisher(queue, mapper);
        String traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";

        publisher.publishFlaggedCase(new Score(
                "tx-002", "acc-002", 80, 60,
                List.of(new RuleHit("GEO", "Geo", 80, Map.of("distanceKm", 8000))),
                OffsetDateTime.parse("2026-07-25T14:59:00Z"),
                Instant.parse("2026-07-25T15:00:00Z"),
                traceparent));

        ArgumentCaptor<BinaryData> body = ArgumentCaptor.forClass(BinaryData.class);
        verify(queue).sendMessage(body.capture());
        // El trace-id debe sobrevivir el salto por la cola: es lo que une el scoring con
        // la apertura del caso en una sola traza.
        assertThat(mapper.readTree(body.getValue().toString()).get("traceparent").asText())
                .isEqualTo(traceparent);
    }

    private Set<String> fieldNames(JsonNode node) {
        java.util.Set<String> names = new java.util.HashSet<>();
        node.fieldNames().forEachRemaining(names::add);
        return names;
    }
}
