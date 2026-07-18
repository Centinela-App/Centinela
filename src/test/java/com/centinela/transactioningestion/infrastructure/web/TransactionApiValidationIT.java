package com.centinela.transactioningestion.infrastructure.web;

import com.centinela.transactioningestion.application.port.out.RawTransactionStoragePort;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc(addFilters = false)
@ActiveProfiles("test")
class TransactionApiValidationIT {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private RawTransactionStoragePort storagePort;

    @Test
    void should_reject_invalid_payload_without_storage() throws Exception {
        String invalidPayload = """
                {
                  "transactionId": "tx-invalid-1001",
                  "accountId": "acct-2001",
                  "amount": -1,
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

        mockMvc.perform(post("/api/v1/transactions")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(invalidPayload))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_REQUEST"));

        verifyNoInteractions(storagePort);
    }

    @Test
    void should_accept_payload_without_optional_coordinates() throws Exception {
        String validPayload = """
                {
                  "transactionId": "tx-no-coordinates",
                  "accountId": "acct-2001",
                  "amount": 2000.50,
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

        mockMvc.perform(post("/api/v1/transactions")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validPayload))
                .andExpect(status().isAccepted());
    }
}
