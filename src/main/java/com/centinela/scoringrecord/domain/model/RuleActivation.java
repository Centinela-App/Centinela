package com.centinela.scoringrecord.domain.model;

import java.util.Map;
import java.util.Objects;
import java.util.Optional;

/**
 * Una regla que efectivamente se activo, con los valores que la activaron.
 *
 * <p>Es la lectura de lo que el motor de scoring persistio en el momento de decidir. El
 * explicador <b>no puede anadir nada</b> a esto: si un dato no esta en
 * {@code observedValues}, no existe frase que pueda afirmarlo.
 *
 * <p>Los accesores tipados devuelven {@link Optional} en lugar de valores por defecto a
 * proposito. Un cero por defecto se convertiria en una afirmacion falsa dentro de la
 * explicacion ("supera en 0x el promedio"), que es peor que no decir nada.
 */
public record RuleActivation(
        String ruleId,
        String ruleName,
        int points,
        Map<String, Object> observedValues) {

    public RuleActivation {
        ruleId = Objects.requireNonNull(ruleId, "ruleId is required");
        observedValues = Map.copyOf(Objects.requireNonNull(observedValues, "observedValues is required"));
    }

    public Optional<Number> number(String key) {
        Object value = observedValues.get(key);
        if (value instanceof Number number) {
            return Optional.of(number);
        }
        if (value instanceof String text) {
            try {
                return Optional.of(Double.valueOf(text));
            } catch (NumberFormatException ignored) {
                return Optional.empty();
            }
        }
        return Optional.empty();
    }

    public Optional<Double> decimal(String key) {
        return number(key).map(Number::doubleValue);
    }

    public Optional<Long> integer(String key) {
        return number(key).map(Number::longValue);
    }

    public Optional<String> text(String key) {
        Object value = observedValues.get(key);
        if (value instanceof String string && !string.isBlank()) {
            return Optional.of(string);
        }
        return Optional.empty();
    }

    /** {@code true} si todas las claves indicadas existen con valor utilizable. */
    public boolean has(String... keys) {
        for (String key : keys) {
            Object value = observedValues.get(key);
            if (value == null || (value instanceof String string && string.isBlank())) {
                return false;
            }
        }
        return true;
    }
}
