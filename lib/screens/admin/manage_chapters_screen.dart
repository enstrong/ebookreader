import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../../constants/api_constants.dart';

/// Экран управления главами книги.
///
/// Отображает список глав выбранной книги с возможностью добавления,
/// редактирования и удаления глав. Поддерживает импорт глав из EPUB-файла,
/// режим множественного выбора для массового удаления, а также
/// задание названия, содержимого и порядкового номера главы.
class ManageChaptersScreen extends StatefulWidget {
  final String token;
  final int bookId;
  final String bookTitle;

  const ManageChaptersScreen({
    super.key,
    required this.token,
    required this.bookId,
    required this.bookTitle,
  });

  @override
  State<ManageChaptersScreen> createState() => _ManageChaptersScreenState();
}

class _ManageChaptersScreenState extends State<ManageChaptersScreen>
    with SingleTickerProviderStateMixin {
  late final String baseUrl;
  List<dynamic> chapters = [];
  bool loading = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  // Режим множественного выбора
  bool isSelectionMode = false;
  Set<int> selectedChapterIds = {};

  @override
  void initState() {
    super.initState();
    baseUrl = ApiConstants.adminUrl;
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _animController.forward();
    _loadChapters();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.token}',
      };

  Future<void> _loadChapters() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/books/${widget.bookId}/chapters'),
        headers: headers,
      );

      if (res.statusCode == 200) {
        final chaptersData = jsonDecode(res.body) as List;
        setState(() {
          chapters = chaptersData;
          loading = false;
        });
      } else {
        throw Exception('Ошибка загрузки: ${res.statusCode}');
      }
    } catch (e) {
      setState(() => loading = false);
      _showSnackBar('Ошибка: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(20),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ========== РЕЖИМ ВЫБОРА ==========

  void _toggleSelectionMode() {
    setState(() {
      isSelectionMode = !isSelectionMode;
      if (!isSelectionMode) {
        selectedChapterIds.clear();
      }
    });
  }

  void _selectAllChapters() {
    setState(() {
      selectedChapterIds = chapters.map((c) => c['id'] as int).toSet();
    });
  }

  void _deselectAllChapters() {
    setState(() {
      selectedChapterIds.clear();
    });
  }

  void _toggleChapterSelection(int id) {
    setState(() {
      if (selectedChapterIds.contains(id)) {
        selectedChapterIds.remove(id);
      } else {
        selectedChapterIds.add(id);
      }
    });
  }

  void _showBulkDeleteDialog() {
    if (selectedChapterIds.isEmpty) {
      _showSnackBar('Выберите главы для удаления', isError: true);
      return;
    }

    final count = selectedChapterIds.length;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Удалить главы?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Вы уверены, что хотите удалить $count ${_getChapterWord(count)}?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Отмена',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _bulkDeleteChapters();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  String _getChapterWord(int count) {
    if (count % 10 == 1 && count % 100 != 11) {
      return 'главу';
    } else if ([2, 3, 4].contains(count % 10) &&
        ![12, 13, 14].contains(count % 100)) {
      return 'главы';
    } else {
      return 'глав';
    }
  }

  Future<void> _bulkDeleteChapters() async {
    int successCount = 0;
    int errorCount = 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F3A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF14FFEC)),
              const SizedBox(height: 16),
              Text(
                'Удаление глав...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    for (var chapterId in selectedChapterIds) {
      try {
        final res = await http.delete(
          Uri.parse('$baseUrl/books/${widget.bookId}/chapters/$chapterId'),
          headers: headers,
        );
        if (res.statusCode == 200) {
          successCount++;
        } else {
          errorCount++;
        }
      } catch (e) {
        errorCount++;
      }
    }

    if (mounted) {
      Navigator.pop(context);
      setState(() {
        isSelectionMode = false;
        selectedChapterIds.clear();
      });
      await _loadChapters();

      if (errorCount == 0) {
        _showSnackBar('Удалено глав: $successCount');
      } else {
        _showSnackBar(
          'Удалено: $successCount, Ошибок: $errorCount',
          isError: errorCount > successCount,
        );
      }
    }
  }

  // ========== EPUB PARSER ==========

  Future<void> _importFromEpub() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
      );

      if (result == null) return;

      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F3A),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFF14FFEC)),
                const SizedBox(height: 16),
                Text(
                  'Обработка EPUB файла...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final extractedChapters = await _parseEpub(bytes);

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (extractedChapters.isEmpty) {
        _showSnackBar('В файле не найдено глав', isError: true);
        return;
      }

      await _showChapterSelectionDialog(extractedChapters);
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _showSnackBar('Ошибка импорта: $e', isError: true);
      }
    }
  }

  Future<List<Map<String, String>>> _parseEpub(List<int> bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final chapters = <Map<String, String>>[];

    ArchiveFile? opfFile;
    for (var file in archive) {
      if (file.name.endsWith('.opf')) {
        opfFile = file;
        break;
      }
    }

    if (opfFile == null) {
      throw Exception('Не найден файл content.opf');
    }

    final opfContent = utf8.decode(opfFile.content as List<int>);
    final opfDoc = XmlDocument.parse(opfContent);

    final spineItems = opfDoc.findAllElements('itemref');
    int chapterOrder = 1;

    for (var item in spineItems) {
      final idref = item.getAttribute('idref');
      if (idref == null) continue;

      final manifestItem = opfDoc
          .findAllElements('item')
          .firstWhere(
            (el) => el.getAttribute('id') == idref,
            orElse: () => XmlElement(XmlName('item')),
          );

      final href = manifestItem.getAttribute('href');
      if (href == null ||
          !href.endsWith('.html') && !href.endsWith('.xhtml')) {
        continue;
      }

      final chapterFile = archive.firstWhere(
        (f) => f.name.endsWith(href),
        orElse: () => ArchiveFile('', 0, []),
      );

      if (chapterFile.content.isEmpty) continue;

      final chapterContent = utf8.decode(chapterFile.content as List<int>);
      final chapterDoc = XmlDocument.parse(chapterContent);

      String title = 'Глава $chapterOrder';
      final h1 = chapterDoc.findAllElements('h1').firstOrNull;
      final h2 = chapterDoc.findAllElements('h2').firstOrNull;
      final titleEl = chapterDoc.findAllElements('title').firstOrNull;

      if (h1 != null && h1.innerText.isNotEmpty) {
        title = h1.innerText.trim();
      } else if (h2 != null && h2.innerText.isNotEmpty) {
        title = h2.innerText.trim();
      } else if (titleEl != null && titleEl.innerText.isNotEmpty) {
        title = titleEl.innerText.trim();
      }

      final bodyElements = chapterDoc.findAllElements('body');
      String content = '';

      if (bodyElements.isNotEmpty) {
        content = bodyElements.first.innerText;
      } else {
        content = chapterDoc.innerText;
      }

      content = content
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'\n\s*\n'), '\n\n')
          .trim();

      if (content.length > 50) {
        chapters.add({
          'title': title,
          'content': content,
          'order': chapterOrder.toString(),
        });
        chapterOrder++;
      }
    }

    return chapters;
  }

  Future<void> _showChapterSelectionDialog(
      List<Map<String, String>> extractedChapters) async {
    final selectedChapters =
        List<bool>.filled(extractedChapters.length, true);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1F3A),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Выберите главы для импорта',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        setDialogState(() {
                          for (int i = 0; i < selectedChapters.length; i++) {
                            selectedChapters[i] = true;
                          }
                        });
                      },
                      child: const Text(
                        'Выбрать все',
                        style: TextStyle(color: Color(0xFF14FFEC)),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setDialogState(() {
                          for (int i = 0; i < selectedChapters.length; i++) {
                            selectedChapters[i] = false;
                          }
                        });
                      },
                      child: Text(
                        'Снять все',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6)),
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: extractedChapters.length,
                    itemBuilder: (context, index) {
                      final chapter = extractedChapters[index];
                      return CheckboxListTile(
                        value: selectedChapters[index],
                        onChanged: (value) {
                          setDialogState(() {
                            selectedChapters[index] = value ?? false;
                          });
                        },
                        title: Text(
                          chapter['title']!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'Глава ${chapter['order']} • ${chapter['content']!.length} символов',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                        activeColor: const Color(0xFF14FFEC),
                        checkColor: Colors.black,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Отмена',
                style:
                    TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);

                final selectedCount =
                    selectedChapters.where((e) => e).length;
                if (selectedCount == 0) {
                  _showSnackBar('Выберите хотя бы одну главу',
                      isError: true);
                  return;
                }

                await _importSelectedChapters(
                  extractedChapters
                      .asMap()
                      .entries
                      .where((e) => selectedChapters[e.key])
                      .map((e) => e.value)
                      .toList(),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF14FFEC),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Импортировать',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importSelectedChapters(
      List<Map<String, String>> selectedChapters) async {
    int successCount = 0;
    int errorCount = 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F3A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF14FFEC)),
              const SizedBox(height: 16),
              Text(
                'Импорт глав...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    for (var chapter in selectedChapters) {
      try {
        final payload = {
          'title': chapter['title']!,
          'content': chapter['content']!,
          'chapterOrder': int.parse(chapter['order']!),
        };

        final res = await http.post(
          Uri.parse('$baseUrl/books/${widget.bookId}/chapters'),
          headers: headers,
          body: jsonEncode(payload),
        );

        if (res.statusCode == 200 || res.statusCode == 201) {
          successCount++;
        } else {
          errorCount++;
        }
      } catch (e) {
        errorCount++;
      }
    }

    if (mounted) {
      Navigator.pop(context);
      await _loadChapters();

      if (errorCount == 0) {
        _showSnackBar('Импортировано глав: $successCount');
      } else {
        _showSnackBar(
          'Импортировано: $successCount, Ошибок: $errorCount',
          isError: errorCount > successCount,
        );
      }
    }
  }

  // ========== ДОБАВЛЕНИЕ / РЕДАКТИРОВАНИЕ ==========

  String? _validateChapterData({
    required String title,
    required String content,
    required String order,
  }) {
    if (order.trim().isEmpty) return 'Укажите номер главы';
    final orderNum = int.tryParse(order.trim());
    if (orderNum == null) return 'Номер главы должен быть числом';
    if (orderNum <= 0) return 'Номер главы должен быть больше 0';
    if (title.trim().isEmpty) return 'Введите название главы';
    if (title.trim().length < 3) return 'Название должно содержать минимум 3 символа';
    if (content.trim().isEmpty) return 'Введите содержимое главы';
    if (content.trim().length < 10) return 'Содержимое должно содержать минимум 10 символов';
    return null;
  }

  Future<void> _addOrEditChapter({Map<String, dynamic>? chapter}) async {
    final titleController =
        TextEditingController(text: chapter?['title'] ?? '');
    final contentController =
        TextEditingController(text: chapter?['content'] ?? '');
    final orderController = TextEditingController(
      text: chapter?['chapterOrder']?.toString() ?? '',
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF0A0E27),
                  const Color(0xFF1A1F3A),
                  const Color(0xFF0D7377).withValues(alpha: 0.3),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF14FFEC).withValues(alpha: 0.15),
                          const Color(0xFF0D7377).withValues(alpha: 0.1),
                        ],
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color:
                              const Color(0xFF14FFEC).withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF14FFEC).withValues(alpha: 0.2),
                                const Color(0xFF0D7377).withValues(alpha: 0.1),
                              ],
                            ),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.close,
                                color: Color(0xFF14FFEC)),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF14FFEC)
                                    .withValues(alpha: 0.3),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Icon(
                            chapter == null ? Icons.add : Icons.edit,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ShaderMask(
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                  colors: [
                                    Color(0xFF14FFEC),
                                    Color(0xFF0D7377)
                                  ],
                                ).createShader(bounds),
                                child: Text(
                                  chapter == null
                                      ? 'Добавить главу'
                                      : 'Редактировать главу',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                chapter == null
                                    ? 'Создание новой главы'
                                    : 'Изменение существующей главы',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Глава',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: TextField(
                              controller: orderController,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 16),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: 'Введите номер главы',
                                hintStyle: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.3)),
                                prefixIcon: Icon(Icons.numbers,
                                    color: const Color(0xFF14FFEC)
                                        .withValues(alpha: 0.6)),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.all(16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Название главы',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: TextField(
                              controller: titleController,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 16),
                              decoration: InputDecoration(
                                hintText: 'Введите название главы',
                                hintStyle: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.3)),
                                prefixIcon: Icon(Icons.title,
                                    color: const Color(0xFF14FFEC)
                                        .withValues(alpha: 0.6)),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.all(16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Содержимое главы',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: TextField(
                              controller: contentController,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  height: 1.6),
                              maxLines: 20,
                              decoration: InputDecoration(
                                hintText:
                                    'Введите текст главы...\n\nЗдесь вы можете написать полное содержимое главы.',
                                hintStyle: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.3)),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.all(16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF1A1F3A).withValues(alpha: 0.8),
                          const Color(0xFF0A0E27).withValues(alpha: 0.95),
                        ],
                      ),
                      border: Border(
                        top: BorderSide(
                          color:
                              const Color(0xFF14FFEC).withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  width: 1.5),
                            ),
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text(
                                'Отмена',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Color(0xFF14FFEC),
                                Color(0xFF0D7377)
                              ]),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF14FFEC)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final validationError = _validateChapterData(
                                  title: titleController.text,
                                  content: contentController.text,
                                  order: orderController.text,
                                );
                                if (validationError != null) {
                                  _showSnackBar(validationError,
                                      isError: true);
                                  return;
                                }
                                final payload = {
                                  'title': titleController.text.trim(),
                                  'content': contentController.text.trim(),
                                  'chapterOrder': int.tryParse(
                                          orderController.text.trim()) ??
                                      0,
                                };
                                Navigator.pop(ctx);
                                if (chapter == null) {
                                  await _createChapter(payload);
                                } else {
                                  await _updateChapter(
                                      chapter['id'], payload);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Сохранить главу',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createChapter(Map<String, dynamic> payload) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/books/${widget.bookId}/chapters'),
        headers: headers,
        body: jsonEncode(payload),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        await _loadChapters();
        _showSnackBar('Глава успешно добавлена');
      } else {
        throw Exception('Ошибка: ${res.statusCode}');
      }
    } catch (e) {
      _showSnackBar('Ошибка создания: $e', isError: true);
    }
  }

  Future<void> _updateChapter(int id, Map<String, dynamic> payload) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/books/${widget.bookId}/chapters/$id'),
        headers: headers,
        body: jsonEncode(payload),
      );
      if (res.statusCode == 200) {
        await _loadChapters();
        _showSnackBar('Глава обновлена');
      } else {
        throw Exception('Ошибка: ${res.statusCode}');
      }
    } catch (e) {
      _showSnackBar('Ошибка обновления: $e', isError: true);
    }
  }

  void _showDeleteDialog(int id, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Удалить главу?',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Вы уверены, что хотите удалить главу "$title"?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена',
                style:
                    TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteChapter(id, title);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Удалить',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteChapter(int id, String title) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/books/${widget.bookId}/chapters/$id'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        await _loadChapters();
        _showSnackBar('Глава "$title" удалена');
      } else {
        throw Exception('Ошибка удаления: ${res.statusCode}');
      }
    } catch (e) {
      _showSnackBar('Ошибка удаления: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0A0E27),
              const Color(0xFF1A1F3A),
              const Color(0xFF0D7377).withValues(alpha: 0.3),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF14FFEC).withValues(alpha: 0.2),
                            const Color(0xFF0D7377).withValues(alpha: 0.1),
                          ],
                        ),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Color(0xFF14FFEC)),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) =>
                                const LinearGradient(
                              colors: [
                                Color(0xFF14FFEC),
                                Color(0xFF0D7377)
                              ],
                            ).createShader(bounds),
                            child: const Text(
                              'Главы',
                              style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                          ),
                          Text(
                            widget.bookTitle,
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.6)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Кнопки в режиме выбора
                    if (isSelectionMode) ...[
                      IconButton(
                        icon: const Icon(Icons.select_all,
                            color: Color(0xFF14FFEC)),
                        onPressed: selectedChapterIds.length == chapters.length
                            ? _deselectAllChapters
                            : _selectAllChapters,
                        tooltip: selectedChapterIds.length == chapters.length
                            ? 'Снять все'
                            : 'Выбрать все',
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_sweep,
                            color: Colors.red.shade400),
                        onPressed: _showBulkDeleteDialog,
                        tooltip: 'Удалить выбранные',
                      ),
                    ] else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${chapters.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),

              // Список глав
              Expanded(
                child: loading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(
                                color: Color(0xFF14FFEC)),
                            const SizedBox(height: 16),
                            Text('Загрузка...',
                                style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.6))),
                          ],
                        ),
                      )
                    : chapters.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.menu_book_outlined,
                                    size: 80,
                                    color:
                                        Colors.white.withValues(alpha: 0.3)),
                                const SizedBox(height: 16),
                                Text('Нет глав',
                                    style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.white
                                            .withValues(alpha: 0.6))),
                                const SizedBox(height: 8),
                                Text('Добавьте первую главу',
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white
                                            .withValues(alpha: 0.4))),
                              ],
                            ),
                          )
                        : FadeTransition(
                            opacity: _fadeAnimation,
                            child: RefreshIndicator(
                              onRefresh: _loadChapters,
                              color: const Color(0xFF14FFEC),
                              backgroundColor: const Color(0xFF1A1F3A),
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: chapters.length,
                                itemBuilder: (context, index) {
                                  final c = chapters[index];
                                  final title = c['title'] ?? 'Без названия';
                                  final order = c['chapterOrder'] ?? 0;
                                  final chapterId = c['id'] as int;
                                  final isSelected = selectedChapterIds
                                      .contains(chapterId);

                                  return TweenAnimationBuilder(
                                    duration: Duration(
                                        milliseconds: 300 + (index * 50)),
                                    tween:
                                        Tween<double>(begin: 0, end: 1),
                                    builder: (context, double value,
                                        child) {
                                      return Opacity(
                                        opacity: value,
                                        child: Transform.translate(
                                            offset:
                                                Offset(0, 20 * (1 - value)),
                                            child: child),
                                      );
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(
                                          bottom: 12),
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(16),
                                        gradient: isSelected
                                            ? LinearGradient(
                                                colors: [
                                                  const Color(0xFF14FFEC)
                                                      .withValues(alpha: 0.2),
                                                  const Color(0xFF0D7377)
                                                      .withValues(alpha: 0.15),
                                                ],
                                              )
                                            : LinearGradient(
                                                colors: [
                                                  Colors.white.withValues(
                                                      alpha: 0.05),
                                                  Colors.white.withValues(
                                                      alpha: 0.02),
                                                ],
                                              ),
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(0xFF14FFEC)
                                                  .withValues(alpha: 0.5)
                                              : Colors.white
                                                  .withValues(alpha: 0.1),
                                          width: isSelected ? 2 : 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.2),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 8),
                                        leading: isSelectionMode
                                            ? Checkbox(
                                                value: isSelected,
                                                onChanged: (_) =>
                                                    _toggleChapterSelection(
                                                        chapterId),
                                                activeColor:
                                                    const Color(0xFF14FFEC),
                                                checkColor: Colors.black,
                                                side: BorderSide(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.5),
                                                ),
                                              )
                                            : Container(
                                                width: 50,
                                                height: 50,
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12),
                                                  gradient:
                                                      const LinearGradient(
                                                    colors: [
                                                      Color(0xFF14FFEC),
                                                      Color(0xFF0D7377)
                                                    ],
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: const Color(
                                                              0xFF14FFEC)
                                                          .withValues(
                                                              alpha: 0.3),
                                                      blurRadius: 8,
                                                      spreadRadius: 2,
                                                    ),
                                                  ],
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    '$order',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                        title: Text(
                                          title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            fontSize: 16,
                                          ),
                                        ),
                                        subtitle: Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Глава $order',
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.6),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        onTap: isSelectionMode
                                            ? () =>
                                                _toggleChapterSelection(
                                                    chapterId)
                                            : () => _addOrEditChapter(
                                                chapter: c),
                                        onLongPress: !isSelectionMode
                                            ? () {
                                                _toggleSelectionMode();
                                                _toggleChapterSelection(
                                                    chapterId);
                                              }
                                            : null,
                                        trailing: isSelectionMode
                                            ? null
                                            : Row(
                                                mainAxisSize:
                                                    MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: const Color(
                                                              0xFF14FFEC)
                                                          .withValues(
                                                              alpha: 0.1),
                                                    ),
                                                    child: IconButton(
                                                      icon: const Icon(
                                                          Icons.edit_outlined,
                                                          color: Color(
                                                              0xFF14FFEC)),
                                                      onPressed: () =>
                                                          _addOrEditChapter(
                                                              chapter: c),
                                                      tooltip:
                                                          'Редактировать',
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: Colors.red
                                                          .withValues(
                                                              alpha: 0.1),
                                                    ),
                                                    child: IconButton(
                                                      icon: Icon(
                                                          Icons
                                                              .delete_outline,
                                                          color: Colors
                                                              .red.shade400),
                                                      onPressed: () =>
                                                          _showDeleteDialog(
                                                              c['id'],
                                                              title),
                                                      tooltip: 'Удалить',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: isSelectionMode
          ? FloatingActionButton.extended(
              heroTag: 'cancel_selection',
              onPressed: _toggleSelectionMode,
              backgroundColor: Colors.grey.shade700,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.close),
              label: const Text(
                'Отмена',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (chapters.isNotEmpty)
                  FloatingActionButton(
                    heroTag: 'selection_mode',
                    onPressed: _toggleSelectionMode,
                    backgroundColor: Colors.red.shade700.withValues(alpha: 0.9),
                    foregroundColor: Colors.white,
                    elevation: 2,
                    child: const Icon(Icons.checklist),
                  ),
                if (chapters.isNotEmpty) const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'import_epub',
                  onPressed: _importFromEpub,
                  backgroundColor:
                      const Color(0xFF0D7377).withValues(alpha: 0.9),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  child: const Icon(Icons.upload_file),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF14FFEC), Color(0xFF0D7377)]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF14FFEC).withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: FloatingActionButton.extended(
                    heroTag: 'add_chapter',
                    onPressed: () => _addOrEditChapter(),
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Добавить',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
    );
  }
}
