package com.centinela.documentstorage.application;

import com.centinela.documentstorage.application.command.StoreVerificationDocumentCommand;
import com.centinela.documentstorage.application.exception.InvalidVerificationDocumentException;
import com.centinela.documentstorage.application.port.out.VerificationDocumentStoragePort;
import com.centinela.documentstorage.application.service.StoreVerificationDocumentService;
import com.centinela.documentstorage.domain.model.VerificationDocument;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

@ExtendWith(MockitoExtension.class)
class StoreVerificationDocumentServiceTest {

    private static final Instant RECEIVED_AT = Instant.parse("2026-07-19T01:15:00Z");

    @Mock
    private VerificationDocumentStoragePort storagePort;

    @Test
    void should_validate_and_normalize_document() {
        StoreVerificationDocumentService service = service("doc-test-1001");
        byte[] content = "synthetic-document".getBytes(StandardCharsets.UTF_8);

        String documentId = service.store(new StoreVerificationDocumentCommand(
                "../Reporte técnico 2026.pdf",
                content));

        ArgumentCaptor<VerificationDocument> documentCaptor =
                ArgumentCaptor.forClass(VerificationDocument.class);
        verify(storagePort).store(documentCaptor.capture(), org.mockito.ArgumentMatchers.eq(RECEIVED_AT));

        VerificationDocument stored = documentCaptor.getValue();
        assertEquals("doc-test-1001", documentId);
        assertEquals("doc-test-1001", stored.documentId());
        assertEquals("Reporte_t_cnico_2026.pdf", stored.storedFilename());
        assertArrayEquals(content, stored.content());
    }

    @Test
    void should_remove_windows_and_absolute_path_segments() {
        StoreVerificationDocumentService service = service("doc-test-1002");

        service.store(new StoreVerificationDocumentCommand(
                "C:\\temp\\verification\\evidence.txt",
                new byte[]{1}));

        ArgumentCaptor<VerificationDocument> documentCaptor =
                ArgumentCaptor.forClass(VerificationDocument.class);
        verify(storagePort).store(documentCaptor.capture(), org.mockito.ArgumentMatchers.eq(RECEIVED_AT));
        assertEquals("evidence.txt", documentCaptor.getValue().storedFilename());
    }

    @Test
    void should_reject_empty_document_without_calling_storage() {
        StoreVerificationDocumentService service = service("doc-test-1003");

        assertThrows(
                InvalidVerificationDocumentException.class,
                () -> service.store(new StoreVerificationDocumentCommand("report.pdf", new byte[0])));

        verify(storagePort, never()).store(
                org.mockito.ArgumentMatchers.any(),
                org.mockito.ArgumentMatchers.any());
    }

    @Test
    void should_reject_missing_or_path_only_filename_without_calling_storage() {
        StoreVerificationDocumentService service = service("doc-test-1004");

        assertThrows(
                InvalidVerificationDocumentException.class,
                () -> service.store(new StoreVerificationDocumentCommand("../", new byte[]{1})));
        assertThrows(
                InvalidVerificationDocumentException.class,
                () -> service.store(new StoreVerificationDocumentCommand("   ", new byte[]{1})));

        verify(storagePort, never()).store(
                org.mockito.ArgumentMatchers.any(),
                org.mockito.ArgumentMatchers.any());
    }

    private StoreVerificationDocumentService service(String documentId) {
        return new StoreVerificationDocumentService(
                storagePort,
                Clock.fixed(RECEIVED_AT, ZoneOffset.UTC),
                () -> documentId);
    }
}
