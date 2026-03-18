# ---------- Stage 1 : Build ----------
# Bilkul same as pehle — kuch change nahi
FROM maven:3.9.6-eclipse-temurin-17-alpine AS build
WORKDIR /build

COPY pom.xml .
RUN mvn dependency:go-offline

COPY src ./src
RUN mvn clean package -DskipTests

# ---------- Stage 2 : Run ----------
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# curl install karo — health check ke liye zaroori hai
RUN apk add --no-cache curl

COPY --from=build /build/target/*.jar app.jar

# ── Health Check ──────────────────────────────────────────────────
# Spring Boot Actuator endpoint check karta hai
HEALTHCHECK --interval=30s \
            --timeout=10s  \
            --retries=3    \
            --start-period=60s \
  CMD curl -f http://localhost:8086/actuator/health || exit 1

EXPOSE 8086
ENTRYPOINT ["java","-jar","app.jar"]



# # Build stage
# FROM maven:3.9.6-eclipse-temurin-17-alpine AS build
# WORKDIR /build
# COPY pom.xml .
# RUN mvn dependency:go-offline
# COPY src ./src
# RUN mvn clean package -DskipTests

# # Create custom JRE
# FROM eclipse-temurin:17-jdk-alpine AS jre-build
# RUN jlink \
#     --add-modules java.base,java.logging,java.sql \
#     --strip-debug \
#     --no-man-pages \
#     --no-header-files \
#     --compress=2 \
#     --output /customjre

# # Final stage
# FROM alpine:3.19
# WORKDIR /app
# COPY --from=jre-build /customjre /opt/java
# ENV PATH="/opt/java/bin:${PATH}"
# COPY --from=build /build/target/*.jar app.jar

# EXPOSE 8085
# ENTRYPOINT ["java","-jar","app.jar"]

