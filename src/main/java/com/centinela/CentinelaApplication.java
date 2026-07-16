package com.centinela;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Punto de entrada de Centinela.
 *
 * <p>Semana 1: solo levanta el contexto Spring Boot. No registra controllers
 * funcionales, adaptadores de Azure ni logica de negocio (eso llega en las
 * issues ISS-007, ISS-008 e ISS-009).
 */
@SpringBootApplication
public class CentinelaApplication {

    public static void main(String[] args) {
        SpringApplication.run(CentinelaApplication.class, args);
    }
}
