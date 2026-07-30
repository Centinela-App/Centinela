package com.centinela.documentverification.application.port.out;

import com.centinela.documentverification.domain.model.ExtractionOutcome;

/**
 * Motor de extraccion de datos de un documento de identidad.
 *
 * <p>Existe como puerto porque el enunciado contempla dos implementaciones segun lo que
 * permita la suscripcion: un servicio administrado de reconocimiento documental, o una
 * libreria ejecutada dentro del propio componente. El requisito de manejo de fallos es
 * identico en ambos casos, asi que la logica de que hacer ante un documento ilegible vive
 * del lado de la aplicacion y no se duplica por adaptador.
 *
 * <p><b>Contrato estricto: este metodo no lanza.</b> Un documento ilegible o corrupto se
 * comunica como {@link ExtractionOutcome} con el estado correspondiente. Es lo que impide
 * que un archivo malformado propague una excepcion y detenga el procesamiento del lote.
 */
public interface IdentityDataExtractorPort {

    /**
     * @param content     bytes del documento tal como se cargaron
     * @param contentType tipo declarado en la carga; puede ser nulo o mentir
     * @param fileName    nombre original, usado solo para inferir el tipo si falta
     * @return el desenlace del intento, nunca nulo
     */
    ExtractionOutcome extract(byte[] content, String contentType, String fileName);

    /** Identificador del motor, guardado junto al resultado para poder auditarlo. */
    String engineName();
}
