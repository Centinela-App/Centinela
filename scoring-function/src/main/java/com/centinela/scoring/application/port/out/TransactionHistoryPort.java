package com.centinela.scoring.application.port.out;

import com.centinela.scoring.domain.model.HistoricalTransaction;

import java.time.OffsetDateTime;
import java.util.List;

/**
 * Puerto de salida para leer el historial reciente de UNA cuenta.
 *
 * <p>La implementacion debe consultar Cosmos usando {@code accountId} como
 * clave de particion exclusivamente (sin recorrer particiones ajenas). No
 * expone tipos del SDK de Cosmos.
 */
@FunctionalInterface
public interface TransactionHistoryPort {

    /**
     * Recupera las transacciones de {@code accountId} anteriores a
     * {@code before}, dentro de una unica particion.
     */
    List<HistoricalTransaction> recentHistory(String accountId, OffsetDateTime before);
}
