package com.centinela.casemanagement.infrastructure.messaging;

import com.azure.storage.queue.QueueClient;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

class AzureStorageQueueAdapterTest {
    @Test
    void deletes_with_message_id_and_pop_receipt() {
        QueueClient client = mock(QueueClient.class);
        AzureStorageQueueAdapter adapter = new AzureStorageQueueAdapter(client);

        adapter.deleteMessage("message-1", "receipt-1");

        verify(client).deleteMessage("message-1", "receipt-1");
    }

    @Test
    void refuses_delete_without_pop_receipt() {
        QueueClient client = mock(QueueClient.class);
        AzureStorageQueueAdapter adapter = new AzureStorageQueueAdapter(client);

        assertThatThrownBy(() -> adapter.deleteMessage("message-1", " "))
                .isInstanceOf(IllegalArgumentException.class);
        verifyNoInteractions(client);
    }
}
