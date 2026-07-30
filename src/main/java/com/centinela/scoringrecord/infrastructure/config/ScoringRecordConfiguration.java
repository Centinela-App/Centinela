package com.centinela.scoringrecord.infrastructure.config;

import com.centinela.scoringrecord.application.port.out.ScoringDecisionReaderPort;
import com.centinela.scoringrecord.infrastructure.mongo.CosmosScoringDecisionReader;
import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoClients;
import org.bson.Document;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Acceso de solo lectura al registro que el motor de scoring dejo en Cosmos.
 *
 * <p>Vive en su propio modulo porque lo consumen dos componentes con ciclos de vida
 * distintos: el explicador, que lo usa para redactar la explicacion, y la API de consulta,
 * que lo usa para responderle al analista. Ninguno de los dos deberia depender del otro
 * solo para llegar al mismo dato.
 *
 * <p>Se activa por configuracion para que un contenedor que no lo necesite — por ejemplo
 * uno dedicado unicamente a consumir la cola de casos — no abra conexiones ociosas contra
 * la base de datos.
 */
@Configuration
@ConditionalOnProperty(name = "centinela.scoring-record.enabled", havingValue = "true")
public class ScoringRecordConfiguration {

    /**
     * La cadena de conexion llega por variable de entorno, poblada desde Key Vault por la
     * plataforma. Nunca se hornea en la imagen ni se versiona.
     */
    @Bean(destroyMethod = "close")
    public MongoClient scoringRecordMongoClient(
            @Value("${centinela.scoring-record.cosmos.connection-string}") String connectionString) {
        return MongoClients.create(connectionString);
    }

    @Bean
    public ScoringDecisionReaderPort scoringDecisionReader(
            MongoClient scoringRecordMongoClient,
            @Value("${centinela.scoring-record.cosmos.database}") String database,
            @Value("${centinela.scoring-record.cosmos.collection}") String collection) {
        return new CosmosScoringDecisionReader(
                scoringRecordMongoClient.getDatabase(database).getCollection(collection, Document.class));
    }
}
