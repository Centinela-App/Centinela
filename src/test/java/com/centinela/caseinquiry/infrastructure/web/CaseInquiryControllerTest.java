package com.centinela.caseinquiry.infrastructure.web;

import com.centinela.caseinquiry.application.port.in.QueryCaseUseCase;
import com.centinela.caseinquiry.domain.model.CaseView;
import com.centinela.caseinquiry.domain.model.VerificationDocumentView;
import com.centinela.scoringrecord.domain.model.RuleActivation;
import com.centinela.scoringrecord.domain.model.ScoringDecision;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * La distinción que estas pruebas protegen es la que hace demostrable el escenario de
 * transacción normal: <b>toda</b> transacción puntuada tiene análisis, pero solo las marcadas
 * tienen caso. Un `404` en `/cases` no es un error — es la respuesta correcta para una
 * transacción limpia, y confundirlo con un fallo haría irreproducible el control negativo.
 */
class CaseInquiryControllerTest {

    private static final String TRACEPARENT = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";

    private QueryCaseUseCase queryCase;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        queryCase = mock(QueryCaseUseCase.class);
        mockMvc = MockMvcBuilders
                .standaloneSetup(new CaseInquiryController(queryCase))
                .build();
    }

    @Test
    void returns_the_analysis_of_a_flagged_transaction_with_its_triggered_rules() throws Exception {
        when(queryCase.findAnalysis("tx-001")).thenReturn(Optional.of(new ScoringDecision(
                "tx-001", "acc-001", 82, 60, TRACEPARENT,
                List.of(new RuleActivation("velocity", "Velocidad", 35, Map.of("countInWindow", 4)),
                        new RuleActivation("geo-impossible", "Geo-Imposible", 47,
                                Map.of("distanceKm", 8000.0))))));

        mockMvc.perform(get("/api/v1/transactions/tx-001/analysis"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.transactionId").value("tx-001"))
                .andExpect(jsonPath("$.score").value(82))
                .andExpect(jsonPath("$.threshold").value(60))
                .andExpect(jsonPath("$.flagged").value(true))
                .andExpect(jsonPath("$.traceparent").value(TRACEPARENT))
                .andExpect(jsonPath("$.triggeredRules.length()").value(2))
                // Ordenadas por contribución: primero la que más pesó.
                .andExpect(jsonPath("$.triggeredRules[0].ruleId").value("geo-impossible"))
                .andExpect(jsonPath("$.triggeredRules[0].observedValues.distanceKm").value(8000.0));
    }

    @Test
    void a_clean_transaction_has_analysis_but_no_case() throws Exception {
        // El control negativo de la sustentación depende exactamente de este par de respuestas.
        when(queryCase.findAnalysis("tx-limpia")).thenReturn(Optional.of(new ScoringDecision(
                "tx-limpia", "acc-001", 0, 60, TRACEPARENT, List.of())));
        when(queryCase.findCase("tx-limpia")).thenReturn(Optional.empty());

        mockMvc.perform(get("/api/v1/transactions/tx-limpia/analysis"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.flagged").value(false))
                .andExpect(jsonPath("$.triggeredRules.length()").value(0));

        mockMvc.perform(get("/api/v1/cases/tx-limpia"))
                .andExpect(status().isNotFound());
    }

    @Test
    void returns_the_case_with_its_explanation_and_documents() throws Exception {
        when(queryCase.findCase("tx-001")).thenReturn(Optional.of(new CaseView(
                7L, "tx-001", "acc-001", new BigDecimal("82.00"), "NEW",
                "GENERATED", "Transacción marcada con score 82 (umbral: 60).", TRACEPARENT,
                Instant.parse("2026-07-29T12:00:00Z"), Instant.parse("2026-07-29T12:00:30Z"),
                List.of(new VerificationDocumentView(
                        3L, "2026/07/29/doc/cedula.pdf", "application/pdf", "EXTRACTED",
                        "MARIA LOPEZ", "1020345678", null, null, "local-textual-v1", null,
                        Instant.parse("2026-07-29T12:01:00Z"),
                        Instant.parse("2026-07-29T12:01:05Z"),
                        Instant.parse("2026-07-29T12:01:05Z"))))));

        mockMvc.perform(get("/api/v1/cases/tx-001"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.caseId").value(7))
                .andExpect(jsonPath("$.accountId").value("acc-001"))
                .andExpect(jsonPath("$.explanationState").value("GENERATED"))
                .andExpect(jsonPath("$.explanation").exists())
                .andExpect(jsonPath("$.verificationDocuments[0].state").value("EXTRACTED"))
                .andExpect(jsonPath("$.verificationDocuments[0].fullName").value("MARIA LOPEZ"));
    }

    @Test
    void a_pending_case_is_returned_with_its_state_not_as_an_empty_case() throws Exception {
        // Un caso sin explicación no es un caso incompleto: es un caso cuya explicación aún no
        // se generó. Devolver texto vacío sin decir cuál de las dos cosas ocurrió dejaría al
        // analista sin saber si debe esperar o escalar.
        when(queryCase.findCase("tx-002")).thenReturn(Optional.of(new CaseView(
                8L, "tx-002", "acc-002", new BigDecimal("75.00"), "NEW",
                "PENDING", null, TRACEPARENT,
                Instant.parse("2026-07-29T12:00:00Z"), Instant.parse("2026-07-29T12:00:00Z"),
                List.of())));

        mockMvc.perform(get("/api/v1/cases/tx-002"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.explanationState").value("PENDING"))
                .andExpect(jsonPath("$.explanation").doesNotExist());
    }

    @Test
    void an_unreadable_document_is_returned_with_its_failure_reason() throws Exception {
        // Es lo que hace cierto el requisito de que el documento quede "en estado consultable".
        when(queryCase.findCase("tx-003")).thenReturn(Optional.of(new CaseView(
                9L, "tx-003", "acc-003", new BigDecimal("80.00"), "NEW",
                "GENERATED", "Transacción marcada con score 80 (umbral: 60).", TRACEPARENT,
                Instant.parse("2026-07-29T12:00:00Z"), Instant.parse("2026-07-29T12:00:00Z"),
                List.of(new VerificationDocumentView(
                        4L, "2026/07/29/doc/corrupto.pdf", "application/pdf", "UNREADABLE",
                        null, null, null, null, "local-textual-v1",
                        "El archivo se declaro como PDF pero su contenido no lo es (firma invalida).",
                        Instant.parse("2026-07-29T12:01:00Z"),
                        Instant.parse("2026-07-29T12:01:02Z"),
                        Instant.parse("2026-07-29T12:01:02Z"))))));

        mockMvc.perform(get("/api/v1/cases/tx-003"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.verificationDocuments[0].state").value("UNREADABLE"))
                .andExpect(jsonPath("$.verificationDocuments[0].failureReason").exists())
                .andExpect(jsonPath("$.verificationDocuments[0].analystNotifiedAt").exists());
    }

    @Test
    void an_unknown_transaction_yields_not_found_on_both_resources() throws Exception {
        when(queryCase.findAnalysis(anyString())).thenReturn(Optional.empty());
        when(queryCase.findCase(anyString())).thenReturn(Optional.empty());

        mockMvc.perform(get("/api/v1/transactions/no-existe/analysis")).andExpect(status().isNotFound());
        mockMvc.perform(get("/api/v1/cases/no-existe")).andExpect(status().isNotFound());
    }
}
