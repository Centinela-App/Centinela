package com.centinela.documentstorage.infrastructure.web;

import com.centinela.documentstorage.application.exception.DocumentStorageUnavailableException;
import com.centinela.documentstorage.application.port.out.VerificationDocumentStoragePort;
import com.centinela.documentstorage.domain.model.VerificationDocument;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc(addFilters = false)
@ActiveProfiles("test")
class VerificationDocumentApiIT {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private VerificationDocumentStoragePort storagePort;

    @Test
    void should_return_201_after_storing_non_empty_document() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "verification.txt",
                "text/plain",
                "synthetic-document".getBytes(StandardCharsets.UTF_8));

        mockMvc.perform(multipart("/api/v1/verification-documents").file(file))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.documentId").isNotEmpty())
                .andExpect(jsonPath("$.status").value("STORED"))
                .andExpect(jsonPath("$.caseId").doesNotExist());

        verify(storagePort).store(any(VerificationDocument.class), any());
    }

    @Test
    void should_reject_missing_file_without_storage() throws Exception {
        mockMvc.perform(multipart("/api/v1/verification-documents"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_DOCUMENT"))
                .andExpect(jsonPath("$.message").value("Verification document is missing or invalid"));

        verifyNoInteractions(storagePort);
    }

    @Test
    void should_reject_empty_file_without_storage() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "empty.txt",
                "text/plain",
                new byte[0]);

        mockMvc.perform(multipart("/api/v1/verification-documents").file(file))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_DOCUMENT"));

        verifyNoInteractions(storagePort);
    }

    @Test
    void should_normalize_dangerous_filename_before_storage() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "../../technical evidence.txt",
                "text/plain",
                new byte[]{1, 2, 3});

        mockMvc.perform(multipart("/api/v1/verification-documents").file(file))
                .andExpect(status().isCreated());

        var captor = org.mockito.ArgumentCaptor.forClass(VerificationDocument.class);
        verify(storagePort).store(captor.capture(), any());
        assertEquals("technical_evidence.txt", captor.getValue().storedFilename());
    }

    @Test
    void should_return_503_when_document_storage_is_unavailable() throws Exception {
        doThrow(new DocumentStorageUnavailableException(
                "synthetic storage failure",
                new RuntimeException("synthetic cause")))
                .when(storagePort).store(any(), any());

        MockMultipartFile file = new MockMultipartFile(
                "file",
                "verification.txt",
                "text/plain",
                new byte[]{1});

        mockMvc.perform(multipart("/api/v1/verification-documents").file(file))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("STORAGE_UNAVAILABLE"))
                .andExpect(jsonPath("$.message").value("Document storage is temporarily unavailable"))
                .andExpect(jsonPath("$.trace").doesNotExist())
                .andExpect(jsonPath("$.exception").doesNotExist());
    }
}
