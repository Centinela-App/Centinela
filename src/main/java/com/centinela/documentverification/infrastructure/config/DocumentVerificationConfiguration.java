package com.centinela.documentverification.infrastructure.config;

import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import com.centinela.documentverification.application.port.in.ExtractVerificationDocumentUseCase;
import com.centinela.documentverification.application.port.out.DocumentContentReaderPort;
import com.centinela.documentverification.application.port.out.IdentityDataExtractorPort;
import com.centinela.documentverification.application.port.out.VerificationDocumentRegistryPort;
import com.centinela.documentverification.application.service.ExtractVerificationDocumentService;
import com.centinela.documentverification.infrastructure.azure.blob.AzureDocumentContentReader;
import com.centinela.documentverification.infrastructure.extraction.TextualIdentityDataExtractor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

import java.time.Clock;
import java.util.Optional;

/**
 * Cableado del flujo de verificacion documental.
 *
 * <p>El motor de extraccion se resuelve por configuracion. Hoy solo existe la
 * implementacion local, que es el plan alternativo previsto en el enunciado; si la
 * suscripcion habilitara el servicio administrado de reconocimiento documental, bastaria
 * publicar otro {@link IdentityDataExtractorPort} sin tocar nada mas: la politica de
 * manejo de fallos vive en la capa de aplicacion, no en el adaptador.
 */
@Configuration
@ConditionalOnProperty(name = "centinela.document-verification.enabled", havingValue = "true")
public class DocumentVerificationConfiguration {

    @Bean
    public IdentityDataExtractorPort identityDataExtractorPort() {
        return new TextualIdentityDataExtractor();
    }

    @Bean
    @Profile("!test")
    public DocumentContentReaderPort documentContentReaderPort(
            @Value("${centinela.storage.documents.account-name}") String accountName,
            @Value("${centinela.storage.documents.container-name}") String containerName) {
        BlobContainerClient containerClient = new BlobServiceClientBuilder()
                .endpoint("https://" + accountName + ".blob.core.windows.net")
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient()
                .getBlobContainerClient(containerName);

        return new AzureDocumentContentReader(containerClient);
    }

    @Bean
    @Profile("test")
    public DocumentContentReaderPort noOpDocumentContentReaderPort() {
        return blobPath -> Optional.empty();
    }

    @Bean
    public ExtractVerificationDocumentUseCase extractVerificationDocumentUseCase(
            VerificationDocumentRegistryPort registry,
            DocumentContentReaderPort contentReader,
            IdentityDataExtractorPort extractor,
            @Value("${centinela.document-verification.batch-size:10}") int batchSize) {
        return new ExtractVerificationDocumentService(
                registry, contentReader, extractor, Clock.systemUTC(), batchSize);
    }
}
