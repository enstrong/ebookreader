import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { ru, en }

class AppLanguageController extends ChangeNotifier {
  static const _storageKey = 'app_language';

  AppLanguage _language = AppLanguage.ru;
  bool _isLoaded = false;

  AppLanguage get language => _language;
  bool get isLoaded => _isLoaded;
  bool get isEnglish => _language == AppLanguage.en;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    _language = AppLanguage.values.firstWhere(
      (language) => language.name == raw,
      orElse: () => AppLanguage.ru,
    );
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language && _isLoaded) return;
    _language = language;
    _isLoaded = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, language.name);
  }
}

class AppLanguageScope extends InheritedNotifier<AppLanguageController> {
  const AppLanguageScope({
    super.key,
    required AppLanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLanguageController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppLanguageScope>();
    assert(scope != null, 'AppLanguageScope is missing above this context');
    return scope!.notifier!;
  }
}

extension AppLanguageContext on BuildContext {
  AppLanguageController get appLanguage => AppLanguageScope.of(this);

  String tr(String russian, {String? en}) {
    if (!appLanguage.isEnglish) return russian;
    return en ?? _en[russian] ?? russian;
  }

  String genreLabel(String genre) {
    final normalized = genre.trim().toLowerCase();
    final english = _genreEn[normalized];
    if (appLanguage.isEnglish && english != null) return english;
    final russian = _genreRu[normalized];
    return russian ?? _cleanGenre(genre);
  }

  String pagesCount(int count) {
    if (appLanguage.isEnglish) return '$count ${count == 1 ? 'page' : 'pages'}';
    final mod10 = count % 10;
    final mod100 = count % 100;
    final word = mod10 == 1 && mod100 != 11
        ? 'страница'
        : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
        ? 'страницы'
        : 'страниц';
    return '$count $word';
  }

  String booksCount(int count) {
    if (appLanguage.isEnglish) return '$count ${count == 1 ? 'book' : 'books'}';
    final mod10 = count % 10;
    final mod100 = count % 100;
    final word = mod10 == 1 && mod100 != 11
        ? 'книга'
        : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
        ? 'книги'
        : 'книг';
    return '$count $word';
  }

  String ratingsCount(int count) {
    if (appLanguage.isEnglish) {
      return '$count ${count == 1 ? 'rating' : 'ratings'}';
    }
    final mod10 = count % 10;
    final mod100 = count % 100;
    final word = mod10 == 1 && mod100 != 11
        ? 'оценка'
        : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
        ? 'оценки'
        : 'оценок';
    return '$count $word';
  }

  String chapterLabel(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return tr('Глава');
    return appLanguage.isEnglish ? 'Chapter $raw' : 'Глава $raw';
  }

