package com.centinela.transactioningestion.infrastructure.config;

import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.eventgrid.EventGridEvent;
import com.azure.messaging.eventgrid.EventGridPublisherClient;
import com.azure.messaging.eventgrid.EventGridPublisherClientBuilder;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import com.centinela.transactioningestion.application.port.in.IngestTransactionUseCase;
import com.centinela.transactioningestion.application.port.out.RawTransactionStoragePort;
import com.centinela.transactioningestion.application.port.out.TransactionEventPublisherPort;
import com.centinela.transactioningestion.application.service.IngestTransactionService;
import com.centinela.transactioningestion.infrastructure.azure.blob.AzureRawTransactionBlobAdapter;
import com.centinela.transactioningestion.infrastructure.azure.blob.BlobPathFactory;
import com.centinela.transactioningestion.infrastructure.azure.blob.RawTransactionBlobProperties;
import com.centinela.transactioningestion.infrastructure.messaging.EventGridTransactionEventPublisher;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

import java.time.Clock;

/**
 * Ensamblaje Spring de los puertos y adaptadores de ingesta.
 *
 * <p>La capa de aplicacion permanece libre de anotaciones de framework.
 *
 * <p>El publicador del evento se resuelve por perfil: en produccion es el adaptador
 * de Event Grid con Managed Identity; bajo el perfil {@code test} es un no-op para
 * arrancar el contexto sin conectarse a Azure (igual que el resto de clientes cloud).
 */
@Configuration
@EnableConfigurationProperties(RawTransactionBlobProperties.class)
public class TransactionIngestionConfiguration {

    @Bean
    Clock transactionReceptionClock() {
        return Clock.systemUTC();
    }

    @Bean
    BlobPathFactory blobPathFactory() {
        return new BlobPathFactory();
    }

    @Bean
    BlobContainerClient rawTransactionBlobContainerClient(RawTransactionBlobProperties properties) {
        return new BlobServiceClientBuilder()
                .endpoint(properties.endpoint())
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient()
                .getBlobContainerClient(properties.containerName());
    }

    @Bean
    RawTransactionStoragePort rawTransactionStoragePort(
            BlobContainerClient rawTransactionBlobContainerClient,
            ObjectMapper objectMapper,
            BlobPathFactory blobPathFactory) {
        return new AzureRawTransactionBlobAdapter(
                rawTransactionBlobContainerClient,
                objectMapper,
                blobPathFactory);
    }

    @Bean
    @Profile("!test")
    EventGridPublisherClient<EventGridEvent> transactionEventGridClient(
            @Value("${centinela.messaging.eventgrid.topic-endpoint}") String topicEndpoint) {
        return new EventGridPublisherClientBuilder()
                .endpoint(topicEndpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildEventGridEventPublisherClient();
    }

    @Bean
    @Profile("!test")
    TransactionEventPublisherPort transactionEventPublisherPort(
            EventGridPublisherClient<EventGridEvent> transactionEventGridClient,
            RawTransactionBlobProperties properties) {
        return new EventGridTransactionEventPublisher(
                transactionEventGridClient,
                properties.containerName());
    }

    /**
     * Publicador no-op para el perfil de prueba: el contexto arranca sin endpoint de
     * Event Grid y las pruebas de pipeline real viven en issues posteriores (E2E).
     */
    @Bean
    @Profile("test")
    TransactionEventPublisherPort noOpTransactionEventPublisherPort() {
        return (transaction, receivedAt) -> {
        };
    }

    @Bean
    IngestTransactionUseCase ingestTransactionUseCase(
            RawTransactionStoragePort storagePort,
            TransactionEventPublisherPort transactionEventPublisherPort,
            Clock transactionReceptionClock) {
        return new IngestTransactionService(
                storagePort,
                transactionEventPublisherPort,
                transactionReceptionClock);
    }
}
