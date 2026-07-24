package com.centinela.scoring.infrastructure.cosmos;

import com.azure.cosmos.CosmosContainer;
import com.azure.cosmos.models.CosmosQueryRequestOptions;
import com.azure.cosmos.models.FeedResponse;
import com.azure.cosmos.models.PartitionKey;
import com.azure.cosmos.util.CosmosPagedIterable;
import com.centinela.scoring.application.port.out.TransactionHistoryPort;
import com.centinela.scoring.domain.model.HistoricalTransaction;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.logging.Logger;

/**
 * Adaptador Cosmos para el historial de UNA cuenta.
 *
 * <p>La consulta fija la clave de particion ({@code accountId}) en las
 * {@link CosmosQueryRequestOptions} y NUNCA activa
 * {@code setQueryMetricsEnabled}/cross-partition: {@code CosmosQueryRequestOptions}
 * sin {@code PartitionKey} recorreria todas las particiones, lo cual esta
 * prohibido por ISS-S2-007. Registra el RU consumido de cada pagina para
 * evidenciar que la consulta toco una sola particion (TEST-S2-009).
 */
public final class CosmosTransactionHistoryAdapter implements TransactionHistoryPort {

    private static final Logger LOGGER = Logger.getLogger(CosmosTransactionHistoryAdapter.class.getName());
    private static final int DEFAULT_HISTORY_LIMIT = 50;

    private final CosmosContainer container;
    private final int historyLimit;

    public CosmosTransactionHistoryAdapter(CosmosContainer container) {
        this(container, DEFAULT_HISTORY_LIMIT);
    }

    public CosmosTransactionHistoryAdapter(CosmosContainer container, int historyLimit) {
        this.container = Objects.requireNonNull(container, "container is required");
        if (historyLimit <= 0) {
            throw new IllegalArgumentException("historyLimit must be positive");
        }
        this.historyLimit = historyLimit;
    }

    @Override
    public List<HistoricalTransaction> recentHistory(String accountId, OffsetDateTime before) {
        Objects.requireNonNull(accountId, "accountId is required");
        Objects.requireNonNull(before, "before is required");

        String query = "SELECT TOP @limit c.transactionId, c.amount, c.occurredAt, "
                + "c.location.latitude AS latitude, c.location.longitude AS longitude "
                + "FROM c WHERE c.accountId = @accountId AND c.occurredAt < @before "
                + "ORDER BY c.occurredAt DESC";

        List<com.azure.cosmos.models.SqlParameter> parameters = List.of(
                new com.azure.cosmos.models.SqlParameter("@limit", historyLimit),
                new com.azure.cosmos.models.SqlParameter("@accountId", accountId),
                new com.azure.cosmos.models.SqlParameter("@before", before.toString()));
        com.azure.cosmos.models.SqlQuerySpec querySpec =
                new com.azure.cosmos.models.SqlQuerySpec(query, parameters);

        // Clave de particion fijada: la consulta NUNCA recorre particiones ajenas.
        CosmosQueryRequestOptions options = new CosmosQueryRequestOptions()
                .setPartitionKey(new PartitionKey(accountId));

        CosmosPagedIterable<HistoryProjection> pages =
                container.queryItems(querySpec, options, HistoryProjection.class);

        List<HistoricalTransaction> history = new ArrayList<>();
        double totalRequestCharge = 0.0;
        int pageCount = 0;
        for (FeedResponse<HistoryProjection> page : pages.iterableByPage()) {
            pageCount++;
            totalRequestCharge += page.getRequestCharge();
            for (HistoryProjection item : page.getResults()) {
                history.add(item.toDomain());
            }
        }

        final double finalCharge = totalRequestCharge;
        final int finalPages = pageCount;
        LOGGER.info(String.format(
                "cosmos.singlePartitionQuery accountId=%s pages=%d requestCharge=%.2fRU results=%d",
                accountId, finalPages, finalCharge, history.size()));

        return List.copyOf(history);
    }

    /** Proyeccion JSON minima devuelta por la consulta (una sola particion). */
    static final class HistoryProjection {
        public String transactionId;
        public BigDecimal amount;
        public String occurredAt;
        public BigDecimal latitude;
        public BigDecimal longitude;

        HistoricalTransaction toDomain() {
            return new HistoricalTransaction(
                    transactionId,
                    amount,
                    OffsetDateTime.parse(occurredAt),
                    latitude,
                    longitude);
        }
    }
}