package com.example.aimoderation;

import com.example.aimoderation.config.AppModerationProperties;
import com.example.aimoderation.config.LocalEnvFileLoader;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
@EnableConfigurationProperties(AppModerationProperties.class)
public class AiModerationApplication {

	public static void main(String[] args) {
		LocalEnvFileLoader.loadIfPresent();
		SpringApplication.run(AiModerationApplication.class, args);
	}

}
