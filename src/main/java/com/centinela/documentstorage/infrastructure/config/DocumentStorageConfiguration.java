package com.centinela.documentstorage.infrastructure.config;

import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import com.centinela.documentstorage.application.port.in.StoreVerificationDocumentUseCase;
import com.centinela.documentstorage.application.port.out.VerificationDocumentStoragePort;
import com.centinela.documentstorage.application.service.StoreVerificationDocumentService;
import com.centinela.documentstorage.infrastructure.azure.blob.AzureVerificationDocumentBlobAdapter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

import java.time.Clock;

/**
 * Ensamblaje Spring del flujo documental sin introducir framework en aplicacion.
 */
@Configuration
public class DocumentStorageConfiguration {

    @Bean
    @Profile("!test")
    VerificationDocumentStoragePort verificationDocumentStoragePort(
            @Value("${centinela.storage.documents.account-name}") String accountName,
            @Value("${centinela.storage.documents.container-name}") String containerName) {
        BlobContainerClient containerClient = new BlobServiceClientBuilder()
                .endpoint("https://" + accountName + ".blob.core.windows.net")
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient()
                .getBlobContainerClient(containerName);

        return new AzureVerificationDocumentBlobAdapter(containerClient);
    }

    /**
     * Adaptador no-op para pruebas de contexto. Evita inicializar el SDK de
     * Azure cuando las pruebas cargan toda la aplicacion sin usar documentos.
     * Las pruebas del endpoint reemplazan este bean con {@code @MockBean}.
     */
    @Bean
    @Profile("test")
    VerificationDocumentStoragePort noOpVerificationDocumentStoragePort() {
        return (document, receivedAt) -> {
        };
    }

    @Bean
    StoreVerificationDocumentUseCase storeVerificationDocumentUseCase(
            VerificationDocumentStoragePort storagePort) {
        return new StoreVerificationDocumentService(storagePort, Clock.systemUTC());
    }
}
