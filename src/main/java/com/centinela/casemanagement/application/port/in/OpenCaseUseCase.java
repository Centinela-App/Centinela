package com.centinela.casemanagement.application.port.in;

import com.centinela.casemanagement.domain.model.Case_;
import com.centinela.shared.event.FlaggedCaseMessage;

/** Puerto de entrada idempotente para abrir un caso desde la cola. */
public interface OpenCaseUseCase {
    Case_ openCase(FlaggedCaseMessage message);
}
