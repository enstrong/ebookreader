# Этап 1: Сборка (используем Maven образ, так как в нем уже есть всё необходимое)
FROM maven:3.8.5-openjdk-17-slim AS builder
WORKDIR /app
# Копируем только pom.xml сначала, чтобы закешировать зависимости
COPY pom.xml .
COPY src ./src
# Собираем JAR
RUN mvn clean package -Dmaven.test.skip=true

# Этап 2: Запуск (используем актуальный и поддерживаемый образ Temurin)
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app
# Копируем JAR из этапа сборки (используем маску *, чтобы не зависеть от версии в названии)
COPY --from=builder /app/target/*.jar ebookreader-backend.jar

# Создаем папку для ассетов, чтобы не было ошибок доступа
RUN mkdir -p assets/covers

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "ebookreader-backend.jar"]
