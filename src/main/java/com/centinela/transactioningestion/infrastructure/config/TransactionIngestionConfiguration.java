package com.centinela.transactioningestion.infrastructure.config;

import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import com.centinela.transactioningestion.application.port.in.IngestTransactionUseCase;
import com.centinela.transactioningestion.application.port.out.RawTransactionStoragePort;
import com.centinela.transactioningestion.application.service.IngestTransactionService;
import com.centinela.transactioningestion.infrastructure.azure.blob.AzureRawTransactionBlobAdapter;
import com.centinela.transactioningestion.infrastructure.azure.blob.BlobPathFactory;
import com.centinela.transactioningestion.infrastructure.azure.blob.RawTransactionBlobProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;

/**
 * Ensamblaje Spring de los puertos y adaptadores de ingesta.
 *
 * <p>La capa de aplicacion permanece libre de anotaciones de framework.
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
    IngestTransactionUseCase ingestTransactionUseCase(
            RawTransactionStoragePort storagePort,
            Clock transactionReceptionClock) {
        return new IngestTransactionService(storagePort, transactionReceptionClock);
    }
}
