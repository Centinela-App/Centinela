package com.centinela.transactioningestion.infrastructure.web.dto;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class TransactionRequestValidationTest {

    private static Validator validator;

    @BeforeAll
    static void setUpValidator() {
        validator = Validation.buildDefaultValidatorFactory().getValidator();
    }

    @Test
    void acceptsTheDocumentedValidPayload() {
        assertThat(validator.validate(validRequest())).isEmpty();
    }

    @Test
    void rejectsMissingTopLevelRequiredFields() {
        TransactionRequest request = new TransactionRequest(
                " ",
                null,
                null,
                "CO",
                null,
                null,
                null);

        assertThat(pathsOf(validator.validate(request)))
                .contains("transactionId", "accountId", "amount", "currency", "occurredAt", "location", "merchant");
    }

    @Test
    void rejectsAmountThatIsNotPositive() {
        TransactionRequest request = copyWithAmount(BigDecimal.ZERO);

        assertThat(pathsOf(validator.validate(request))).contains("amount");

        TransactionRequest negativeRequest = copyWithAmount(new BigDecimal("-0.01"));
        assertThat(pathsOf(validator.validate(negativeRequest))).contains("amount");
    }

    @Test
    void rejectsCurrencyWithLengthDifferentFromThree() {
        TransactionRequest request = copyWithCurrency("CO");

        assertThat(pathsOf(validator.validate(request))).contains("currency");
    }

    @Test
    void validatesNestedRequiredFields() {
        TransactionRequest request = new TransactionRequest(
                "tx-1001",
                "acc-2001",
                new BigDecimal("125000.50"),
                "COP",
                OffsetDateTime.parse("2026-07-18T15:30:00-05:00"),
                new LocationRequest("C", " ", null, null),
                new MerchantRequest(" ", null));

        assertThat(pathsOf(validator.validate(request)))
                .contains(
                        "location.countryCode",
                        "location.city",
                        "merchant.name",
                        "merchant.category");
    }

    @Test
    void rejectsCoordinatesOutsideTheirRanges() {
        TransactionRequest request = new TransactionRequest(
                "tx-1001",
                "acc-2001",
                new BigDecimal("125000.50"),
                "COP",
                OffsetDateTime.parse("2026-07-18T15:30:00-05:00"),
                new LocationRequest("CO", "Bogota", new BigDecimal("90.1"), new BigDecimal("-180.1")),
                new MerchantRequest("Comercio de prueba", "RETAIL"));

        assertThat(pathsOf(validator.validate(request)))
                .contains("location.latitude", "location.longitude");
    }

    @Test
    void acceptsMissingOptionalCoordinates() {
        TransactionRequest request = new TransactionRequest(
                "tx-1001",
                "acc-2001",
                new BigDecimal("125000.50"),
                "COP",
                OffsetDateTime.parse("2026-07-18T15:30:00-05:00"),
                new LocationRequest("CO", "Bogota", null, null),
                new MerchantRequest("Comercio de prueba", "RETAIL"));

        assertThat(validator.validate(request)).isEmpty();
    }

    private static TransactionRequest validRequest() {
        return new TransactionRequest(
                "tx-1001",
                "acc-2001",
                new BigDecimal("125000.50"),
                "COP",
                OffsetDateTime.parse("2026-07-18T15:30:00-05:00"),
                new LocationRequest("CO", "Bogota", new BigDecimal("4.7110"), new BigDecimal("-74.0721")),
                new MerchantRequest("Comercio de prueba", "RETAIL"));
    }

    private static TransactionRequest copyWithAmount(BigDecimal amount) {
        TransactionRequest valid = validRequest();
        return new TransactionRequest(
                valid.transactionId(), valid.accountId(), amount, valid.currency(), valid.occurredAt(),
                valid.location(), valid.merchant());
    }

    private static TransactionRequest copyWithCurrency(String currency) {
        TransactionRequest valid = validRequest();
        return new TransactionRequest(
                valid.transactionId(), valid.accountId(), valid.amount(), currency, valid.occurredAt(),
                valid.location(), valid.merchant());
    }

    private static Set<String> pathsOf(Set<ConstraintViolation<TransactionRequest>> violations) {
        return violations.stream()
                .map(violation -> violation.getPropertyPath().toString())
                .collect(java.util.stream.Collectors.toSet());
    }
}
