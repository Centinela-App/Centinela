package com.centinela.documentverification.domain.model;

import java.util.Objects;

/**
 * Resultado de intentar extraer los datos de un documento.
 *
 * <p>Es deliberadamente un valor de retorno y no una excepcion. Un documento ilegible es
 * un <b>desenlace previsto</b> del flujo, no un error del programa: modelarlo como
 * excepcion invitaria a que alguien lo dejara escapar y tumbara el procesamiento del lote,
 * que es exactamente lo que el requisito prohibe.
 */
public record ExtractionOutcome(
        DocumentState state,
        ExtractedIdentityData data,
        String failureReason,
        String engine) {

    public ExtractionOutcome {
        state = Objects.requireNonNull(state, "state is required");
        data = data == null ? ExtractedIdentityData.empty() : data;
    }

    public static ExtractionOutcome success(ExtractedIdentityData data, String engine) {
        return new ExtractionOutcome(data.resultingState(), data, null, engine);
    }

    public static ExtractionOutcome unsupportedFormat(String contentType, String engine) {
        return new ExtractionOutcome(
                DocumentState.UNSUPPORTED_FORMAT,
                ExtractedIdentityData.empty(),
                "Formato no soportado por el extractor: " + contentType,
                engine);
    }

    public static ExtractionOutcome unreadable(String reason, String engine) {
        return new ExtractionOutcome(
                DocumentState.UNREADABLE, ExtractedIdentityData.empty(), reason, engine);
    }

    public static ExtractionOutcome failed(String reason, String engine) {
        return new ExtractionOutcome(
                DocumentState.EXTRACTION_FAILED, ExtractedIdentityData.empty(), reason, engine);
    }

    /** Mensaje para el analista, en el idioma en que trabaja. */
    public String analystMessage(String blobPath) {
        return switch (state) {
            case EXTRACTED -> "El documento se procesó correctamente y sus datos quedaron adjuntos al caso.";
            case PARTIALLY_EXTRACTED -> "El documento se leyó parcialmente: algunos campos no pudieron "
                    + "extraerse y deben completarse manualmente.";
            case UNREADABLE -> "El documento cargado no es legible. Vuelva a cargarlo con mejor "
                    + "calidad o resolución.";
            case UNSUPPORTED_FORMAT -> "El formato del documento cargado no está soportado. "
                    + "Formatos admitidos: PDF, PNG, JPEG y TXT.";
            case EXTRACTION_FAILED -> "No fue posible procesar el documento por un error del sistema. "
                    + "El caso sigue abierto y el documento quedó registrado (" + blobPath + ").";
            case RECEIVED -> "El documento fue recibido y está pendiente de procesamiento.";
        };
    }
}
