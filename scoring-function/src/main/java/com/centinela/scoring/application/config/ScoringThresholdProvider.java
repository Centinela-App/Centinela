package com.centinela.scoring.application.config;

import java.util.Arrays;
import java.util.Collections;
import java.util.Set;
import java.util.function.Supplier;
import java.util.stream.Collectors;

/**
 * Proveedor de configuracion externa para el umbral de scoring y listas de riesgo.
 *
 * <p>Permite consultar dinamicamente el umbral de scoring (App Setting / Key Vault / env)
 * sin necesidad de recompilar ni redesplegar la aplicacion.
 */
public class ScoringThresholdProvider {

    public static final String SCORING_THRESHOLD_ENV = "SCORING_THRESHOLD";
    public static final String RISKY_MERCHANTS_ENV = "RISKY_MERCHANTS";
    public static final String RISKY_CATEGORIES_ENV = "RISKY_CATEGORIES";
    /**
     * El umbral por defecto es 25: el puntaje de la regla mas debil
     * (atypical-amount). La promesa del producto — verificada por el banco de
     * pruebas — es que CADA causal por si sola abre un caso; con un umbral por
     * encima de 25, un monto atipico aislado (25), una rafaga de velocidad (30)
     * o un comercio riesgoso (35) puntuarian sin marcar jamas. Se descubrio en
     * despliegue real: con el antiguo 50, los cuatro escenarios de una sola
     * regla del banco de pruebas terminaban en "NO MARCADA".
     */
    public static final int DEFAULT_THRESHOLD = 25;

    private final Supplier<Integer> thresholdSupplier;
    private final Supplier<Set<String>> riskyMerchantsSupplier;
    private final Supplier<Set<String>> riskyCategoriesSupplier;

    public ScoringThresholdProvider() {
        this(
                () -> readIntegerEnv(SCORING_THRESHOLD_ENV, DEFAULT_THRESHOLD),
                () -> readSetEnv(RISKY_MERCHANTS_ENV),
                () -> readSetEnv(RISKY_CATEGORIES_ENV)
        );
    }

    public ScoringThresholdProvider(
            Supplier<Integer> thresholdSupplier,
            Supplier<Set<String>> riskyMerchantsSupplier,
            Supplier<Set<String>> riskyCategoriesSupplier) {
        this.thresholdSupplier = thresholdSupplier != null ? thresholdSupplier : () -> DEFAULT_THRESHOLD;
        this.riskyMerchantsSupplier = riskyMerchantsSupplier != null ? riskyMerchantsSupplier : Collections::emptySet;
        this.riskyCategoriesSupplier = riskyCategoriesSupplier != null ? riskyCategoriesSupplier : Collections::emptySet;
    }

    /**
     * Obtiene el umbral de scoring en tiempo de ejecucion.
     */
    public int getThreshold() {
        return thresholdSupplier.get();
    }

    /**
     * Obtiene la lista/conjunto de comercios de riesgo en tiempo de ejecucion.
     */
    public Set<String> getRiskyMerchants() {
        return riskyMerchantsSupplier.get();
    }

    /**
     * Obtiene la lista/conjunto de categorias de riesgo en tiempo de ejecucion.
     */
    public Set<String> getRiskyCategories() {
        return riskyCategoriesSupplier.get();
    }

    private static int readIntegerEnv(String envName, int defaultValue) {
        String val = System.getenv(envName);
        if (val == null || val.isBlank()) {
            val = System.getProperty(envName);
        }
        if (val == null || val.isBlank()) {
            return defaultValue;
        }
        try {
            return Integer.parseInt(val.trim());
        } catch (NumberFormatException e) {
            return defaultValue;
        }
    }

    private static Set<String> readSetEnv(String envName) {
        String val = System.getenv(envName);
        if (val == null || val.isBlank()) {
            val = System.getProperty(envName);
        }
        if (val == null || val.isBlank()) {
            return Collections.emptySet();
        }
        return Arrays.stream(val.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .collect(Collectors.toUnmodifiableSet());
    }
}