  String chaptersCount(int count) {
    if (appLanguage.isEnglish) {
      return count == 0
          ? tr('Нет глав')
          : '$count ${count == 1 ? 'chapter' : 'chapters'}';
    }
    if (count == 0) return 'Нет глав';
    final mod10 = count % 10;
    final mod100 = count % 100;
    final word = mod10 == 1 && mod100 != 11
        ? 'глава'
        : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
        ? 'главы'
        : 'глав';
    return '$count $word';
  }
}

String _cleanGenre(String genre) {
  return genre
      .split(RegExp(r'[_\-\s,]+'))
      .where((word) => word.trim().isNotEmpty)
      .map((word) => word.trim())
      .join(' ');
}

const Map<String, String> _genreRu = {
  'fiction': 'Художественная литература',
  'fantasy': 'Фэнтези и мистика',
  'fantasy, paranormal': 'Фэнтези и мистика',
  'fantasy-paranormal': 'Фэнтези и мистика',
  'young-adult': 'Подростковая литература',
  'young adult': 'Подростковая литература',
  'children': 'Детская литература',
  'romance': 'Романтика',
  'mystery, thriller, crime': 'Детективы и триллеры',
  'mystery-thriller-crime': 'Детективы и триллеры',
  'mystery': 'Детективы и триллеры',
  'history, historical fiction, biography': 'История и биографии',
  'history-biography': 'История и биографии',
  'comics, graphic': 'Комиксы и графические романы',
  'comics-graphic': 'Комиксы и графические романы',
  'poetry': 'Поэзия',
  'non-fiction': 'Нон-фикшн',
  'nonfiction': 'Нон-фикшн',
  'classics': 'Классика',
  'science fiction': 'Научная фантастика',
  'sci-fi': 'Научная фантастика',
  'horror': 'Ужасы',
  'adventure': 'Приключения',
  'drama': 'Драма',
  'literature': 'Литература',
};

const Map<String, String> _genreEn = {
  'fiction': 'Fiction',
  'fantasy': 'Fantasy and paranormal',
  'fantasy, paranormal': 'Fantasy and paranormal',
  'fantasy-paranormal': 'Fantasy and paranormal',
  'young-adult': 'Young adult',
  'young adult': 'Young adult',
  'children': 'Children',
  'romance': 'Romance',
  'mystery, thriller, crime': 'Mystery, thriller, crime',
  'mystery-thriller-crime': 'Mystery, thriller, crime',
  'mystery': 'Mystery, thriller, crime',
  'history, historical fiction, biography': 'History and biography',
  'history-biography': 'History and biography',
  'comics, graphic': 'Comics and graphic novels',
  'comics-graphic': 'Comics and graphic novels',
  'poetry': 'Poetry',
  'non-fiction': 'Non-fiction',
  'nonfiction': 'Non-fiction',
  'classics': 'Classics',
  'science fiction': 'Science fiction',
  'sci-fi': 'Science fiction',
  'horror': 'Horror',
  'adventure': 'Adventure',
  'drama': 'Drama',
  'literature': 'Literature',
};

const Map<String, String> _en = {
  'Внешний вид': 'Appearance',
  'Тема приложения': 'App theme',
  'Язык приложения': 'App language',
  'Язык интерфейса': 'Interface language',
  'Тема и язык': 'Theme and language',
  'Загрузка...': 'Loading...',
  'Отмена': 'Cancel',
  'Удалить': 'Delete',
  'Сохранить': 'Save',
  'Сохранить книгу': 'Save book',
  'Добавить': 'Add',
  'Изменить': 'Change',
  'Редактировать': 'Edit',
  'Закрыть': 'Close',
  'Продолжить': 'Continue',
  'Назад': 'Back',
  'Вперёд': 'Forward',
  'Войти': 'Sign in',
  'Выйти': 'Sign out',
  'Регистрация': 'Create account',
  'Зарегистрироваться': 'Create account',
  'Нет аккаунта? ': 'No account? ',
  'Войдите, чтобы продолжить чтение': 'Sign in to keep reading',
  'Присоединяйтесь к нашему сообществу читателей': 'Join our reading community',
  'Email или логин': 'Email or username',
  'Логин': 'Username',
  'Пароль': 'Password',
  'Повторите пароль': 'Repeat password',
  'Новый пароль': 'New password',
  'Старый пароль': 'Current password',
  'Минимум 8 символов': 'At least 8 characters',
  'Забыли пароль?': 'Forgot password?',
  'Восстановить пароль': 'Reset password',
  'Введите код': 'Enter code',
  'Код из письма': 'Email code',
  'Отправить код': 'Send code',
  'Изменить пароль': 'Change password',
  'Войти через Google': 'Sign in with Google',
  'Не удается подключиться к серверу. Проверьте интернет-соединение':
      'Cannot connect to the server. Check your connection',
  'Не удалось войти через Google': 'Could not sign in with Google',
  'Токен не получен от сервера': 'Token was not received from the server',
  'Введите email или имя пользователя': 'Enter email or username',
  'Введите email': 'Enter email',
  'Введите пароль': 'Enter password',
  'Введите корректный email': 'Enter a valid email',
  'Введите логин': 'Enter username',
  'Подтвердите пароль': 'Confirm password',
  'Минимум 3 символа': 'At least 3 characters',
  'Уже есть аккаунт? ': 'Already have an account? ',
  'Ошибка регистрации': 'Registration error',
  'Все поля должны быть заполнены': 'All fields are required',
  'Пароль должен содержать минимум 8 символов':
      'Password must contain at least 8 characters',
  'Пароли не совпадают': 'Passwords do not match',
  'Если email найден, код отправлен': 'If the email exists, a code was sent',
  'Пароль изменён. Теперь можно войти': 'Password changed. You can sign in now',
  'Библиотека': 'Library',
  'Для чтения и прослушивания': 'Read and listen',
  'Для вас': 'For you',
  'AI-рекомендации по вашим оценкам': 'AI recommendations from your ratings',
  'Настроить вкус': 'Tune preferences',
  'Открыть каталог': 'Open catalog',
  'Научим модель вашему вкусу': 'Teach the model your taste',
  'Выберите 3-10 книг, которые вам понравились. После этого здесь появится ваша персональная полка.':
      'Choose 3-10 books you liked. Your personal shelf will appear here after that.',
  'Выбрать любимые книги': 'Choose favorite books',
  'Открыть полный каталог': 'Open full catalog',
  'Все книги Goodreads': 'All Goodreads books',
  'Показать рекомендации': 'Show recommendations',
  'Выберите любимые книги': 'Choose favorite books',
  'От 3 до 10 книг, рейтинг будет сохранён как 5★':
      'Choose 3 to 10 books; each will be saved as a 5★ rating',
  'Выбрано': 'Selected',
  'Уже вижу': 'Already seeing',
  'Профиль': 'Profile',
  'Выход из системы': 'Sign out',
  'Вы действительно хотите выйти из своего аккаунта?':
      'Do you really want to sign out?',
  'Смена имени пользователя': 'Change username',
  'Введите новое имя': 'Enter a new name',
  'Никнейм не может быть пустым': 'Nickname cannot be empty',
  'Никнейм успешно обновлён': 'Nickname updated',
  'Пароль успешно изменён': 'Password changed',
  'ПОЛЬЗОВАТЕЛЬ': 'USER',
  'Оценённые книги': 'Rated books',
  'История оценок и сигналов рекомендаций':
      'Rating history and recommendation signals',
  'Любимые цитаты': 'Favorite quotes',
  'Цитаты, опубликованные из книг': 'Quotes published from books',
  'Ошибка загрузки цитат': 'Quote loading error',
  'Опубликованные цитаты появятся здесь.': 'Published quotes will appear here.',
  'Сменить пароль': 'Change password',
  'Обновить пароль': 'Update password',
  'Не установлен': 'Not set',
  'Выйти из системы': 'Sign out',
  'Сохранённые книги': 'Saved books',
  'Книги, к которым вы хотите вернуться': 'Books you want to return to',
  'Нет сохранённых книг': 'No saved books',
  'Здесь будут отображаться книги, которые вы сохранили для чтения':
      'Books you save for reading will appear here',
  'Убрать из сохранённых?': 'Remove from saved?',
  'Убрать из сохранённых': 'Remove from saved',
  'Удалено из сохранённых': 'Removed from saved',
  'Книга сохранена': 'Book saved',
  'Книга отмечена как прочитанная': 'Book marked as read',
  'Оценка удалена': 'Rating removed',
  'Оценка сохранена': 'Rating saved',
  'Оценка': 'Rating',
  'Книга': 'Book',
  'Оценить книгу': 'Rate book',
  '0: прочитано без оценки': '0: read without a rating',
  'Ошибка сохранения оценки': 'Rating save error',
  'Ошибка загрузки оценённых книг': 'Rated books loading error',
  'нет даты': 'no date',
  'Средняя': 'Average',
  'Сигналы': 'Signals',
  'Последняя': 'Latest',
  'Дата неизвестна': 'Date unknown',
  'Пока нет оценённых книг': 'No rated books yet',
  'Когда пользователь поставит звёзды книге, она появится здесь вместе с датой и вкладом в рекомендации.':
      'When the user rates a book, it will appear here with the date and recommendation signal.',
  'Нет среднего рейтинга': 'No average rating',
  'Сильно выше среднего': 'Far above average',
  'Выше среднего': 'Above average',
  'Сильно ниже среднего': 'Far below average',
  'Ниже среднего': 'Below average',
  'Около среднего': 'Near average',
  'Книга не найдена': 'Book not found',
  'Описание отсутствует': 'No description available',
  'Главы отсутствуют': 'No chapters',
  'Эта книга пока не содержит глав для чтения':
      'This book has no readable chapters yet',
  'Подбираем похожие книги': 'Finding similar books',
  'Похожие книги': 'Similar books',
  'Похожий жанр': 'Similar genre',
  'Похожий автор': 'Similar author',
  'Похожая книга': 'Similar book',
  'Ваша оценка': 'Your rating',
  'Отметить как прочитанное': 'Mark as read',
  'Детали': 'Details',
  'Открыть': 'Open',
  'не указан': 'not specified',
  'Продолжить чтение': 'Continue reading',
  'Читать': 'Read',
  'Слушать': 'Listen',
  'Текст': 'Text',
  'Каталог': 'Catalog',
  'Отзывы': 'Reviews',
  'Цитаты': 'Quotes',
  'Отзывы могут содержать спойлеры': 'Reviews may contain spoilers',
  'Цитаты могут содержать спойлеры': 'Quotes may contain spoilers',
  'Здесь читатели обсуждают конкретные моменты книги. Откройте этот раздел только если точно готовы.':
      'Readers discuss specific moments from the book here. Open this section only if you are ready.',
  'Я понимаю, что здесь будут спойлеры':
      'I understand that this section may contain spoilers',
  'Не открывать': 'Do not open',
  'Открыть всё равно': 'Open anyway',
  'опубликовано пользователем': 'published by',
  'Ответить': 'Reply',
  'Опубликовать': 'Publish',
  'Пока нет отзывов.': 'No reviews yet.',
  'Пока нет опубликованных цитат.': 'No published quotes yet.',
  'Ваш ответ': 'Your reply',
  'Напишите отзыв': 'Write a review',
  'Показать больше': 'Show more',
  'Скрыть': 'Hide',
  'Главная': 'Home',
  'Поиск книг...': 'Search books...',
  'Поиск': 'Search',
  'результатов': 'results',
  'Библиотека пуста': 'Library is empty',
  'Начните читать книгу, и она появится здесь':
      'Start reading a book and it will appear here',
  'Попробуйте поискать по другому названию или автору':
      'Try another title or author',
  'Снять выделение': 'Clear selection',
  'выбрано': 'selected',
  'Читаю': 'Reading',
  'Хочу': 'Want',
  'Прочитано': 'Finished',
  'Демо-аудиокнига': 'Demo audiobook',
  'Поиск любимой книги': 'Search favorite books',
  'Фильтр': 'Filter',
  'Фильтры': 'Filters',
  'Сортировать': 'Sort',
  'Сброс': 'Reset',
  'Все жанры': 'All genres',
  'Рейтинг': 'Rating',
  'Оценки': 'Ratings',
  'Язык': 'Language',
  'Название': 'Title',
  'Автор': 'Author',
  'Описание': 'Description',
  'Страницы': 'Pages',
  'Жанр': 'Genre',
  'Доступность': 'Availability',
  'Языки недоступны': 'No languages available',
  'Все рейтинги': 'All ratings',
  'Очистить': 'Clear',
  'Применить': 'Apply',
  'Нет книг': 'No books',
  'Книги не найдены': 'No books found',
  'Попробуйте изменить фильтры или поиск': 'Try changing filters or search',
  'Добавьте первую книгу': 'Add the first book',
  'Добавить книгу': 'Add book',
  'Управление': 'Manage',
  'Пользователи': 'Users',
  'Книги': 'Books',
  'Пользователи системы': 'System users',
  'Нет пользователей': 'No users',
  'Администратор': 'Administrator',
  'Пользователь': 'User',
  'Управление книгами': 'Book management',
  'Удалить книгу?': 'Delete book?',
  'Удалить пользователя?': 'Delete user?',
  'Главы': 'Chapters',
  'Глава': 'Chapter',
  'Ошибка загрузки': 'Loading error',
  'Ошибка сохранения выделения': 'Highlight save error',
  'Цитата не может быть длиннее': 'Quote cannot be longer than',
  'слов': 'words',
  'Цитата опубликована': 'Quote published',
  'Ошибка публикации цитаты': 'Quote publishing error',
  'Ошибка словаря': 'Dictionary error',
  'Выделение больше не совпадает с текстом главы':
      'The selection no longer matches the chapter text',
  'Сохранено в словарь': 'Saved to dictionary',
  'Ошибка сохранения в словарь': 'Dictionary save error',
  'Словарь': 'Dictionary',
  'Определение': 'Definition',
  'Перевод': 'Translation',
  'Источник': 'Source',
  'Ошибка обновления заметки': 'Note update error',
  'Ошибка удаления заметки': 'Note deletion error',
  'Ошибка загрузки заметок': 'Notes loading error',
  'Выделения и заметки': 'Highlights and notes',
  'Выделите текст в книге, и он появится здесь.':
      'Select text in a book and it will appear here.',
  'Выделения': 'Highlights',
  'Выделить': 'Highlight',
  'Цитата': 'Quote',
  'Настройки чтения': 'Reading settings',
  'Размер шрифта': 'Font size',
  'Яркость': 'Brightness',
  'Шрифт': 'Font',
  'Дополнительно': 'Advanced',
  'Отступы и цвета': 'Margins and colors',
  'Вернуть настройки чтения по умолчанию': 'Restore default reading settings',
  'Сбросить настройки?': 'Reset settings?',
  'Шрифт, размер, яркость, отступы и цвета чтения вернутся по умолчанию.':
      'Font, size, brightness, margins, and reading colors will return to defaults.',
  'Сбросить': 'Reset',
  'Шрифт чтения': 'Reading font',
  'Готово': 'Done',
  'Отступы': 'Margins',
  'Вернуть отступы по умолчанию': 'Restore default margins',
  'Горизонтальные': 'Horizontal',
  'Вертикальные': 'Vertical',
  'Цвета': 'Colors',
  'Вернуть цвета по умолчанию': 'Restore default colors',
  'Фон': 'Background',
  'Выделение': 'Highlight',
  'Сохранённый перевод': 'Saved translation',
  'Недавние': 'Recent',
  'Выделено': 'Selected',
  'Определения': 'Definitions',
  'Для фраз показывается только перевод. Для слова определение может отсутствовать в источнике.':
      'Only translation is shown for phrases. A word definition may be missing from the source.',
  'Варианты': 'Alternatives',
  'Перевод сейчас недоступен.': 'Translation is unavailable right now.',
  'Статус': 'Status',
  'Заметка к выделению': 'Highlight note',
  'Добавьте мысль, вопрос или короткую заметку...':
      'Add a thought, question, or short note...',
  'Позже': 'Later',
  'Нет глав': 'No chapters',
  'Добавьте первую главу': 'Add the first chapter',
  'Добавить главу': 'Add chapter',
  'Редактировать главу': 'Edit chapter',
  'Название главы': 'Chapter title',
  'Содержимое главы': 'Chapter content',
  'Сохранить главу': 'Save chapter',
  'Выбрать все': 'Select all',
  'Снять все': 'Clear all',
  'Импортировать': 'Import',
  'Аудиокнига': 'Audiobook',
  'Для этой книги пока нет аудиотреков': 'This book has no audio tracks yet',
  'Для этой главы пока нет аудио': 'This chapter does not have audio yet',
  'Не удалось запустить аудио': 'Could not start audio',
  'Сегмент': 'Segment',
  'Предыдущий сегмент': 'Previous segment',
  'Следующий сегмент': 'Next segment',
  'Назад на 10 секунд': 'Back 10 seconds',
  'Вперёд на 10 секунд': 'Forward 10 seconds',
  'Пауза': 'Pause',
  'Скорость': 'Speed',
  'Сейчас играет': 'Now playing',
  'Продолжить читать': 'Continue reading',
  'Аудио': 'Audio',
  'Есть текст': 'Text available',
  'Есть аудио': 'Audio available',
  'Текст + аудио': 'Text + audio',
  'PDF без синхронизации': 'PDF without sync',
  'Метаданные': 'Metadata',
  'Без названия': 'Untitled',
  'Неизвестный автор': 'Unknown author',
  'Ваша электронная библиотека': 'Your digital library',
};
