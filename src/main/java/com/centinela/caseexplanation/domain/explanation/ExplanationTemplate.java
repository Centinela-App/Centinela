package com.centinela.caseexplanation.domain.explanation;

import com.centinela.scoringrecord.domain.model.RuleActivation;
import com.centinela.scoringrecord.domain.model.ScoringDecision;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.text.DecimalFormat;
import java.text.DecimalFormatSymbols;
import java.util.Locale;
import java.util.Optional;
import java.util.StringJoiner;

/**
 * Convierte el registro de una decision del motor en texto legible para el analista.
 *
 * <p><b>Determinista por construccion.</b> No hay modelo de lenguaje, ni aleatoriedad, ni
 * lectura del reloj: la misma decision produce byte a byte el mismo texto, hoy y dentro de
 * un ano. Eso importa porque la explicacion se adjunta a un caso de fraude que puede
 * acabar sustentando una decision frente a un cliente.
 *
 * <p><b>Correspondencia estricta.</b> Cada frase se construye a partir de valores que el
 * motor registro en el instante de decidir. Cuando falta un dato, la frase se degrada a
 * una formulacion mas pobre pero verdadera, en lugar de rellenarse con supuestos: si no
 * se conoce la ciudad anterior, se habla de distancia; si no se midio la cadencia habitual
 * de la cuenta, no se menciona ningun promedio. Una regla desconocida para esta plantilla
 * no se omite — se enumera con sus valores crudos, porque ocultarla falsearia el score.
 */
public final class ExplanationTemplate {

    /** Identificadores que produce el motor de scoring (ver el paquete {@code domain.rule}). */
    static final String RULE_VELOCITY = "velocity";
    static final String RULE_ATYPICAL_AMOUNT = "atypical-amount";
    static final String RULE_GEO_IMPOSSIBLE = "geo-impossible";
    static final String RULE_RISKY_MERCHANT = "risky-merchant";

    private static final Locale SPANISH = Locale.forLanguageTag("es-CO");
    private static final int MINUTES_PER_HOUR = 60;
    private static final int MINUTES_PER_DAY = 1440;

    private ExplanationTemplate() {
    }

    /**
     * Genera la explicacion completa.
     *
     * @throws InsufficientDecisionRecordException si la decision no registro ninguna regla
     *         activada. No es un fallo del explicador: un caso abierto sin reglas indica
     *         que el motor no dejo constancia de por que decidio marcarlo.
     */
    public static String render(ScoringDecision decision) {
        if (decision.triggeredRules().isEmpty()) {
            throw new InsufficientDecisionRecordException(
                    "El motor no registro ninguna regla activada para la transaccion "
                            + decision.transactionId() + ": no hay nada que explicar sin inventarlo.");
        }

        StringBuilder text = new StringBuilder();
        text.append("Transacción marcada con score ")
                .append(decision.totalScore())
                .append(" (umbral: ")
                .append(decision.threshold())
                .append(").")
                .append(System.lineSeparator());

        for (RuleActivation rule : decision.rulesByContribution()) {
            text.append(System.lineSeparator())
                    .append("- ")
                    .append(sentenceFor(rule))
                    .append(" (+")
                    .append(rule.points())
                    .append(" puntos).");
        }

        return text.toString();
    }

    private static String sentenceFor(RuleActivation rule) {
        return switch (rule.ruleId()) {
            case RULE_VELOCITY -> velocity(rule);
            case RULE_ATYPICAL_AMOUNT -> atypicalAmount(rule);
            case RULE_GEO_IMPOSSIBLE -> geoImpossible(rule);
            case RULE_RISKY_MERCHANT -> riskyMerchant(rule);
            default -> unknownRule(rule);
        };
    }

