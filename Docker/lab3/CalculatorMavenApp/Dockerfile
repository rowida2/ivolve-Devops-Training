FROM maven:3.9-eclipse-temurin-17


RUN groupadd -r appgroup && useradd -r -g appgroup appuser

WORKDIR /app
COPY . .


RUN mvn package -DskipTests && chown -R appuser:appgroup /app

EXPOSE 8080

CMD ["sh", "-c", "java -jar target/*.jar"]
