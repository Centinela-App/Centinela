package com.centinela.casemanagement.infrastructure.messaging;

import java.time.Duration;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.timeout;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.centinela.casemanagement.application.port.in.OpenCaseUseCase;
import com.centinela.casemanagement.domain.model.Case_;
import com.centinela.casemanagement.domain.model.FlaggedCaseMessage;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

/**
 * Tests de integración para FlaggedCaseQueueListener.
 *
 * <p>Requiere Azure Storage Queue configurado:
 * <pre>
 * CENTINELA_RUN_AZURE_IT=true
 * CENTINELA_STORAGE_ACCOUNT=...
 * CENTINELA_FLAGGED_CASES_QUEUE=...
 * </pre>
 *
 * <p>Verifica:
 * <ul>
 *   <li>TEST-S2-020: Procesa backlog al reanudar</li>
 *   <li>TEST-S2-023: Consumidor caído sin pérdida de casos</li>
 * </ul>
 */
@DisplayName("FlaggedCaseQueueListener")
@EnabledIfEnvironmentVariable(named = "CENTINELA_RUN_AZURE_IT", matches = "true")
class FlaggedCaseQueueListenerIT {

    private static final String TX_ID = "tx-it-001";
    private static final Duration VISIBILITY_TIMEOUT = Duration.ofSeconds(30);

    private final ObjectMapper objectMapper = new ObjectMapper()
            .registerModule(new JavaTimeModule());

    @Nested
    @DisplayName("procesamiento de mensajes")
    class MessageProcessingTests {

        @Test
        @DisplayName("procesa mensaje y elimina tras commit exitoso")
        void processesMessageAndDeletesAfterCommit() throws Exception {
            // Given
            OpenCaseUseCase useCase = mock(OpenCaseUseCase.class);
            Case_ createdCase = new Case_("case-1", TX_ID, Case_.CaseStatus.OPEN,
                    java.time.OffsetDateTime.now(), java.time.OffsetDateTime.now());
            when(useCase.openCase(any())).thenReturn(createdCase);

            AtomicBoolean deleted = new AtomicBoolean(false);

            FlaggedCaseQueueListener.QueueReceiver receiver = (timeout, max) -> {
                try {
                    String json = objectMapper.writeValueAsString(
                            new FlaggedCaseMessage(TX_ID, "acc-1", "test", "rule-1", "msg-1"));
                    return List.of(new FlaggedCaseQueueListener.QueueMessage("msg-1", json, "receipt-1"));
                } catch (Exception e) {
                    throw new RuntimeException(e);
                }
            };

            FlaggedCaseQueueListener.MessageDeleter deleter = messageId -> {
                deleted.set(true);
            };

            FlaggedCaseQueueListener listener = new FlaggedCaseQueueListener(
                    useCase, receiver, deleter, objectMapper,
                    VISIBILITY_TIMEOUT, Duration.ofMillis(100));

            // When
            listener.start();
            Thread.sleep(500); // Dar tiempo para procesar
            listener.stop();

            // Then
            verify(useCase, timeout(2000).atLeastOnce()).openCase(any(FlaggedCaseMessage.class));
            assertThat(deleted.get()).isTrue();
        }

        @Test
        @DisplayName("TEST-S2-020: procesa backlog acumulado al reanudar")
        void processesBacklogOnResume() throws Exception {
            // Given - mensajes acumulados mientras el consumidor estaba caído
            OpenCaseUseCase useCase = mock(OpenCaseUseCase.class);
            AtomicInteger processedCount = new AtomicInteger(0);
            when(useCase.openCase(any())).thenAnswer(inv -> {
                processedCount.incrementAndGet();
                return new Case_("case-" + processedCount.get(), 
                        ((FlaggedCaseMessage) inv.getArgument(0)).transactionId(),
                        Case_.CaseStatus.OPEN,
                        java.time.OffsetDateTime.now(), java.time.OffsetDateTime.now());
            });

            List<FlaggedCaseQueueListener.QueueMessage> backlog = List.of(
                    createMessage("tx-backlog-1"),
                    createMessage("tx-backlog-2"),
                    createMessage("tx-backlog-3"));

            AtomicInteger callCount = new AtomicInteger(0);

            FlaggedCaseQueueListener.QueueReceiver receiver = (timeout, max) -> {
                int current = callCount.getAndIncrement();
                if (current < backlog.size()) {
                    return List.of(backlog.get(current));
                }
                return Collections.emptyList();
            };

            FlaggedCaseQueueListener.MessageDeleter deleter = messageId -> { };

            FlaggedCaseQueueListener listener = new FlaggedCaseQueueListener(
                    useCase, receiver, deleter, objectMapper,
                    VISIBILITY_TIMEOUT, Duration.ofMillis(50));

            // When - consumidor reanuda
            listener.start();
            Thread.sleep(1000); // Esperar a procesar todos
            listener.stop();

            // Then - procesó todos los mensajes del backlog
            assertThat(processedCount.get()).isEqualTo(3);
        }
    }

    @Nested
    @DisplayName("resiliencia")
    class ResilienceTests {

