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
    @Profile("!test")
    BlobContainerClient rawTransactionBlobContainerClient(RawTransactionBlobProperties properties) {
        // Dos caminos y solo dos: Azurite por cadena de conexion (perfil local) o Azure
        // por Managed Identity. No hay tercer camino con credenciales reales en
        // configuracion, y la bifurcacion explicita lo hace auditable de un vistazo.
        BlobServiceClientBuilder builder = new BlobServiceClientBuilder();
        if (properties.usesConnectionString()) {
            builder.connectionString(properties.connectionString());
        } else {
            builder.endpoint(properties.endpoint())
                    .credential(new DefaultAzureCredentialBuilder().build());
        }
        return builder.buildClient().getBlobContainerClient(properties.containerName());
    }

    @Bean
    @Profile("!test")
    RawTransactionStoragePort rawTransactionStoragePort(
            BlobContainerClient rawTransactionBlobContainerClient,
            ObjectMapper objectMapper,
            BlobPathFactory blobPathFactory) {
        return new AzureRawTransactionBlobAdapter(
                rawTransactionBlobContainerClient,
                objectMapper,
                blobPathFactory);
    }

    /**
     * Adaptador no-op para pruebas de contexto. Evita construir clientes Azure
     * cuando otro flujo carga toda la aplicacion y no necesita Blob Storage.
     * Las pruebas del endpoint reemplazan este bean con {@code @MockBean}.
     */
    @Bean
    @Profile("test")
    RawTransactionStoragePort noOpRawTransactionStoragePort() {
        return (transaction, receivedAt) -> {
        };
    }

    @Bean
    @Profile("!test & !local")
    EventGridPublisherClient<EventGridEvent> transactionEventGridClient(
            @Value("${centinela.messaging.eventgrid.topic-endpoint}") String topicEndpoint) {
        return new EventGridPublisherClientBuilder()
                .endpoint(topicEndpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildEventGridEventPublisherClient();
    }

    @Bean
    @Profile("!test & !local")
    TransactionEventPublisherPort transactionEventPublisherPort(
            EventGridPublisherClient<EventGridEvent> transactionEventGridClient,
            RawTransactionBlobProperties properties) {
        return new EventGridTransactionEventPublisher(
                transactionEventGridClient,
                properties.containerName());
    }

    /**
     * Publicador del perfil {@code local}: registra el evento en el log en lugar de
     * publicarlo, porque <b>no existe emulador local de Event Grid</b>. El salto
     * API&nbsp;&rarr;&nbsp;motor se cubre en local con
     * {@code scripts/local/simulate-scoring.sh}, que hace lo que el motor haria:
     * escribe el registro de scoring y encola el caso.
     *
     * <p>Es un log-and-continue y no un no-op silencioso a proposito: quien mire el log
     * local debe ver que el evento existio y que su continuacion es manual. Un no-op
     * mudo haria creer que el pipeline completo funciona en local, y no es verdad.
     */
    @Bean
    @Profile("local")
    TransactionEventPublisherPort localLoggingEventPublisher() {
        org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger("centinela.local.eventgrid");
        return (transaction, receivedAt) -> log.info(
                "LOCAL: transaction-event-v1 NO publicado (sin Event Grid local). "
                        + "transactionId={} accountId={}. Para continuar el flujo: "
                        + "scripts/local/simulate-scoring.sh {}",
                transaction.transactionId(), transaction.accountId(), transaction.transactionId());
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
