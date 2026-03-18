package com.devops.demo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.web.servlet.support.SpringBootServletInitializer;
import org.springframework.cache.annotation.EnableCaching;

@SpringBootApplication
@EnableCaching  // ✅ Enable caching globally
public class DemoApplication extends SpringBootServletInitializer {

    // WAR deployment ke liye
    @Override
    protected SpringApplicationBuilder configure(SpringApplicationBuilder application) {
        return application.sources(DemoApplication.class);
    }

    // Standalone JAR ke liye
    public static void main(String[] args) {
        SpringApplication.run(DemoApplication.class, args);
    }
}