    // "Se detectaron 4 transacciones de esta cuenta en los últimos 4 minutos,
    //  cuando el promedio de la cuenta es de 1 cada 6 horas"
    private static String velocity(RuleActivation rule) {
        Optional<Long> count = rule.integer("countInWindow");
        if (count.isEmpty()) {
            return unknownRule(rule);
        }

        StringBuilder sentence = new StringBuilder("Se detectaron ")
                .append(count.get())
                .append(" transacciones de esta cuenta");

        // El lapso real de la rafaga describe mejor el hecho que la ventana configurada.
        Optional<Long> elapsed = rule.integer("elapsedMinutesInWindow").filter(minutes -> minutes > 0);
        Optional<Long> window = rule.integer("windowMinutes");
        if (elapsed.isPresent()) {
            sentence.append(" en los últimos ").append(humanizeMinutes(elapsed.get()));
        } else if (window.isPresent()) {
            sentence.append(" en una ventana de ").append(humanizeMinutes(window.get()));
        }

        rule.decimal("baselineAverageIntervalMinutes")
                .filter(interval -> interval > 0)
                .ifPresent(interval -> sentence
                        .append(", cuando el promedio histórico de la cuenta es de 1 cada ")
                        .append(humanizeMinutes(Math.round(interval))));

        rule.integer("maxAllowed").ifPresent(max -> sentence
                .append(". El máximo tolerado es de ").append(max).append(" en la ventana"));

        return sentence.toString();
    }

    // "El monto de $4.200.000 supera en 84× el promedio histórico de la cuenta ($50.000)"
    private static String atypicalAmount(RuleActivation rule) {
        Optional<Double> current = rule.decimal("currentAmount");
        Optional<Double> average = rule.decimal("averageAmount");
        if (current.isEmpty() || average.isEmpty()) {
            return unknownRule(rule);
        }

        String currency = rule.text("currency").map(code -> code + " ").orElse("");
        StringBuilder sentence = new StringBuilder("El monto de ")
                .append(currency).append(money(current.get()));

        Optional<Double> multiplier = rule.decimal("observedMultiplier").filter(value -> value > 0);
        if (multiplier.isPresent()) {
            sentence.append(" supera en ").append(multiplierText(multiplier.get()))
                    .append("× el promedio histórico de la cuenta (")
                    .append(currency).append(money(average.get())).append(")");
        } else {
            sentence.append(" supera el promedio histórico de la cuenta (")
                    .append(currency).append(money(average.get())).append(")");
        }

        rule.integer("historySampleSize").ifPresent(sample -> sentence
                .append(", calculado sobre ").append(sample).append(" transacciones previas"));

        return sentence.toString();
    }

    // "La transacción anterior de esta cuenta se originó en Medellín hace 11 minutos;
    //  esta se origina en Madrid, a 8.000 km"
    private static String geoImpossible(RuleActivation rule) {
        Optional<Double> distance = rule.decimal("distanceKm");
        Optional<Long> minutes = rule.integer("timeMinutes");
        if (distance.isEmpty() || minutes.isEmpty()) {
            return unknownRule(rule);
        }

        String previousPlace = rule.text("previousCity").orElse(null);
        String currentPlace = rule.text("currentCity").orElse(null);

        StringBuilder sentence = new StringBuilder("La transacción anterior de esta cuenta ");
        if (previousPlace != null) {
            sentence.append("se originó en ").append(previousPlace);
        } else {
            // Sin ciudad registrada la frase se vuelve mas pobre, pero sigue siendo cierta.
            sentence.append("se originó");
        }
        sentence.append(" hace ").append(humanizeMinutes(minutes.get())).append("; esta se origina ");
        if (currentPlace != null) {
            sentence.append("en ").append(currentPlace).append(", ");
        }
        sentence.append("a ").append(distanceText(distance.get())).append(" km");

        rule.decimal("calculatedSpeedKmh").ifPresent(speed -> sentence
                .append(", lo que implica un desplazamiento a ")
                .append(distanceText(speed)).append(" km/h"));

        return sentence.toString();
    }

