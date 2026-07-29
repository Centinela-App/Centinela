package com.centinela.documentverification.domain.model;

/**
 * Estado de un documento de verificacion dentro del flujo de escalamiento de casos.
 *
 * <p>El requisito es que un documento ilegible, incompleto, corrupto o de formato
 * inesperado <b>no interrumpa el flujo ni deje el caso en estado indeterminado</b>. Por
 * eso el fracaso de la extraccion no es la ausencia de un dato: es un estado explicito,
 * consultable por el analista, que distingue <i>que</i> salio mal. "No se pudo leer" y
 * "el formato no esta soportado" exigen acciones distintas de quien recibe la
 * notificacion.
 */
public enum DocumentState {

    /** Cargado y a la espera de extraccion. Estado inicial. */
    RECEIVED,

    /** Extraccion completa: nombre, numero de identificacion y fechas. */
    EXTRACTED,

    /**
     * Se leyo el documento pero faltan campos obligatorios. El caso recibe lo que si se
     * pudo extraer; el analista completa el resto manualmente.
     */
    PARTIALLY_EXTRACTED,

    /** El archivo se abrio pero no contiene texto recuperable (escaneo ilegible, vacio). */
    UNREADABLE,

    /** El tipo de archivo no es uno de los que el extractor sabe procesar. */
    UNSUPPORTED_FORMAT,

    /** Error inesperado durante la extraccion: archivo corrupto, motor caido. */
    EXTRACTION_FAILED;

    /** {@code true} si el documento aporto algun dato utilizable al caso. */
    public boolean yieldedData() {
        return this == EXTRACTED || this == PARTIALLY_EXTRACTED;
    }

    /** {@code true} si el estado es terminal y no debe reintentarse. */
    public boolean isTerminal() {
        return this != RECEIVED;
    }
}
