package com.centinela.casemanagement.infrastructure.config;

import com.centinela.casemanagement.application.port.in.OpenCaseUseCase;
import com.centinela.casemanagement.application.port.out.CaseRepositoryPort;
import com.centinela.casemanagement.application.service.OpenCaseService;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;

@Configuration
public class CaseManagementConfiguration {
    @Bean
    Clock caseManagementClock() {
        return Clock.systemUTC();
    }

    @Bean
    OpenCaseUseCase openCaseUseCase(CaseRepositoryPort repositoryPort, Clock caseManagementClock) {
        return new OpenCaseService(repositoryPort, caseManagementClock);
    }
}
