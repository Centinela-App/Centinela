package com.centinela.shared.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Habilita la infraestructura de tareas programadas para toda la aplicacion.
 *
 * <p>Existe como configuracion propia, incondicional, por un bug que estuvo activo:
 * {@code @EnableScheduling} vivia dentro de {@code CaseExplanationConfiguration}, que
 * esta condicionada a {@code centinela.explainer.enabled}. Consecuencia: un despliegue
 * con la verificacion documental encendida y el explicador apagado dejaba a
 * {@code DocumentExtractionWorker} registrado pero <b>sin planificador que lo invocara
 * jamas</b> — los documentos quedaban en {@code RECEIVED} indefinidamente y ningun error
 * lo delataba, porque no fallar no es lo mismo que funcionar.
 *
 * <p>La regla que este archivo materializa: la capacidad de planificar pertenece a la
 * aplicacion; <i>que</i> se planifica pertenece a cada modulo y sigue condicionado por
 * sus propias banderas. Habilitar el planificador sin ningun {@code @Scheduled} activo
 * no cuesta nada, asi que la incondicionalidad es gratis.
 */
@Configuration
@EnableScheduling
public class SchedulingConfiguration {
}
