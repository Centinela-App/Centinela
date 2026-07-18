package com.centinela.transactioningestion.infrastructure.web;

import com.centinela.shared.web.ApiExceptionHandler;
import com.centinela.transactioningestion.application.port.in.IngestTransactionUseCase;
import com.centinela.transactioningestion.infrastructure.web.mapper.TransactionWebMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.http.converter.json.MappingJackson2HttpMessageConverter;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.validation.beanvalidation.LocalValidatorFactoryBean;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class TransactionControllerValidationTest {

    private IngestTransactionUseCase useCase;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        useCase = mock(IngestTransactionUseCase.class);
        TransactionController controller = new TransactionController(useCase, new TransactionWebMapper());

        LocalValidatorFactoryBean validator = new LocalValidatorFactoryBean();
        validator.afterPropertiesSet();

        mockMvc = MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new ApiExceptionHandler())
                .setValidator(validator)
                .setMessageConverters(new MappingJackson2HttpMessageConverter())
                .build();
    }

    @Test
    void validJsonInvokesThePortAndReturnsOnlyTheContractReceipt() throws Exception {
        mockMvc.perform(post("/api/v1/transactions")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validPayload()))
                .andExpect(status().isAccepted())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(content().json("""
                        {
                          "transactionId": "tx-1001",
                          "status": "RECEIVED"
                        }
                        """, true));

        verify(useCase).ingest(org.mockito.ArgumentMatchers.argThat(command ->
                command.transaction().transactionId().equals("tx-1001")
                        && command.transaction().accountId().equals("acc-2001")));
    }

    @Test
    void missingRequiredFieldReturnsSafe400AndDoesNotInvokeThePort() throws Exception {
        String payload = validPayload().replace("\"accountId\": \"acc-2001\",", "");

        mockMvc.perform(post("/api/v1/transactions")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(payload))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_REQUEST"))
                .andExpect(jsonPath("$.message").value("Request validation failed"))
                .andExpect(jsonPath("$.trace").doesNotExist())
                .andExpect(jsonPath("$.exception").doesNotExist());

        verifyNoInteractions(useCase);
    }

    @Test
    void futureFieldReturns400AndDoesNotInvokeThePort() throws Exception {
        String payload = validPayload().replace(
                "\"merchant\": {",
                "\"score\": 95, \"merchant\": {");

        mockMvc.perform(post("/api/v1/transactions")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(payload))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_REQUEST"))
                .andExpect(jsonPath("$.message").value("Request body is malformed or contains unknown fields"))
                .andExpect(jsonPath("$.trace").doesNotExist());

        verifyNoInteractions(useCase);
    }

    @Test
    void invalidRfc3339DateReturns400AndDoesNotInvokeThePort() throws Exception {
        String payload = validPayload().replace(
                "2026-07-18T15:30:00-05:00",
                "18/07/2026 15:30");

        mockMvc.perform(post("/api/v1/transactions")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(payload))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_REQUEST"))
                .andExpect(jsonPath("$.trace").doesNotExist());

        verifyNoInteractions(useCase);
    }

    @Test
    void nonJsonContentTypeIsRejectedWithoutInvokingThePort() throws Exception {
        mockMvc.perform(post("/api/v1/transactions")
                        .contentType(MediaType.TEXT_PLAIN)
                        .content(validPayload()))
                .andExpect(status().isUnsupportedMediaType());

        verifyNoInteractions(useCase);
    }

    private static String validPayload() {
        return """
                {
                  "transactionId": "tx-1001",
                  "accountId": "acc-2001",
                  "amount": 125000.50,
                  "currency": "COP",
                  "occurredAt": "2026-07-18T15:30:00-05:00",
                  "location": {
                    "countryCode": "CO",
                    "city": "Bogota",
                    "latitude": 4.7110,
                    "longitude": -74.0721
                  },
                  "merchant": {
                    "name": "Comercio de prueba",
                    "category": "RETAIL"
                  }
                }
                """;
    }
}
