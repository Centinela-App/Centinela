package com.centinela.casemanagement.infrastructure.messaging;

import com.centinela.casemanagement.application.port.in.OpenCaseUseCase;
import com.centinela.casemanagement.domain.model.Case_;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class FlaggedCaseQueueListenerIT {

    private final ObjectMapper objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());

    @Test
    void consumes_exact_contract_and_deletes_with_pop_receipt_after_commit() {
        List<String> deletions = new ArrayList<>();
        OpenCaseUseCase useCase = message -> new Case_(1L, message.transactionId(),
                BigDecimal.valueOf(message.score()), Case_.CaseStatus.NEW,
                message.scoredAt(), message.scoredAt());
        FlaggedCaseQueueListener listener = listener(useCase, deletions);

        listener.processMessage(new FlaggedCaseQueueListener.QueueMessage(
                "message-1", validJson("tx-001"), "receipt-1"));

        assertThat(deletions).containsExactly("message-1:receipt-1");
    }

    @Test
    void keeps_message_when_database_write_fails() {
        List<String> deletions = new ArrayList<>();
        FlaggedCaseQueueListener listener = listener(message -> {
            throw new IllegalStateException("database unavailable");
        }, deletions);

        assertThatThrownBy(() -> listener.processMessage(new FlaggedCaseQueueListener.QueueMessage(
                "message-2", validJson("tx-002"), "receipt-2")))
                .isInstanceOf(IllegalStateException.class);

        assertThat(deletions).isEmpty();
    }

    @Test
    void rejects_additional_contract_fields_without_deleting_the_message() {
        List<String> deletions = new ArrayList<>();
        FlaggedCaseQueueListener listener = listener(message -> {
            throw new AssertionError("The use case must not receive an invalid contract");
        }, deletions);
        String json = validJson("tx-extra").replace("\n}", ",\n  \"reason\":\"legacy\"\n}");

        listener.processMessage(new FlaggedCaseQueueListener.QueueMessage("m-extra", json, "r-extra"));

        assertThat(deletions).isEmpty();
    }

    @Test
    void processes_backlog_messages_independently() {
        List<String> deletions = new ArrayList<>();
        List<String> transactions = new ArrayList<>();
        OpenCaseUseCase useCase = message -> {
            transactions.add(message.transactionId());
            return new Case_(Long.valueOf(transactions.size()), message.transactionId(),
                    BigDecimal.valueOf(message.score()), Case_.CaseStatus.NEW,
                    message.scoredAt(), message.scoredAt());
        };
        FlaggedCaseQueueListener listener = listener(useCase, deletions);

        listener.processMessage(new FlaggedCaseQueueListener.QueueMessage("m1", validJson("tx-1"), "r1"));
        listener.processMessage(new FlaggedCaseQueueListener.QueueMessage("m2", validJson("tx-2"), "r2"));
        listener.processMessage(new FlaggedCaseQueueListener.QueueMessage("m3", validJson("tx-3"), "r3"));

        assertThat(transactions).containsExactly("tx-1", "tx-2", "tx-3");
        assertThat(deletions).containsExactly("m1:r1", "m2:r2", "m3:r3");
    }

    private FlaggedCaseQueueListener listener(OpenCaseUseCase useCase, List<String> deletions) {
        return new FlaggedCaseQueueListener(
                useCase,
                (visibility, max) -> List.of(),
                (messageId, popReceipt) -> deletions.add(messageId + ":" + popReceipt),
                objectMapper,
                java.time.Duration.ofSeconds(30),
                java.time.Duration.ofMillis(10));
    }

    private String validJson(String transactionId) {
        return """
                {
                  "transactionId":"%s",
                  "accountId":"acc-001",
                  "score":85,
                  "triggeredRules":[{"ruleId":"VELOCITY","points":35}],
                  "occurredAt":"2026-07-25T14:59:00Z",
                  "scoredAt":"2026-07-25T15:00:00Z"
                }
                """.formatted(transactionId);
    }
}
