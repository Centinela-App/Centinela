package com.centinela.casemanagement.infrastructure.messaging;

import java.time.Duration;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import com.centinela.casemanagement.application.port.in.OpenCaseUseCase;
import com.centinela.casemanagement.domain.model.Case_;
import com.centinela.shared.event.FlaggedCaseMessage;
import com.centinela.shared.telemetry.PipelineStage;
import com.centinela.shared.telemetry.StageTelemetry;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Listener de la cola de casos flagged.
 *
 * <p>Este componente lee mensajes de Azure Storage Queue usando Managed Identity
 * y los procesa mediante el caso de uso OpenCaseUseCase.
 *
 * <p>Características:
 * <ul>
 *   <li>Idempotencia: el caso de uso garantiza que no se crean casos duplicados</li>
 *   <li>Eliminación del mensaje solo tras confirmar el commit de la transacción</li>
 *   <li>Procesa el backlog acumulado si el consumidor estuvo detenido</li>
 *   <li>Puede detenerse y reanudarse para pruebas de desacoplamiento</li>
 * </ul>
 *
 * <p>Puede ejecutarse como:
 * <ul>
 *   <li>Worker dentro del App Service (Spring @Component)</li>
 *   <li>Azure Function con Queue Trigger (despliegue alternativo documentado)</li>
 * </ul>
 *
 * <p>Configuración de aplicación.yml:
 * <pre>
 * centinela:
 *   queue:
 *     flagged-cases:
 *       name: ${CENTINELA_FLAGGED_CASES_QUEUE}
 *       visibility-timeout: PT30S
 *       poll-interval: PT5S
 * </pre>
 */
@Component
@ConditionalOnProperty(name = "centinela.queue.adapter", havingValue = "azure-storage-queue", matchIfMissing = true)
public class FlaggedCaseQueueListener {

    private static final Logger log = LoggerFactory.getLogger(FlaggedCaseQueueListener.class);

    private final OpenCaseUseCase openCaseUseCase;
    private final QueueReceiver queueReceiver;
    private final MessageDeleter messageDeleter;
    private final ObjectMapper objectMapper;
    private final Duration visibilityTimeout;
    private final Duration pollInterval;

    private final AtomicBoolean running = new AtomicBoolean(false);
    private volatile Thread pollingThread;

    /**
     * Constructor principal para inyección de dependencias.
     */
    @Autowired
    public FlaggedCaseQueueListener(
            OpenCaseUseCase openCaseUseCase,
            QueueReceiver queueReceiver,
            MessageDeleter messageDeleter,
            ObjectMapper objectMapper,
            @Value("${centinela.queue.flagged-cases.visibility-timeout:PT30S}") Duration visibilityTimeout,
            @Value("${centinela.queue.flagged-cases.poll-interval:PT5S}") Duration pollInterval) {
        this.openCaseUseCase = openCaseUseCase;
        this.queueReceiver = queueReceiver;
        this.messageDeleter = messageDeleter;
        this.objectMapper = objectMapper.copy()
                .enable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
        this.visibilityTimeout = visibilityTimeout;
        this.pollInterval = pollInterval;
    }

    /**
     * Constructor simplificado para pruebas.
     */
    FlaggedCaseQueueListener(
            OpenCaseUseCase openCaseUseCase,
            ObjectMapper objectMapper) {
        this(openCaseUseCase,
                (Duration visibilityTimeout, int maxMessages) -> { throw new UnsupportedOperationException("No-op in test constructor"); },
                (messageId, popReceipt) -> { throw new UnsupportedOperationException("No-op in test constructor"); },
                objectMapper,
                Duration.ofSeconds(30),
                Duration.ofSeconds(5));
    }

    /**
     * Inicia el procesamiento de mensajes de la cola.
     *
     * <p>Este método es idempotente: si ya está en ejecución, no hace nada.
     * El procesamiento se ejecuta en un hilo separado y puede detenerse
     * mediante {@link #stop()}.
     */
    public synchronized void start() {
        if (running.get()) {
            log.warn("Consumer is already running");
            return;
        }

        running.set(true);
        pollingThread = new Thread(this::pollLoop, "flagged-case-queue-consumer");
        pollingThread.setDaemon(true);
        pollingThread.start();
        log.info("Flagged case queue consumer started");
    }

    /**
     * Detiene el procesamiento de mensajes.
     *
     * <p>Espera a que termine el procesamiento del mensaje actual (con timeout)
     * antes de detenerse. Los mensajes no procesados permanecen en la cola
     * y se procesarán al reanudar.
     */
    public synchronized void stop() {
        if (!running.get()) {
            log.warn("Consumer is not running");
            return;
        }

        running.set(false);

        if (pollingThread != null) {
            pollingThread.interrupt();
            try {
                pollingThread.join(Duration.ofSeconds(10).toMillis());
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                log.warn("Interrupted while waiting for polling thread to stop");
            }
        }

        log.info("Flagged case queue consumer stopped");
    }

    /**
     * Indica si el consumidor está actualmente en ejecución.
     *
     * @return true si está ejecutándose, false en caso contrario
     */
    public boolean isRunning() {
        return running.get();
    }

