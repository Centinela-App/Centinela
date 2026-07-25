package com.centinela.casemanagement.infrastructure.messaging;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * Controlador de lifecycle para el listener de cola.
 *
 * <p>Inicia el consumo de mensajes cuando la aplicación está lista
 * y lo detiene gracefulmente cuando la aplicación se cierra.
 *
 * <p>Puede deshabilitarse estableciendo:
 * <pre>
 * centinela:
 *   queue:
 *     consumer:
 *       auto-start: false
 * </pre>
 *
 * <p>Útil para pruebas y para entornos donde se prefiera iniciar
 * el consumo manualmente o mediante un Function de Azure.
 */
@Component
@ConditionalOnProperty(name = "centinela.queue.adapter", havingValue = "azure-storage-queue", matchIfMissing = true)
public class QueuePollingController {

    private static final Logger log = LoggerFactory.getLogger(QueuePollingController.class);

    private final FlaggedCaseQueueListener listener;
    private final boolean autoStart;

    public QueuePollingController(
            FlaggedCaseQueueListener listener,
            org.springframework.core.env.Environment env) {
        this.listener = listener;
        this.autoStart = Boolean.parseBoolean(
                env.getProperty("centinela.queue.consumer.auto-start", "true"));
    }

    @EventListener(ApplicationReadyEvent.class)
    public void onApplicationReady() {
        if (autoStart) {
            log.info("Starting flagged case queue consumer (auto-start enabled)");
            listener.start();
        } else {
            log.info("Flagged case queue consumer auto-start disabled, use start() to begin processing");
        }
    }

    @EventListener(org.springframework.context.event.ContextClosedEvent.class)
    public void onContextClosed() {
        log.info("Stopping flagged case queue consumer");
        listener.stop();
    }
}
