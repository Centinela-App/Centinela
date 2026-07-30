package com.centinela.scoring.domain.model;

import java.util.Map;
import java.util.Objects;

/**
 * Registro de una regla que fue activada durante el scoring.
 *
 * <p>Contiene el identificador de la regla, los puntos asignados,
 * y los valores observados que causaron la activacion.
 */
public final class RuleHit {

    private final String ruleId;
    private final String ruleName;
    private final int points;
    private final Map<String, Object> observedValues;

    public RuleHit(
            String ruleId,
            String ruleName,
            int points,
            Map<String, Object> observedValues) {
        this.ruleId = Objects.requireNonNull(ruleId, "ruleId is required");
        this.ruleName = Objects.requireNonNull(ruleName, "ruleName is required");
        this.points = points;
        this.observedValues = Map.copyOf(Objects.requireNonNull(observedValues, "observedValues is required"));
    }

    /**
     * Identificador unico de la regla.
     */
    public String ruleId() {
        return ruleId;
    }

    /**
     * Nombre legible de la regla.
     */
    public String ruleName() {
        return ruleName;
    }

    /**
     * Puntos asignados por esta regla.
     */
    public int points() {
        return points;
    }

    /**
     * Valores observados que causaron la activacion de la regla.
     * Incluye contexto necesario para el explicador (Semana 3).
     */
    public Map<String, Object> observedValues() {
        return observedValues;
    }
}