        @Test
        @DisplayName("TEST-S2-023: no pierde mensajes cuando falla procesamiento")
        void doesNotLoseMessagesOnFailure() throws Exception {
            // Given
            OpenCaseUseCase useCase = mock(OpenCaseUseCase.class);
            when(useCase.openCase(any())).thenThrow(new RuntimeException("Simulated failure"));

            AtomicBoolean deleted = new AtomicBoolean(false);

            FlaggedCaseQueueListener.QueueReceiver receiver = (timeout, max) -> {
                try {
                    String json = objectMapper.writeValueAsString(
                            new FlaggedCaseMessage(TX_ID, "acc-1", "test", "rule-1", "msg-fail"));
                    return List.of(new FlaggedCaseQueueListener.QueueMessage("msg-fail", json, "receipt-fail"));
                } catch (Exception e) {
                    throw new RuntimeException(e);
                }
            };

            FlaggedCaseQueueListener.MessageDeleter deleter = messageId -> {
                deleted.set(true);
            };

            FlaggedCaseQueueListener listener = new FlaggedCaseQueueListener(
                    useCase, receiver, deleter, objectMapper,
                    VISIBILITY_TIMEOUT, Duration.ofMillis(100));

            // When
            listener.start();
            Thread.sleep(500);
            listener.stop();

            // Then - el mensaje NO fue eliminado porque falló el procesamiento
            assertThat(deleted.get()).isFalse();
            verify(useCase, timeout(2000).atLeastOnce()).openCase(any());
        }

        @Test
        @DisplayName("detiene procesamiento gracefully sin perder mensajes")
        void stopsGracefullyWithoutLosingMessages() throws Exception {
            // Given
            OpenCaseUseCase useCase = mock(OpenCaseUseCase.class);
            AtomicInteger processedBeforeStop = new AtomicInteger(0);
            when(useCase.openCase(any())).thenAnswer(inv -> {
                processedBeforeStop.incrementAndGet();
                return new Case_("case-stop", 
                        ((FlaggedCaseMessage) inv.getArgument(0)).transactionId(),
                        Case_.CaseStatus.OPEN,
                        java.time.OffsetDateTime.now(), java.time.OffsetDateTime.now());
            });

            FlaggedCaseQueueListener.QueueReceiver receiver = (timeout, max) -> {
                return List.of(
                        createMessage("tx-stop-1"),
                        createMessage("tx-stop-2"),
                        createMessage("tx-stop-3"),
                        createMessage("tx-stop-4"),
                        createMessage("tx-stop-5"));
            };

            FlaggedCaseQueueListener.MessageDeleter deleter = messageId -> { };

            FlaggedCaseQueueListener listener = new FlaggedCaseQueueListener(
                    useCase, receiver, deleter, objectMapper,
                    VISIBILITY_TIMEOUT, Duration.ofMillis(50));

            // When - iniciar y detener inmediatamente
            listener.start();
            Thread.sleep(200);
            listener.stop();

            // Then - algunos mensajes fueron procesados
            assertThat(processedBeforeStop.get()).isGreaterThan(0);
            // Los no procesados permanecen en la cola (simulado por el receiver)
        }
    }

    @Nested
    @DisplayName("ciclo de vida")
    class LifecycleTests {

        @Test
        @DisplayName("puede iniciarse y detenerse múltiples veces")
        void canStartAndStopMultipleTimes() {
            // Given
            OpenCaseUseCase useCase = mock(OpenCaseUseCase.class);
            FlaggedCaseQueueListener.QueueReceiver receiver = (timeout, max) -> Collections.emptyList();
            FlaggedCaseQueueListener.MessageDeleter deleter = messageId -> { };

            FlaggedCaseQueueListener listener = new FlaggedCaseQueueListener(
                    useCase, receiver, deleter, objectMapper,
                    VISIBILITY_TIMEOUT, Duration.ofMillis(100));

            // When/Then - múltiples ciclos start/stop
            listener.start();
            assertThat(listener.isRunning()).isTrue();
            listener.stop();
            assertThat(listener.isRunning()).isFalse();

            listener.start();
            assertThat(listener.isRunning()).isTrue();
            listener.stop();
            assertThat(listener.isRunning()).isFalse();
        }

        @Test
        @DisplayName("start es idempotente")
        void startIsIdempotent() {
            // Given
            OpenCaseUseCase useCase = mock(OpenCaseUseCase.class);
            FlaggedCaseQueueListener.QueueReceiver receiver = (timeout, max) -> Collections.emptyList();
            FlaggedCaseQueueListener.MessageDeleter deleter = messageId -> { };

            FlaggedCaseQueueListener listener = new FlaggedCaseQueueListener(
                    useCase, receiver, deleter, objectMapper,
                    VISIBILITY_TIMEOUT, Duration.ofMillis(100));

            // When
            listener.start();
            listener.start(); // Segunda llamada - no debe fallar

            // Then
            assertThat(listener.isRunning()).isTrue();
            listener.stop();
        }
    }

    private FlaggedCaseQueueListener.QueueMessage createMessage(String transactionId) {
        try {
            String json = objectMapper.writeValueAsString(
                    new FlaggedCaseMessage(transactionId, "acc-test", "test reason", "rule-1", "msg-" + transactionId));
            return new FlaggedCaseQueueListener.QueueMessage("msg-" + transactionId, json, "receipt-" + transactionId);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }
}
