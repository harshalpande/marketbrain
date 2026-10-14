FROM maven:3.9.11-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml .
RUN mvn -q -DskipTests dependency:go-offline
COPY src src
RUN mvn -q -DskipTests package

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /workspace/target/marketbrain-service-0.1.0-SNAPSHOT.jar app.jar
# Standalone stdin-only local control client; no nested Boot dependencies or HTTP unlock route.
COPY --from=build /workspace/target/classes/in/marketbrain/paper/PaperRuntimeControl.class /app/control/in/marketbrain/paper/PaperRuntimeControl.class
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
