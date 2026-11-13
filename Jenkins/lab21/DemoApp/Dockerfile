# Runtime stage: lightweight JRE only (the Maven build already ran in the pipeline)
FROM eclipse-temurin:17-jre

# Set working directory in container
WORKDIR /app

# Copy JAR file
COPY target/demo-0.0.1-SNAPSHOT.jar .

# Run the application
CMD ["java", "-jar", "demo-0.0.1-SNAPSHOT.jar"]

EXPOSE 8080
