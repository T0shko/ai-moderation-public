package com.example.aimoderation;

import com.example.aimoderation.config.LocalEnvFileLoader;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class AiModerationApplication {

	public static void main(String[] args) {
		LocalEnvFileLoader.loadIfPresent();
		SpringApplication.run(AiModerationApplication.class, args);
	}

}
