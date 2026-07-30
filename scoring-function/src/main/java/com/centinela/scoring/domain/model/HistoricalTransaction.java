package com.centinela.scoring.domain.model;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

/**
 * Proyeccion minima de una transaccion pasada de la MISMA cuenta, recuperada
 * de una sola particion de Cosmos (clave de particion {@code accountId}).
 *
 * <p>Solo contiene los campos que necesitan las reglas de dominio (ISS-S2-008):
 * no expone tipos del SDK de Cosmos ni el documento completo.
 *
 * <p>Semana 3 agrega {@code city} y {@code countryCode}. Las coordenadas bastan para
 * <i>decidir</i> que un desplazamiento es imposible, pero no para <i>explicarselo</i> a
 * un analista: "de 6.25,-75.56 a 40.41,-3.70" no es una frase util. La explicacion
 * exigida por Semana 3 nombra las ciudades, y un dato que el motor no registro no puede
 * inventarlo el explicador.
 */
public record HistoricalTransaction(
        String transactionId,
        BigDecimal amount,
        OffsetDateTime occurredAt,
        BigDecimal latitude,
        BigDecimal longitude,
        String city,
        String countryCode) {

    /**
     * Constructor heredado sin datos de localidad.
     *
     * <p>Se conserva porque las reglas que solo usan monto o tiempo no necesitan la
     * ciudad, y obligar a cada llamador a pasar {@code null} explicito no aporta nada.
     */
    public HistoricalTransaction(
            String transactionId,
            BigDecimal amount,
            OffsetDateTime occurredAt,
            BigDecimal latitude,
            BigDecimal longitude) {
        this(transactionId, amount, occurredAt, latitude, longitude, null, null);
    }
}
