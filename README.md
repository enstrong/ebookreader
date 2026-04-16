# 🇬🇧 eBookReader(Русский язык ниже)

A cross-platform book app built with Flutter, Spring Boot, and PostgreSQL.
This diploma project is a joint app created with my partner over several months; now I’m continuing it solo.

## What this app does

- Upload books as files from the app, including EPUB and other supported formats.
- Store uploaded book metadata, covers, and content in a backend service.
- Read books on mobile and desktop with a polished Flutter interface.
- Manage books, login/auth, and basic library organization.
- Keep local state and user preferences with `shared_preferences`.

## Core features

### Book upload

- Upload books using the file picker UI.
- EPUB is supported, and the app is designed to accept other book formats if they are allowed by the parser.
- Uploaded books are stored in the backend and become available in the app library.

### Library experience

- Browse and search your books.
- View book details, cover art, and metadata.
- Use the app as a personal reading manager.

### Authentication

- Login and user management are handled by the backend service.
- Secure sessions and profile-based library support.

### Backend / infrastructure

- Backend service lives in `backend/` and is built with Java/Spring Boot.
- Uses PostgreSQL for data storage.
- Docker support is included for local backend environment setup.

## Project status

- Work began as a team project and continued across a few months.
- I’m not in a rush to add everything immediately. Today is **April 15th**, and the diploma defense is scheduled for **June 22nd-28th.**

## Future direction

This project is headed toward becoming a true book superapp.
The priorities are:

1. **AI Recommendation Engine**
   - Add an AI recommendation engine that suggests books based on reading history
   - If a user has no history yet, ask them about books they love or let AI ask a few warm-up questions
   - Add an AI button on the main page to recommend titles dynamically

2. **Reading experience**
   - Bookmarks inside books
   - Notes/highlights
   - Highlight words and get definitions
   - Translate words or passages from open-source dictionaries

3. **Audiobooks and sync**
   - Support audiobooks and ebook playback together
   - Sync audio position with text so users can listen while walking and continue reading at home

4. **Reviews, ratings, and quotes last**
   - Add book reviews and rating pages
   - Add quotes in the far future once core reading and AI functionality are strong

## Tech stack

- Flutter frontend
- Spring Boot backend
- PostgreSQL database
- Docker-compatible backend setup
- File upload via Flutter `file_picker`
- EPUB parsing and book asset handling via Dart packages

## Notes

This is a personal project in active development. I finally bought a  new **MacBook Air M4 with 24GB of RAM** specifically to work on AI features for this app. All this development of the app is all cool and stuff, but I've never actually tried Machine Learning.


## Author

- Project started with a partner, developed together for 2 months (October and February).
- Partner, that absolutely deserves a lot of credit - [Shonkurieta](https://github.com/Shonkurieta). Frontend developer of this project and also added the EPUB support.
- Now continuing as a solo developer. Also have an internship, part-time job, and I'm training for a half-marathon.
- Main focus: achieve the first 3 of 4 goals at least, which should suffice for a great grade (no pun intended), or even achieve all 4 if I manage my time the best way possible. Though it all depends on how hard Machine Learning is, and I currently have zero idea due to having zero past experience.

---

## 🇷🇺 Русская версия

Кроссплатформенное приложение для книг на Flutter, Spring Boot и PostgreSQL.
Этот дипломный проект начинался как совместный с партнером, мы работали несколько месяцев, а сейчас я продолжаю его в одиночку.

## Что делает приложение

- Загружает книги из приложения как файлы, включая EPUB и другие поддерживаемые форматы.
- Сохраняет метаданные книг, обложки и содержимое в бэкенд-сервисе.
- Позволяет читать книги на мобильных и настольных платформах с удобным интерфейсом.
- Управляет книгами, входом и базовой библиотекой.
- Хранит локальные настройки и предпочтения пользователя через `shared_preferences`.

## Основные функции

### Загрузка книг

- Загружайте книги через интерфейс выбора файлов.
- EPUB поддерживается, и приложение рассчитано на другие форматы, если парсер их допустит.
- Загруженные книги сохраняются на сервере и становятся доступными в библиотеке приложения.

### Работа с библиотекой

- Просматривайте и ищите книги.
- Просматривайте детали книги, обложку и метаданные.
- Используйте приложение как личный менеджер чтения.

### Аутентификация

- Вход и управление пользователями обрабатываются бэкендом.
- Безопасные сессии и поддержка библиотек у пользователей.

### Бэкенд / инфраструктура

- Бэкенд находится в `backend/` и написан на Java/Spring Boot.
- Данные хранятся в PostgreSQL.
- Имеется поддержка Docker для локального запуска бэкенда.

## Текущее состояние проекта

- Проект начинался как командная работа и развивался несколько месяцев.
- Я не тороплюсь добавлять всё сразу. Сегодня **15 апреля**, а защита диплома назначена на **22–28 июня**.

## Дальнейшее развитие

Проект движется к формату суперприложения для книг.
Приоритеты:

1. **AI Recommendation Engine**
   - Добавить движок рекомендаций AI, который предлагает книги на основе истории чтения.
   - Если истории нет, спросить пользователя о книгах, которые ему нравятся, или дать AI задать несколько вопросов.
   - Добавить кнопку AI на главной странице для динамических рекомендаций.

2. **Опыт чтения**
   - Закладки внутри книг.
   - Заметки и выделения.
   - Выделять слова и получать определения.
   - Переводить слова или отрывки с помощью открытых словарей.

3. **Аудиокниги и синхронизация**
    - Поддержка аудиокниг и чтения электронных книг вместе.
    - Синхронизация позиции аудио с текстом, чтобы слушать во время прогулки и продолжать читать дома.

4. **Обзоры, оценки и цитаты позже**

    - Добавить обзоры книг и страницы оценок.
    - Добавить цитаты в будущем, когда основной опыт чтения и AI будут достаточно сильными.

## Технологии

- Flutter frontend
- Spring Boot backend
- PostgreSQL database
- Docker-compatible backend setup
- File upload via Flutter `file_picker`
- EPUB parsing and book asset handling via Dart packages

## Примечания

Это личный проект в активной разработке. Я недавно купил новый **MacBook Air M4 с 24 ГБ ОЗУ**, чтобы работать над AI-функциями для этого приложения. Следующий этап — сосредоточиться на рекомендациях AI.

## Автор

- Проект начинался с партнером, разрабатывался вместе 2 месяца (октябрь и февраль, производственные практики).
- Партнер, абсолютно заслуживающий упоминания - [Shonkurieta](https://github.com/Shonkurieta). Разрабатывал всю Frontend часть проекта и добавил поддержку EPUB.
- Сейчас продолжаю в одиночку. Также у меня стажировка, работа, и подготовка к полумарафону, поэтому грамотный тайм-менеджмент это все что может спасти мою дипломку.
- Основная цель: выполнить первые 3 из 4 задач и получить много баллов, а если повезет, то реализовать все 4.