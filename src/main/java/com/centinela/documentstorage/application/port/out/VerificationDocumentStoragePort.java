package com.centinela.documentstorage.application.port.out;

import com.centinela.documentstorage.domain.model.VerificationDocument;

import java.time.Instant;

/**
 * Puerto de salida para conservar documentos sin exponer tipos de Azure.
 */
@FunctionalInterface
public interface VerificationDocumentStoragePort {

    /**
     * Persiste el documento y devuelve <b>donde quedo</b>.
     *
     * <p>La ruta la decide el adaptador, que es quien conoce la convencion de nombres. El
     * llamador la necesita porque el flujo de verificacion documental de Semana 3 vuelve a
     * leer el archivo mas tarde, de forma asincrona, para extraer sus datos: sin la ruta
     * habria que reconstruirla duplicando esa convencion en dos sitios, y una divergencia
     * entre ambas solo se descubriria en produccion.
     *
     * @return ruta del blob dentro del contenedor
     */
    String store(VerificationDocument document, Instant receivedAt);
}
