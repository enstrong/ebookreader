import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../services/admin_service.dart';
import '../../constants/api_constants.dart';

/// Экран добавления книги целиком из EPUB-файла.
///
/// Позволяет администратору выбрать EPUB-файл, автоматически извлечь
/// из него метаданные (название, автор, описание) и все главы,
/// при необходимости отредактировать данные, выбрать обложку и
/// создать книгу вместе со всеми главами за один раз.
class AddBookFromFileScreen extends StatefulWidget {
  final String token;

  const AddBookFromFileScreen({super.key, required this.token});

  @override
  State<AddBookFromFileScreen> createState() => _AddBookFromFileScreenState();
}

class _AddBookFromFileScreenState extends State<AddBookFromFileScreen>
    with SingleTickerProviderStateMixin {
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _descController = TextEditingController();

  File? _cover;
  File? _epubFile;
  String? _epubFileName;
  List<Map<String, String>> _extractedChapters = [];
  List<bool> _selectedChapters = [];
  bool _loading = false;
  bool _epubParsed = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _titleController.dispose();
    _authorController.dispose();
    _descController.dispose();
    super.dispose();
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

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _cover = File(picked.path));
  }

  Future<void> _pickEpubFile() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
      );

      if (result == null) return;

      final file = File(result.files.single.path!);
      setState(() {
        _epubFile = file;
        _epubFileName = result.files.single.name;
        _epubParsed = false;
        _extractedChapters = [];
        _selectedChapters = [];
      });

      await _parseEpubFile(file);
    } catch (e) {
      _showSnackBar('Ошибка выбора файла: $e', isError: true);
    }
  }

  Future<void> _parseEpubFile(File file) async {
    setState(() => _loading = true);

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Ищем content.opf
      ArchiveFile? opfFile;
      String opfDir = '';
      for (var f in archive) {
        if (f.name.endsWith('.opf')) {
          opfFile = f;
          final parts = f.name.split('/');
          opfDir = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') + '/' : '';
          break;
        }
      }

      if (opfFile == null) {
        throw Exception('Не найден файл content.opf в EPUB');
      }

      final opfContent = utf8.decode(opfFile.content as List<int>);
      final opfDoc = XmlDocument.parse(opfContent);

      // Извлекаем метаданные
      final metadataEl = opfDoc.findAllElements('metadata').firstOrNull;
      if (metadataEl != null) {
        final titleEl = metadataEl.findAllElements('dc:title').firstOrNull ??
            metadataEl.findAllElements('title').firstOrNull;
        final authorEl = metadataEl.findAllElements('dc:creator').firstOrNull ??
            metadataEl.findAllElements('creator').firstOrNull;
        final descEl = metadataEl.findAllElements('dc:description').firstOrNull ??
            metadataEl.findAllElements('description').firstOrNull;

        if (titleEl != null && titleEl.innerText.isNotEmpty) {
          _titleController.text = titleEl.innerText.trim();
        }
        if (authorEl != null && authorEl.innerText.isNotEmpty) {
          _authorController.text = authorEl.innerText.trim();
        }
        if (descEl != null && descEl.innerText.isNotEmpty) {
          _descController.text = descEl.innerText.trim();
        }

        // Извлекаем обложку
        try {
          final coverMeta = metadataEl.findAllElements('meta').firstWhere(
            (el) => el.getAttribute('name') == 'cover',
            orElse: () => XmlElement(XmlName('meta')),
          );
          String? coverId = coverMeta.getAttribute('content');
          
          if (coverId != null) {
            final coverItem = opfDoc.findAllElements('item').firstWhere(
              (el) => el.getAttribute('id') == coverId,
              orElse: () => XmlElement(XmlName('item')),
            );
            final coverHref = coverItem.getAttribute('href');
            if (coverHref != null) {
              final fullCoverHref = opfDir + coverHref;
              final coverFile = archive.firstWhere(
                (f) => f.name == fullCoverHref || f.name.endsWith(coverHref),
                orElse: () => ArchiveFile('', 0, []),
              );
              
              if (coverFile.content.isNotEmpty) {
                final tempDir = await getTemporaryDirectory();
                final tempFile = File('${tempDir.path}/extracted_cover.jpg');
                await tempFile.writeAsBytes(coverFile.content as List<int>);
                setState(() => _cover = tempFile);
              }
            }
          }
        } catch (e) {
          print('Ошибка извлечения обложки: $e');
        }
      }

      // Извлекаем главы
      final chapters = <Map<String, String>>[];
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

        // Ищем файл главы (с учётом директории OPF)
        final fullHref = opfDir + href;
        final chapterFile = archive.firstWhere(
          (f) => f.name == fullHref || f.name.endsWith(href),
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

      setState(() {
        _extractedChapters = chapters;
        _selectedChapters = List<bool>.filled(chapters.length, true);
        _epubParsed = true;
        _loading = false;
      });

      if (chapters.isEmpty) {
        _showSnackBar('В файле не найдено глав', isError: true);
      } else {
        _showSnackBar('Найдено ${chapters.length} глав');
      }
    } catch (e) {
      setState(() => _loading = false);
      _showSnackBar('Ошибка парсинга EPUB: $e', isError: true);
    }
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty) {
      _showSnackBar('Введите название книги', isError: true);
      return;
    }
    if (_authorController.text.trim().isEmpty) {
      _showSnackBar('Введите автора', isError: true);
      return;
    }

    final selectedChapters = _extractedChapters
        .asMap()
        .entries
        .where((e) => _selectedChapters[e.key])
        .map((e) => e.value)
        .toList();

    if (selectedChapters.isEmpty) {
      _showSnackBar('Выберите хотя бы одну главу', isError: true);
      return;
    }

    setState(() => _loading = true);

    try {
      // 1. Создаём книгу
      final svc = AdminService(widget.token);
      await svc.addBookMultipart(
        title: _titleController.text.trim(),
        author: _authorController.text.trim(),
        description: _descController.text.trim(),
        coverFile: _cover,
      );

      // 2. Получаем ID созданной книги
      final adminUrl = ApiConstants.adminUrl;
      final booksRes = await http.get(
        Uri.parse('$adminUrl/books'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      );

      if (booksRes.statusCode != 200) {
        throw Exception('Не удалось получить список книг');
      }

      final books = jsonDecode(booksRes.body) as List;
      // Ищем только что созданную книгу по названию
      final newBook = books.lastWhere(
        (b) => b['title'] == _titleController.text.trim(),
        orElse: () => null,
      );

      if (newBook == null) {
        throw Exception('Не удалось найти созданную книгу');
      }

      final bookId = newBook['id'] as int;

      // 3. Добавляем главы
      int successCount = 0;
      int errorCount = 0;

      for (var chapter in selectedChapters) {
        try {
          final payload = {
            'title': chapter['title']!,
            'content': chapter['content']!,
            'chapterOrder': int.parse(chapter['order']!),
          };

          final res = await http.post(
            Uri.parse('$adminUrl/books/$bookId/chapters'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${widget.token}',
            },
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

      if (!mounted) return;
      setState(() => _loading = false);

      if (errorCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Книга добавлена с $successCount главами!',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(20),
          ),
        );
        Navigator.pop(context, true);
      } else {
        _showSnackBar(
          'Книга создана. Глав добавлено: $successCount, ошибок: $errorCount',
          isError: errorCount > successCount,
        );
        if (successCount > 0) Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _loading = false);
      _showSnackBar('Ошибка: $e', isError: true);
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
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                // Header
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
                        color: const Color(0xFF14FFEC).withValues(alpha: 0.2),
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
                          icon: const Icon(Icons.arrow_back,
                              color: Color(0xFF14FFEC)),
                          onPressed: () => Navigator.pop(context),
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
                              color:
                                  const Color(0xFF14FFEC).withValues(alpha: 0.3),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.upload_file,
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
                                colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                              ).createShader(bounds),
                              child: const Text(
                                'Книга из файла',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Загрузка книги из EPUB',
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

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // EPUB file picker
                        _buildSectionLabel('EPUB файл'),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _loading ? null : _pickEpubFile,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _epubFile != null
                                    ? const Color(0xFF14FFEC)
                                        .withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.1),
                                width: _epubFile != null ? 2 : 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        const Color(0xFF14FFEC)
                                            .withValues(alpha: 0.2),
                                        const Color(0xFF0D7377)
                                            .withValues(alpha: 0.1),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _epubFile != null
                                        ? Icons.check_circle_outline
                                        : Icons.file_open_outlined,
                                    color: _epubFile != null
                                        ? const Color(0xFF14FFEC)
                                        : Colors.white.withValues(alpha: 0.5),
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _epubFile != null
                                            ? _epubFileName ?? 'Файл выбран'
                                            : 'Выбрать EPUB файл',
                                        style: TextStyle(
                                          color: _epubFile != null
                                              ? Colors.white
                                              : Colors.white
                                                  .withValues(alpha: 0.5),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (_epubParsed)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Найдено ${_extractedChapters.length} глав',
                                            style: TextStyle(
                                              color: const Color(0xFF14FFEC)
                                                  .withValues(alpha: 0.8),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (_loading)
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF14FFEC),
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  Icon(
                                    Icons.chevron_right,
                                    color:
                                        Colors.white.withValues(alpha: 0.3),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Cover picker
                        _buildSectionLabel('Обложка (необязательно)'),
                        const SizedBox(height: 8),
                        Center(
                          child: GestureDetector(
                            onTap: _pickCover,
                            child: Container(
                              width: 160,
                              height: 220,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: _cover == null
                                    ? LinearGradient(
                                        colors: [
                                          Colors.white.withValues(alpha: 0.05),
                                          Colors.white.withValues(alpha: 0.02),
                                        ],
                                      )
                                    : null,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF14FFEC)
                                        .withValues(alpha: 0.15),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: _cover == null
                                    ? Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(
                                                colors: [
                                                  const Color(0xFF14FFEC)
                                                      .withValues(alpha: 0.2),
                                                  const Color(0xFF0D7377)
                                                      .withValues(alpha: 0.1),
                                                ],
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.add_photo_alternate_rounded,
                                              size: 40,
                                              color: Color(0xFF14FFEC),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Добавить\nобложку',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.5),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Stack(
                                        children: [
                                          Image.file(
                                            _cover!,
                                            width: double.infinity,
                                            height: double.infinity,
                                            fit: BoxFit.cover,
                                          ),
                                          Positioned(
                                            top: 8,
                                            right: 8,
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withValues(alpha: 0.5),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.edit,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Title
                        _buildSectionLabel('Название книги'),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: _titleController,
                          hint: 'Введите название',
                          icon: Icons.book_rounded,
                        ),

                        const SizedBox(height: 20),

                        // Author
                        _buildSectionLabel('Автор'),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: _authorController,
                          hint: 'Введите автора',
                          icon: Icons.person_rounded,
                        ),

                        const SizedBox(height: 20),

                        // Description
                        _buildSectionLabel('Описание'),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: _descController,
                          hint: 'Введите описание',
                          icon: Icons.description_rounded,
                          maxLines: 4,
                        ),

                        // Chapters selection - Collapsible
                        if (_epubParsed && _extractedChapters.isNotEmpty) ...[
                          const SizedBox(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildSectionLabel('Главы для импорта'),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        for (int i = 0;
                                            i < _selectedChapters.length;
                                            i++) {
                                          _selectedChapters[i] = true;
                                        }
                                      });
                                    },
                                    child: const Text(
                                      'Все',
                                      style:
                                          TextStyle(color: Color(0xFF14FFEC)),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        for (int i = 0;
                                            i < _selectedChapters.length;
                                            i++) {
                                          _selectedChapters[i] = false;
                                        }
                                      });
                                    },
                                    child: Text(
                                      'Снять',
                                      style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.5)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                expansionTileTheme: ExpansionTileThemeData(
                                  backgroundColor: Colors.white.withValues(alpha: 0.02),
                                  collapsedBackgroundColor: Colors.transparent,
                                  textColor: const Color(0xFF14FFEC),
                                  collapsedTextColor: Colors.white.withValues(alpha: 0.7),
                                  iconColor: const Color(0xFF14FFEC),
                                  collapsedIconColor: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                              child: ExpansionTile(
                                title: Text(
                                  'Главы для импорта (${_selectedChapters.where((c) => c).length}/${_extractedChapters.length})',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                children: [
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: _extractedChapters.length,
                                    separatorBuilder: (_, __) => Divider(
                                      color: Colors.white.withValues(alpha: 0.05),
                                      height: 1,
                                    ),
                                    itemBuilder: (context, index) {
                                      final chapter = _extractedChapters[index];
                                      return CheckboxListTile(
                                        value: _selectedChapters[index],
                                        onChanged: (value) {
                                          setState(() {
                                            _selectedChapters[index] =
                                                value ?? false;
                                          });
                                        },
                                        title: Text(
                                          chapter['title']!,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        subtitle: Text(
                                          'Глава ${chapter['order']} • ${chapter['content']!.length} символов',
                                          style: TextStyle(
                                            color:
                                                Colors.white.withValues(alpha: 0.4),
                                            fontSize: 11,
                                          ),
                                        ),
                                        activeColor: const Color(0xFF14FFEC),
                                        checkColor: Colors.black,
                                        dense: true,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 40),

                        // Submit button
                        Container(
                          width: double.infinity,
                          height: 58,
                          decoration: BoxDecoration(
                            gradient: _epubParsed && _extractedChapters.isNotEmpty
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF14FFEC),
                                      Color(0xFF0D7377)
                                    ],
                                  )
                                : LinearGradient(
                                    colors: [
                                      Colors.grey.withValues(alpha: 0.3),
                                      Colors.grey.withValues(alpha: 0.2),
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: _epubParsed &&
                                    _extractedChapters.isNotEmpty
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF14FFEC)
                                          .withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ]
                                : [],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: (_loading ||
                                    !_epubParsed ||
                                    _extractedChapters.isEmpty)
                                ? null
                                : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_upload_rounded),
                            label: Text(
                              _loading
                                  ? 'Создание книги...'
                                  : _epubParsed
                                      ? 'Создать книгу с главами'
                                      : 'Сначала выберите EPUB файл',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.7),
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              TextStyle(color: Colors.white.withValues(alpha: 0.3)),
          prefixIcon: maxLines == 1
              ? Icon(icon,
                  color: const Color(0xFF14FFEC).withValues(alpha: 0.6))
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }
}
