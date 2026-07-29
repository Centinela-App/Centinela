package com.centinela.casemanagement.infrastructure.messaging;

import java.time.Duration;
import java.util.Collections;
import java.util.List;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.queue.QueueClient;
import com.azure.storage.queue.QueueClientBuilder;
import com.azure.storage.queue.models.PeekedMessageItem;

/**
 * Adapter de Azure Storage Queue para leer y eliminar mensajes.
 *
 * <p>Usa Managed Identity (DefaultAzureCredential) para autenticación,
 * sin necesidad de guardar claves de acceso en configuración.
 *
 * <p>Este adapter es utilizado por {@link FlaggedCaseQueueListener}
 * para interactuar con la cola de casos flagged.
 */
@Component
@ConditionalOnProperty(name = "centinela.queue.adapter", havingValue = "azure-storage-queue", matchIfMissing = true)
public class AzureStorageQueueAdapter implements FlaggedCaseQueueListener.QueueReceiver, FlaggedCaseQueueListener.MessageDeleter {

    private static final Logger log = LoggerFactory.getLogger(AzureStorageQueueAdapter.class);

    private final QueueClient queueClient;

    /**
     * Constructor que inicializa el cliente de cola con Managed Identity.
     *
     * @param accountName nombre de la cuenta de Storage
     * @param queueName nombre de la cola (inyectado desde app settings)
     */
    @Autowired
    public AzureStorageQueueAdapter(
            @Value("${centinela.storage.blob.account-name}") String accountName,
            @Value("${centinela.queue.flagged-cases.name}") String queueName,
            @Value("${centinela.storage.queue.connection-string:}") String connectionString) {
        // Azurite por cadena de conexion en local; Managed Identity en Azure. La
        // cadena vacia (el defecto) mantiene el comportamiento de produccion intacto.
        QueueClientBuilder builder = new QueueClientBuilder().queueName(queueName);
        if (connectionString != null && !connectionString.isBlank()) {
            builder.connectionString(connectionString);
        } else {
            builder.endpoint(buildEndpoint(accountName))
                    .credential(new DefaultAzureCredentialBuilder().build());
        }
        this.queueClient = builder.buildClient();

        log.info("Azure Storage Queue adapter initialized for queue: {}", queueName);
    }

    /**
     * Constructor para pruebas con cliente inyectado.
     */
    AzureStorageQueueAdapter(QueueClient queueClient) {
        this.queueClient = queueClient;
    }

    @Override
    public List<FlaggedCaseQueueListener.QueueMessage> receiveMessages(Duration visibilityTimeout, int maxMessages) {
        try {
            // receiveMessages retorna un PagedIterable<QueueMessageItem>
            return queueClient.receiveMessages(maxMessages, visibilityTimeout, null, null)
                    .stream()
                    .map(msg -> new FlaggedCaseQueueListener.QueueMessage(
                            msg.getMessageId(),
                            msg.getMessageText(),
                            msg.getPopReceipt()))
                    .collect(Collectors.toList());

        } catch (Exception e) {
            log.error("Failed to receive messages from queue: {}", e.getMessage());
            return Collections.emptyList();
        }
    }

    @Override
    public void deleteMessage(String messageId, String popReceipt) {
        if (popReceipt == null || popReceipt.isBlank()) {
            throw new IllegalArgumentException("popReceipt is required to delete an Azure Queue message");
        }
        queueClient.deleteMessage(messageId, popReceipt);
        log.debug("Message {} deleted successfully", messageId);
    }

    private String buildEndpoint(String accountName) {
        if (accountName == null || accountName.isBlank()) {
            throw new IllegalStateException("centinela.storage.blob.account-name is required");
        }
        return String.format("https://%s.queue.core.windows.net", accountName);
    }

    /**
     * Peek messages without removing them (for monitoring/debugging).
     */
    public List<String> peekMessages(int maxMessages) {
        return queueClient.peekMessages(maxMessages, null, null).stream()
                .map(PeekedMessageItem::getMessageText)
                .collect(Collectors.toList());
    }

    /**
     * Obtiene el número de mensajes pendientes en la cola.
     */
    public int getApproximateMessageCount() {
        try {
            return (int) queueClient.getProperties().getApproximateMessagesCount();
        } catch (Exception e) {
            log.warn("Could not get message count: {}", e.getMessage());
            return -1;
        }
    }
}
