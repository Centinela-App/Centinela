package com.centinela.transactioningestion.infrastructure.web;

import com.centinela.transactioningestion.application.exception.StorageUnavailableException;
import com.centinela.transactioningestion.application.port.out.RawTransactionStoragePort;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc(addFilters = false)
@ActiveProfiles("test")
class TransactionApiIT {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private RawTransactionStoragePort storagePort;

    @Test
    void should_return_202_only_after_storage_port_completes() throws Exception {
        mockMvc.perform(post("/api/v1/transactions")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validPayload()))
                .andExpect(status().isAccepted())
                .andExpect(jsonPath("$.transactionId").value("tx-api-1001"))
                .andExpect(jsonPath("$.status").value("RECEIVED"));

        verify(storagePort).store(any(), any());
    }

    @Test
    void should_return_503_when_storage_is_unavailable() throws Exception {
        doThrow(new StorageUnavailableException(
                "synthetic storage failure",
                new RuntimeException("synthetic cause")))
                .when(storagePort).store(any(), any());

        mockMvc.perform(post("/api/v1/transactions")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validPayload()))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("STORAGE_UNAVAILABLE"))
                .andExpect(jsonPath("$.message").value("Transaction storage is temporarily unavailable"))
                .andExpect(jsonPath("$.trace").doesNotExist())
                .andExpect(jsonPath("$.exception").doesNotExist());
    }

    private static String validPayload() {
        return """
                {
                  "transactionId": "tx-api-1001",
                  "accountId": "acct-api-2001",
                  "amount": 180000.75,
                  "currency": "COP",
                  "occurredAt": "2026-07-18T10:00:00-05:00",
                  "location": {
                    "countryCode": "CO",
                    "city": "Bogota"
                  },
                  "merchant": {
                    "name": "Comercio Demo",
                    "category": "RETAIL"
                  }
                }
                """;
    }
}
