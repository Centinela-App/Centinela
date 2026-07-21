package com.centinela.transactioningestion.infrastructure.web;

import com.centinela.transactioningestion.application.command.IngestTransactionCommand;
import com.centinela.transactioningestion.domain.model.Transaction;
import com.centinela.transactioningestion.infrastructure.web.dto.LocationRequest;
import com.centinela.transactioningestion.infrastructure.web.dto.MerchantRequest;
import com.centinela.transactioningestion.infrastructure.web.dto.TransactionRequest;
import com.centinela.transactioningestion.infrastructure.web.mapper.TransactionWebMapper;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.Arrays;
import java.util.Set;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

class TransactionWebMapperTest {

    private final TransactionWebMapper mapper = new TransactionWebMapper();

    @Test
    void mapsOnlyApprovedRawTransactionFields() {
        TransactionRequest request = new TransactionRequest(
                "tx-1001",
                "acc-2001",
                new BigDecimal("125000.50"),
                "COP",
                OffsetDateTime.parse("2026-07-18T15:30:00-05:00"),
                new LocationRequest("CO", "Bogota", new BigDecimal("4.7110"), new BigDecimal("-74.0721")),
                new MerchantRequest("Comercio de prueba", "RETAIL"));

        IngestTransactionCommand command = mapper.toCommand(request);
        Transaction transaction = command.transaction();

        assertThat(transaction.transactionId()).isEqualTo("tx-1001");
        assertThat(transaction.accountId()).isEqualTo("acc-2001");
        assertThat(transaction.amount()).isEqualByComparingTo("125000.50");
        assertThat(transaction.currency()).isEqualTo("COP");
        assertThat(transaction.occurredAt())
                .isEqualTo(OffsetDateTime.parse("2026-07-18T15:30:00-05:00"));
        assertThat(transaction.location().countryCode()).isEqualTo("CO");
        assertThat(transaction.location().city()).isEqualTo("Bogota");
        assertThat(transaction.location().latitude()).isEqualByComparingTo("4.7110");
        assertThat(transaction.location().longitude()).isEqualByComparingTo("-74.0721");
        assertThat(transaction.merchant().name()).isEqualTo("Comercio de prueba");
        assertThat(transaction.merchant().category()).isEqualTo("RETAIL");
    }

    @Test
    void domainTransactionDoesNotContainWeekTwoFields() {
        Set<String> componentNames = Arrays.stream(Transaction.class.getRecordComponents())
                .map(component -> component.getName())
                .collect(Collectors.toSet());

        assertThat(componentNames).containsExactlyInAnyOrder(
                "transactionId", "accountId", "amount", "currency", "occurredAt", "location", "merchant");
        assertThat(componentNames).doesNotContain("score", "decision", "rules", "caseId");
    }
}
