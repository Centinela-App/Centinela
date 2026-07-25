package com.centinela.scoring.infrastructure.blob;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class BlobRawTransactionReaderAdapterTest {
    @Test
    void derives_environment_container_from_the_contract_blob_path() {
        assertThat(BlobRawTransactionReaderAdapter.containerFrom(
                "raw-transactions-staging/2026/07/25/tx-1.json"))
                .isEqualTo("raw-transactions-staging");
    }

    @Test
    void rejects_paths_without_container_and_blob_name() {
        assertThatThrownBy(() -> BlobRawTransactionReaderAdapter.containerFrom("tx-1.json"))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