    // "El comercio «Casino X» pertenece a la categoría «gambling», marcada como de riesgo"
    private static String riskyMerchant(RuleActivation rule) {
        Optional<String> merchant = rule.text("merchantName");
        Optional<String> category = rule.text("merchantCategory");
        Optional<String> matched = rule.text("matchedRiskFactor");
        if (merchant.isEmpty() && category.isEmpty()) {
            return unknownRule(rule);
        }

        // Se nombra exactamente el factor que disparo la regla: decir que el comercio esta
        // en lista cuando lo que coincidio fue la categoria seria una afirmacion distinta.
        boolean byMerchantName = matched.map("MERCHANT_NAME"::equals).orElse(false);
        if (byMerchantName && merchant.isPresent()) {
            return "El comercio «" + merchant.get() + "» figura en la lista de comercios de riesgo"
                    + category.map(value -> " (categoría «" + value + "»)").orElse("");
        }
        if (category.isPresent()) {
            return merchant.map(name -> "El comercio «" + name + "» pertenece a la categoría «"
                            + category.get() + "», marcada como de riesgo")
                    .orElse("La categoría «" + category.get() + "» está marcada como de riesgo");
        }
        return "El comercio «" + merchant.get() + "» figura en la lista de comercios de riesgo";
    }

    /**
     * Ultimo recurso para una regla que esta plantilla no conoce, o cuyos valores
     * esperados faltan.
     *
     * <p>Enumera literalmente lo que el motor registro. No es elegante, pero es honesto:
     * la alternativa — omitir la regla — dejaria un score que no cuadra con la suma de las
     * frases mostradas, y el analista no tendria forma de notarlo.
     */
    private static String unknownRule(RuleActivation rule) {
        String name = rule.ruleName() == null || rule.ruleName().isBlank()
                ? rule.ruleId()
                : rule.ruleName();

        if (rule.observedValues().isEmpty()) {
            return "Se activó la regla «" + name + "», sin valores registrados por el motor";
        }

        StringJoiner values = new StringJoiner(", ");
        rule.observedValues().entrySet().stream()
                .sorted(java.util.Map.Entry.comparingByKey())
                .forEach(entry -> values.add(entry.getKey() + "=" + entry.getValue()));
        return "Se activó la regla «" + name + "» con los valores registrados: " + values;
    }

    /** Convierte minutos en la unidad mas natural, sin perder exactitud. */
    static String humanizeMinutes(long minutes) {
        if (minutes < MINUTES_PER_HOUR) {
            return minutes + (minutes == 1 ? " minuto" : " minutos");
        }
        if (minutes < MINUTES_PER_DAY) {
            long hours = minutes / MINUTES_PER_HOUR;
            long remainder = minutes % MINUTES_PER_HOUR;
            String base = hours + (hours == 1 ? " hora" : " horas");
            return remainder == 0 ? base : base + " y " + remainder + (remainder == 1 ? " minuto" : " minutos");
        }
        long days = minutes / MINUTES_PER_DAY;
        long remainderHours = (minutes % MINUTES_PER_DAY) / MINUTES_PER_HOUR;
        String base = days + (days == 1 ? " día" : " días");
        return remainderHours == 0 ? base : base + " y " + remainderHours + (remainderHours == 1 ? " hora" : " horas");
    }

    private static String money(double amount) {
        return format(amount, "#,##0.##");
    }

    private static String distanceText(double value) {
        return format(value, "#,##0.#");
    }

    private static String multiplierText(double value) {
        BigDecimal rounded = BigDecimal.valueOf(value).setScale(2, RoundingMode.HALF_UP);
        return rounded.stripTrailingZeros().toPlainString();
    }

    private static String format(double value, String pattern) {
        DecimalFormatSymbols symbols = new DecimalFormatSymbols(SPANISH);
        symbols.setGroupingSeparator('.');
        symbols.setDecimalSeparator(',');
        return new DecimalFormat(pattern, symbols).format(value);
    }
}