    /**
     * Bucle principal de polling de la cola.
     *
     * <p>Prosigue continuamente mientras {@link #running} sea true,
     * extrayendo y procesando mensajes en lotes.
     */
    private void pollLoop() {
        while (running.get() && !Thread.currentThread().isInterrupted()) {
            try {
                processAvailableMessages();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                log.info("Polling loop interrupted");
                break;
            } catch (Exception e) {
                log.error("Error in polling loop, will retry after interval", e);
                sleep(pollInterval);
            }
        }
    }

    /**
     * Procesa todos los mensajes disponibles en la cola.
     *
     * <p>Extrae mensajes en lotes y los procesa individualmente.
     * Cada mensaje se procesa completamente (caso creado + auditoría + commit)
     * antes de eliminarlo de la cola.
     */
    private void processAvailableMessages() throws InterruptedException {
        List<QueueMessage> messages = queueReceiver.receiveMessages(visibilityTimeout, 10);

        if (messages.isEmpty()) {
            sleep(pollInterval);
            return;
        }

        log.debug("Processing {} messages from queue", messages.size());

        for (QueueMessage message : messages) {
            if (!running.get()) {
                // Se solicitó parada; no procesar más mensajes
                // Los mensajes no procesados permanecerán invisibles y volverán a estar disponibles
                log.info("Stop requested, leaving {} messages for next run", messages.size());
                break;
            }

            processMessage(message);
        }
    }

    /**
     * Procesa un mensaje individual de la cola.
     *
     * <p>El flujo es:
     * <ol>
     *   <li>Deserializar el mensaje JSON a {@link FlaggedCaseMessage}</li>
     *   <li>Llamar a {@link OpenCaseUseCase#openCase(FlaggedCaseMessage)}</li>
     *   <li>Eliminar el mensaje de la cola SOLO tras confirmar la escritura</li>
     * </ol>
     *
     * <p>Si el procesamiento falla, el mensaje permanece invisible y
     * se reintentará automáticamente tras el visibility timeout.
     *
     * @param message el mensaje de la cola a procesar
     */
    void processMessage(QueueMessage message) {
        String messageId = message.messageId();
        FlaggedCaseMessage flaggedMessage;

        try {
            flaggedMessage = deserializeMessage(message.content());
        } catch (Exception e) {
            log.error("Failed to deserialize message {}: {}", messageId, e.getMessage());
            // Mensaje no procesable - mover a dead letter (opcional, documentado)
            handlePoisonMessage(messageId);
            return;
        }

        long startedAt = StageTelemetry.startedAt();
        try {
            // Procesar el mensaje - crea caso + auditoría (en transacción)
            Case_ createdCase = openCaseUseCase.openCase(flaggedMessage);
            log.info("Case {} created for transaction {}", createdCase.caseId(), flaggedMessage.transactionId());

            // Eliminar mensaje SOLO tras confirmar la escritura
            messageDeleter.deleteMessage(messageId, message.popReceipt());
            log.debug("Message {} deleted from queue after successful commit", messageId);

            // El traceparent viene dentro del mensaje: es lo que une esta etapa con la
            // ingesta y el scoring bajo una sola traza pese al salto asincrono.
            StageTelemetry.success(PipelineStage.CASE_OPEN, flaggedMessage.transactionId(),
                    flaggedMessage.traceparent(), StageTelemetry.elapsedMillis(startedAt));

        } catch (Exception e) {
            StageTelemetry.failure(PipelineStage.CASE_OPEN, flaggedMessage.transactionId(),
                    flaggedMessage.traceparent(), StageTelemetry.elapsedMillis(startedAt), e.getMessage());
            log.error("Failed to process message {} for transaction {}: {}",
                    messageId, flaggedMessage.transactionId(), e.getMessage());
            // No eliminar el mensaje - se reintentará automáticamente
            // El caso de uso es idempotente, así que los reintentos son seguros
            throw e;
        }
    }

    private FlaggedCaseMessage deserializeMessage(String json) throws JsonProcessingException {
        return objectMapper.readValue(json, FlaggedCaseMessage.class);
    }

    private void handlePoisonMessage(String messageId) {
        // Documentación: implementar manejo de mensajes problemáticos
        // Opciones:
        // 1. Mover a cola de dead-letter configurada en Storage Queue
        // 2. Registrar en tabla de auditoría de mensajes fallidos
        // 3. Enviar alerta a ops
        log.warn("Poison message {} will be left for retry", messageId);
    }

    private void sleep(Duration duration) {
        try {
            Thread.sleep(duration.toMillis());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    // ========== Interfaces internas para inyección y pruebas ==========

    /**
     * Interfaz para recibir mensajes de la cola.
     * Permite inyectar un adapter real o mock en pruebas.
     */
    @FunctionalInterface
    public interface QueueReceiver {
        List<QueueMessage> receiveMessages(Duration visibilityTimeout, int maxMessages);
    }

    /**
     * Interfaz para eliminar mensajes de la cola.
     * Permite inyectar un adapter real o mock en pruebas.
     */
    @FunctionalInterface
    public interface MessageDeleter {
        void deleteMessage(String messageId, String popReceipt);
    }

    /**
     * Representa un mensaje recibido de la cola.
     *
     * @param messageId ID del mensaje en la cola
     * @param content contenido JSON del mensaje
     * @param popReceipt token para eliminar el mensaje
     */
    public record QueueMessage(
            String messageId,
            String content,
            String popReceipt) {
    }
}
