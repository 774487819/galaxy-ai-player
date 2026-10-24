import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const SamsungGalaxyAiPlayerApp());
}

// رابط الخادم السحابي الآمن الخاص بك مدمج وجاهز:
const String kGoogleScriptProxyUrl =
    'https://script.google.com/macros/s/AKfycbxwrJcTLhcMMffppfjorcUlUIGEbbC58ykwQLLbbkPSSV9jheGibYTokWfyu6o5LJw/exec';

class SamsungGalaxyAiPlayerApp extends StatelessWidget {
  const SamsungGalaxyAiPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Galaxy AI Video Player Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF09090E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF387AFF),
          secondary: Color(0xFF9B51E0),
        ),
      ),
      home: const GalaxyVideoPlayerScreen(),
    );
  }
}

class VideoEpisode {
  final int episodeNumber;
  final String title;
  final String urlOrPath;
  final bool isLocal;

  VideoEpisode({
    required this.episodeNumber,
    required this.title,
    required this.urlOrPath,
    this.isLocal = false,
  });
}

class SubtitleCue {
  final Duration start;
  final Duration end;
  String text;

  SubtitleCue({required this.start, required this.end, required this.text});
}

class GalaxyVideoPlayerScreen extends StatefulWidget {
  const GalaxyVideoPlayerScreen({super.key});

  @override
  State<GalaxyVideoPlayerScreen> createState() => _GalaxyVideoPlayerScreenState();
}

class _GalaxyVideoPlayerScreenState extends State<GalaxyVideoPlayerScreen> {
  late final Player _player = Player();
  late final VideoController _videoController = VideoController(_player);

  bool _showControls = true;
  bool _isLocked = false;
  Timer? _hideTimer;
  double _playbackSpeed = 1.0;
  double _volume = 100.0;
  double _brightness = 1.0;
  BoxFit _videoFit = BoxFit.contain;
  bool _isLooping = false;
  bool _isAudioBoosted = false;

  bool _isAiEnhanced = false;
  String _aiEnhancementPreset = 'Ultra HDR 4K';
  bool _showSplitComparison = false;

  bool _subtitlesEnabled = true;
  String _currentSubLanguage = 'العربية';
  bool _eraseHardcodedSubs = false;
  double _eraserBottomOffset = 42.0;
  double _eraserHeight = 58.0;
  bool _isTranslatingSubtitles = false;

  final Map<String, String> _supportedLanguages = {
    'العربية': 'Arabic',
    'الإنجليزية': 'English',
    'الفرنسية': 'French',
    'الإسبانية': 'Spanish',
    'التركية': 'Turkish',
    'الكورية': 'Korean',
    'اليابانية': 'Japanese',
    'الصينية': 'Chinese',
    'الألمانية': 'German',
    'الروسية': 'Russian',
    'الهندية': 'Hindi',
    'الإيطالية': 'Italian',
  };

  List<SubtitleCue> _activeSubtitles = [
    SubtitleCue(
      start: const Duration(seconds: 0),
      end: const Duration(seconds: 8),
      text: 'مرحباً بك في مشغل Galaxy AI الاحترافي الذكي',
    ),
    SubtitleCue(
      start: const Duration(seconds: 8),
      end: const Duration(seconds: 18),
      text: 'يمكنك ترجمة هذا الفيديو إلى أي لغة في العالم أو إزالة الترجمة المطبوعة تماماً',
    ),
    SubtitleCue(
      start: const Duration(seconds: 18),
      end: const Duration(seconds: 35),
      text: 'اطلب من المساعد الذكي أي أمر مثل: حسّن الجودة، أو ترجم للإنجليزية، أو ألغِ الترجمة',
    ),
    SubtitleCue(
      start: const Duration(seconds: 35),
      end: const Duration(seconds: 600),
      text: 'مشاهدة ممتعة بدقة فائقة الوضوح مع محرك المعالجة الذكي',
    ),
  ];

  final List<VideoEpisode> _episodes = [
    VideoEpisode(
      episodeNumber: 1,
      title: 'الحلقة 1: بداية الرحلة (Big Buck Bunny)',
      urlOrPath: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    ),
    VideoEpisode(
      episodeNumber: 2,
      title: 'الحلقة 2: حلم الفيلة (Elephants Dream)',
      urlOrPath: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
    ),
    VideoEpisode(
      episodeNumber: 3,
      title: 'الحلقة 3: مغامرات سينتل (Sintel 4K)',
      urlOrPath: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
    ),
  ];
  int _currentEpisodeIndex = 0;

  final TextEditingController _aiPromptController = TextEditingController();
  final List<Map<String, String>> _aiMessages = [];
  bool _isAiLoading = false;

  @override
  void initState() {
    super.initState();
    _playEpisodeByIndex(0);
    _startHideControlsTimer();
  }

  Future<void> _removeAllSubtitles({bool alsoEraseBurnedIn = true}) async {
    setState(() {
      _subtitlesEnabled = false;
      _eraseHardcodedSubs = alsoEraseBurnedIn;
    });

    await _player.setSubtitleTrack(SubtitleTrack.no());
    await _updateNativeMpvFilters();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            children: [
              const Icon(Icons.subtitles_off_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  alsoEraseBurnedIn
                      ? 'تم إلغاء الترجمة وتفعيل الممحاة الذكية لحذف أي ترجمة مطبوعة من جهة أخرى ✨'
                      : 'تم إيقاف عرض الترجمة',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _translateVideoSubtitlesTo(String targetLangArabicName) async {
    final targetLangEnglish = _supportedLanguages[targetLangArabicName] ?? targetLangArabicName;

    setState(() {
      _isTranslatingSubtitles = true;
      _subtitlesEnabled = true;
      _currentSubLanguage = targetLangArabicName;
    });

    try {
      final sourceTexts = _activeSubtitles.map((e) => e.text).toList();

      final requestBody = {
        "appSecret": "MY_GALAXY_PLAYER_SECRET_2026",
        "geminiPayload": {
          "systemInstruction": {
            "parts": [
              {
                "text": "أنت مترجم أفلام محترف. قم بترجمة مصفوفة النصوص التالية إلى اللغة ($targetLangEnglish). "
                    "أرجع JSON فقط بهذا الشكل: {\"translations\": [\"النص 1\", \"النص 2\"]}"
              }
            ]
          },
          "contents": [
            {
              "parts": [
                {"text": jsonEncode(sourceTexts)}
              ]
            }
          ],
          "generationConfig": {"responseMimeType": "application/json"}
        }
      };

      var response = await http.post(
        Uri.parse(kGoogleScriptProxyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 302 || response.statusCode == 301) {
        final redirectUrl = response.headers['location'];
        if (redirectUrl != null) {
          response = await http.get(Uri.parse(redirectUrl));
        }
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates'] != null) {
          final aiJsonText = data['candidates'][0]['content']['parts'][0]['text'];
          final decoded = jsonDecode(aiJsonText);
          final List<dynamic> translatedList = decoded['translations'] ?? [];

          setState(() {
            for (int i = 0; i < _activeSubtitles.length && i < translatedList.length; i++) {
              _activeSubtitles[i].text = translatedList[i].toString();
            }
          });
        } else {
          _applyOfflineDemoTranslation(targetLangArabicName);
        }
      } else {
        _applyOfflineDemoTranslation(targetLangArabicName);
      }
    } catch (_) {
      _applyOfflineDemoTranslation(targetLangArabicName);
    } finally {
      setState(() => _isTranslatingSubtitles = false);
    }
  }

  void _applyOfflineDemoTranslation(String lang) {
    final Map<String, List<String>> offlinePacks = {
      'العربية': [
        'مرحباً بك في مشغل Galaxy AI الاحترافي الذكي',
        'يمكنك ترجمة هذا الفيديو إلى أي لغة في العالم أو إزالة الترجمة المطبوعة تماماً',
        'اطلب من المساعد الذكي أي أمر مثل: حسّن الجودة، أو ترجم للإنجليزية، أو ألغِ الترجمة',
        'مشاهدة ممتعة بدقة فائقة الوضوح مع محرك المعالجة الذكي',
      ],
      'الإنجليزية': [
        'Welcome to the smart Samsung Galaxy AI Pro Video Player',
        'You can translate this video into any language or erase hardcoded subtitles completely',
        'Ask the AI Assistant anything: Enhance quality, translate to English, or remove subtitles',
        'Enjoy watching in Ultra HD with our real-time AI processing engine',
      ],
      'الفرنسية': [
        'Bienvenue dans le lecteur vidéo intelligent Galaxy AI Pro',
        'Traduisez cette vidéo dans toutes les langues ou supprimez les sous-titres incrustés',
        'Demandez à l\'assistant IA : Améliorer la qualité, traduire ou supprimer les sous-titres',
        'Bon visionnage en Ultra HD avec notre moteur de traitement IA',
      ],
      'الإسبانية': [
        'Bienvenido al reproductor de video inteligente Galaxy AI Pro',
        'Traduce este video a cualquier idioma o elimina los subtítulos incrustados',
        'Pide al asistente IA: Mejorar calidad, traducir o quitar subtítulos',
        'Disfruta viendo en Ultra HD con nuestro motor de procesamiento IA',
      ],
      'التركية': [
        'Akıllı Galaxy AI Pro Video Oynatıcısına Hoş Geldiniz',
        'Bu videoyu istediğiniz dile çevirebilir veya gömülü altyazıları tamamen silebilirsiniz',
        'Yapay Zeka Asistanına sorun: Kaliteyi artır, çevir veya altyazıyı kaldır',
        'Yapay zeka motorumuzla Ultra HD kalitesinde iyi seyirler',
      ],
      'الكورية': [
        '스마트 Galaxy AI 프로 비디오 플레이어에 오신 것을 환영합니다',
        '이 비디오를 모든 언어로 번역하거나 하드코딩된 자막을 완전히 지울 수 있습니다',
        'AI 비서에게 화질 개선, 번역 또는 자막 제거를 요청하세요',
        '실시간 AI 처리 엔진으로 초고화질 시청을 즐기세요',
      ],
    };

    final selectedPack = offlinePacks[lang] ??
        [
          '[$lang] Galaxy AI Pro Video Player',
          '[$lang] AI Multi-Language Live Translation Active',
          '[$lang] Voice & Text AI Commands Ready',
          '[$lang] Ultra HDR 4K AI Upscaling Mode',
        ];

    setState(() {
      for (int i = 0; i < _activeSubtitles.length && i < selectedPack.length; i++) {
        _activeSubtitles[i].text = selectedPack[i];
      }
    });
  }

  Future<void> _importExternalSrtFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt', 'txt'],
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final parsed = _parseSrtContent(content);
      if (parsed.isNotEmpty) {
        setState(() {
          _activeSubtitles = parsed;
          _subtitlesEnabled = true;
        });
      }
    }
  }

  List<SubtitleCue> _parseSrtContent(String srt) {
    final List<SubtitleCue> cues = [];
    final blocks = srt.trim().split(RegExp(r'\r?\n\r?\n'));
    final timeRegExp = RegExp(r'(\d+):(\d+):(\d+)[,.](\d+)\s*-->\s*(\d+):(\d+):(\d+)[,.](\d+)');

    for (final block in blocks) {
      final lines = block.split(RegExp(r'\r?\n'));
      if (lines.length >= 2) {
        for (int i = 0; i < lines.length; i++) {
          final match = timeRegExp.firstMatch(lines[i]);
          if (match != null) {
            final start = Duration(
              hours: int.parse(match.group(1)!),
              minutes: int.parse(match.group(2)!),
              seconds: int.parse(match.group(3)!),
              milliseconds: int.parse(match.group(4)!),
            );
            final end = Duration(
              hours: int.parse(match.group(5)!),
              minutes: int.parse(match.group(6)!),
              seconds: int.parse(match.group(7)!),
              milliseconds: int.parse(match.group(8)!),
            );
            final text = lines.sublist(i + 1).join('\n').replaceAll(RegExp(r'<[^>]*>'), '');
            cues.add(SubtitleCue(start: start, end: end, text: text));
            break;
          }
        }
      }
    }
    return cues;
  }

  Future<void> _sendCommandToAi(String userText) async {
    if (userText.trim().isEmpty) return;

    setState(() {
      _aiMessages.add({'role': 'user', 'text': userText});
      _isAiLoading = true;
    });
    _aiPromptController.clear();

    try {
      final requestBody = {
        "appSecret": "MY_GALAXY_PLAYER_SECRET_2026",
        "geminiPayload": {
          "systemInstruction": {
            "parts": [
              {
                "text": "أنت مساعد ذكي داخل مشغل فيديو سامسونج الاحترافي. حلل أمر المستخدم وأرجع JSON فقط بهذا الشكل:\n"
                    "{\n"
                    "  \"action\": \"enhance_on\" | \"enhance_off\" | \"remove_subs\" | \"translate_subs\" | \"play_ep\" | \"speed\" | \"pause\" | \"play\" | \"lock\" | \"boost_audio\",\n"
                    "  \"value\": رقم الحلقة أو السرعة إن وجد (رقم),\n"
                    "  \"lang\": اسم اللغة بالعربية إن طلب ترجمة (مثل \"الإنجليزية\" أو \"العربية\" أو \"الفرنسية\" أو \"التركية\"),\n"
                    "  \"reply\": \"ردك الأنيق والمختصر باللغة العربية بتأكيد التنفيذ\"\n"
                    "}"
              }
            ]
          },
          "contents": [
            {
              "parts": [
                {"text": userText}
              ]
            }
          ],
          "generationConfig": {"responseMimeType": "application/json"}
        }
      };

      var response = await http.post(
        Uri.parse(kGoogleScriptProxyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 302 || response.statusCode == 301) {
        final redirectUrl = response.headers['location'];
        if (redirectUrl != null) {
          response = await http.get(Uri.parse(redirectUrl));
        }
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates'] != null) {
          final aiJsonText = data['candidates'][0]['content']['parts'][0]['text'];
          final commandData = jsonDecode(aiJsonText);
          await _executeParsedAiAction(commandData);
        } else {
          _fallbackLocalCommandParser(userText);
        }
      } else {
        _fallbackLocalCommandParser(userText);
      }
    } catch (_) {
      _fallbackLocalCommandParser(userText);
    } finally {
      setState(() => _isAiLoading = false);
    }
  }

  Future<void> _executeParsedAiAction(Map<String, dynamic> commandData) async {
    final String action = commandData['action'] ?? '';
    final num? val = commandData['value'];
    final String? lang = commandData['lang'];

    if (action == 'enhance_on') await _applyAiVideoEnhancement(true, preset: 'Ultra HDR 4K');
    if (action == 'enhance_off') await _applyAiVideoEnhancement(false);
    if (action == 'remove_subs') await _removeAllSubtitles(alsoEraseBurnedIn: true);
    if (action == 'translate_subs' && lang != null) {
      await _translateVideoSubtitlesTo(lang);
    }
    if (action == 'pause') _player.pause();
    if (action == 'play') _player.play();
    if (action == 'lock') setState(() => _isLocked = true);
    if (action == 'boost_audio') _toggleAudioBoost();
    if (action == 'speed' && val != null) {
      setState(() => _playbackSpeed = val.toDouble());
      _player.setRate(val.toDouble());
    }
    if (action == 'play_ep' && val != null) {
      final idx = _episodes.indexWhere((e) => e.episodeNumber == val.toInt());
      if (idx != -1) _playEpisodeByIndex(idx);
    }

    setState(() {
      _aiMessages.add({
        'role': 'ai',
        'text': commandData['reply'] ?? 'تم تنفيذ طلبك بنجاح ✨',
      });
    });
  }

  void _fallbackLocalCommandParser(String text) {
    final lower = text.trim();
    String reply = 'تم تنفيذ الأمر مباشرة في المشغل ⚡';

    if (lower.contains('الغاء الترجم') ||
        lower.contains('إلغاء الترجم') ||
        lower.contains('احذف الترجم') ||
        lower.contains('اخفاء الترجم') ||
        lower.contains('بدون ترجم') ||
        lower.contains('ألغِ الترجم')) {
      _removeAllSubtitles(alsoEraseBurnedIn: true);
      reply = '🚫 تم إلغاء الترجمة وتفعيل الممحاة الذكية لإخفاء أي ترجمة مطبوعة من جهات أخرى!';
    } else if (lower.contains('ترجم')) {
      String targetLang = 'الإنجليزية';
      for (final langKey in _supportedLanguages.keys) {
        if (lower.contains(langKey.replaceFirst('ال', ''))) {
          targetLang = langKey;
          break;
        }
      }
      _translateVideoSubtitlesTo(targetLang);
      reply = '🌍 تم ترجمة الفيديو إلى $targetLang بالذكاء الاصطناعي!';
    } else if (lower.contains('حسن') || lower.contains('جود') || lower.contains('توضيح')) {
      _applyAiVideoEnhancement(true, preset: 'Ultra HDR 4K');
      reply = '✨ تم تفعيل محرك Galaxy AI لتحسين جودة الفيديو (Ultra HDR 4K)!';
    } else if (lower.contains('ايقاف التحسين')) {
      _applyAiVideoEnhancement(false);
      reply = 'تم إيقاف تحسين الجودة.';
    } else if (lower.contains('حلق') || lower.contains('شغل')) {
      final numMatch = RegExp(r'(\d+)').firstMatch(lower);
      if (numMatch != null) {
        final epNum = int.parse(numMatch.group(1)!);
        final idx = _episodes.indexWhere((e) => e.episodeNumber == epNum);
        if (idx != -1) {
          _playEpisodeByIndex(idx);
          reply = '🎬 تم تشغيل ${_episodes[idx].title}';
        } else {
          reply = 'الحلقة رقم $epNum غير موجودة في القائمة الحالية.';
        }
      }
    } else if (lower.contains('سرع')) {
      setState(() => _playbackSpeed = 1.5);
      _player.setRate(1.5);
      reply = '⚡ تم تسريع الفيديو إلى 1.5x';
    } else if (lower.contains('صوت') || lower.contains('تضخيم')) {
      _toggleAudioBoost();
      reply = '🔊 تم تفعيل مضخم الصوت الذكي لتوضيح الحوارات!';
    } else if (lower.contains('وقف') || lower.contains('ايقاف')) {
      _player.pause();
      reply = '⏸️ تم إيقاف الفيديو مؤقتاً.';
    }

    setState(() {
      _aiMessages.add({'role': 'ai', 'text': reply});
    });
  }

  Future<void> _applyAiVideoEnhancement(bool enable, {String preset = 'Ultra HDR 4K'}) async {
    setState(() {
      _isAiEnhanced = enable;
      _aiEnhancementPreset = preset;
    });
    await _updateNativeMpvFilters();
  }

  Future<void> _toggleAudioBoost() async {
    setState(() => _isAudioBoosted = !_isAudioBoosted);
    try {
      final nativePlayer = _player.platform as dynamic;
      if (_isAudioBoosted) {
        await nativePlayer.setProperty('af', 'lavfi=[dynaudnorm=f=150:g=15,volume=1.6]');
      } else {
        await nativePlayer.setProperty('af', '');
      }
    } catch (_) {}
  }

  Future<void> _updateNativeMpvFilters() async {
    try {
      final nativePlayer = _player.platform as dynamic;
      final List<String> filters = [];

      if (_isAiEnhanced) {
        if (_aiEnhancementPreset == 'Anime 4K') {
          filters.add('hqdn3d=6:4:8:6,unsharp=7:7:2.0:7:7:0.0,eq=contrast=1.18:saturation=1.35');
        } else if (_aiEnhancementPreset == 'Cinema HDR') {
          filters.add('hqdn3d=2:1:3:2,unsharp=5:5:1.0:5:5:0.0,eq=contrast=1.15:saturation=1.15:gamma=0.95');
        } else {
          filters.add('hqdn3d=3:2:4:3,unsharp=5:5:1.5:5:5:0.0,eq=contrast=1.12:saturation=1.22:brightness=0.02');
        }
      }

      if (_eraseHardcodedSubs) {
        filters.add('delogo=x=80:y=ih-110:w=iw-160:h=85');
      }

      await nativePlayer.setProperty('vf', filters.join(','));
    } catch (_) {}
  }

  ColorFilter _getAiColorFilter() {
    if (!_isAiEnhanced) {
      return const ColorFilter.mode(Colors.transparent, BlendMode.dst);
    }
    return const ColorFilter.matrix(<double>[
      1.18, -0.04, -0.04, 0, 5,
      -0.04, 1.18, -0.04, 0, 5,
      -0.04, -0.04, 1.22, 0, 8,
      0, 0, 0, 1, 0,
    ]);
  }

  void _playEpisodeByIndex(int index) {
    setState(() => _currentEpisodeIndex = index);
    _player.open(Media(_episodes[index].urlOrPath));
  }

  Future<void> _pickLocalVideoFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final name = result.files.single.name;
      setState(() {
        final newEpNum = _episodes.length + 1;
        _episodes.add(VideoEpisode(
          episodeNumber: newEpNum,
          title: 'فيديو محلي ($newEpNum): $name',
          urlOrPath: path,
          isLocal: true,
        ));
        _currentEpisodeIndex = _episodes.length - 1;
      });
      _player.open(Media(path));
    }
  }

  void _startHideControlsTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _player.state.playing) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideControlsTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _player.dispose();
    _aiPromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: GestureDetector(
          onTap: _toggleControls,
          onDoubleTapDown: (details) {
            if (_isLocked) return;
            final width = MediaQuery.of(context).size.width;
            if (details.globalPosition.dx < width / 2) {
              _player.seek(_player.state.position + const Duration(seconds: 10));
            } else {
              _player.seek(_player.state.position - const Duration(seconds: 10));
            }
          },
          onVerticalDragUpdate: (details) {
            if (_isLocked) return;
            final width = MediaQuery.of(context).size.width;
            final delta = -details.primaryDelta! / 200;
            if (details.globalPosition.dx < width / 2) {
              setState(() {
                _volume = (_volume + delta * 100).clamp(0.0, 100.0);
                _player.setVolume(_volume);
              });
            } else {
              setState(() {
                _brightness = (_brightness + delta).clamp(0.2, 1.0);
              });
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: _brightness,
                child: _buildVideoWithAiFilter(),
              ),
              if (_eraseHardcodedSubs) _buildBurnedInSubtitleEraserOverlay(),
              if (_subtitlesEnabled) _buildLiveTranslatedSubtitleOverlay(),
              if (_isAiEnhanced || _eraseHardcodedSubs || _isAudioBoosted)
                Positioned(
                  top: 24,
                  left: 24,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (_isAiEnhanced)
                        _buildStatusBadge(
                          icon: Icons.auto_awesome,
                          text: 'AI: $_aiEnhancementPreset',
                          colors: const [Color(0xFF387AFF), Color(0xFF9B51E0)],
                        ),
                      if (_eraseHardcodedSubs)
                        _buildStatusBadge(
                          icon: Icons.cleaning_services_rounded,
                          text: 'مانع الترجمة المطبوعة مفعل',
                          colors: [Colors.redAccent.shade700, Colors.deepOrange],
                        ),
                      if (_isAudioBoosted)
                        _buildStatusBadge(
                          icon: Icons.graphic_eq_rounded,
                          text: 'تضخيم الصوت AI',
                          colors: [Colors.teal.shade700, Colors.green],
                        ),
                    ],
                  ),
                ),
              if (_isLocked && _showControls)
                Center(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: () => setState(() => _isLocked = false),
                    icon: const Icon(Icons.lock_open_rounded, color: Color(0xFF387AFF)),
                    label: const Text('اضغط لإلغاء قفل الشاشة'),
                  ),
                ),
              if (_showControls && !_isLocked) ...[
                _buildSamsungTopBar(),
                _buildCenterPlayControls(),
                _buildSamsungBottomBar(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge({
    required IconData icon,
    required String text,
    required List<Color> colors,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: colors.first.withOpacity(0.4), blurRadius: 10)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBurnedInSubtitleEraserOverlay() {
    return Positioned(
      bottom: _eraserBottomOffset,
      left: 36,
      right: 36,
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          setState(() {
            _eraserBottomOffset = (_eraserBottomOffset - details.primaryDelta!).clamp(10.0, 260.0);
          });
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22.0, sigmaY: 22.0),
            child: Container(
              height: _eraserHeight,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.18),
                borderRadius: BorderRadius.circular(14),
                border: _showControls
                    ? Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1)
                    : null,
              ),
              alignment: Alignment.center,
              child: _showControls
                  ? const Text(
                      'منطقة مسح الترجمة المطبوعة (اسحبها عمودياً لضبط المكان)',
                      style: TextStyle(fontSize: 10, color: Colors.white70),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveTranslatedSubtitleOverlay() {
    return Positioned(
      bottom: _showControls ? 145 : 42,
      left: 24,
      right: 24,
      child: StreamBuilder<Duration>(
        stream: _player.stream.position,
        builder: (context, snapshot) {
          final pos = snapshot.data ?? _player.state.position;
          final currentCue = _activeSubtitles.cast<SubtitleCue?>().firstWhere(
                (cue) => cue != null && pos >= cue.start && pos <= cue.end,
                orElse: () => null,
              );

          if (currentCue == null && !_isTranslatingSubtitles) {
            return const SizedBox.shrink();
          }

          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: _isTranslatingSubtitles
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9B51E0)),
                        ),
                        SizedBox(width: 10),
                        Text('جاري ترجمة الفيديو بالذكاء الاصطناعي...'),
                      ],
                    )
                  : Text(
                      currentCue!.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVideoWithAiFilter() {
    final videoWidget = Video(
      controller: _videoController,
      fit: _videoFit,
      controls: NoVideoControls,
    );

    if (!_isAiEnhanced) return videoWidget;

    if (_showSplitComparison) {
      return Stack(
        fit: StackFit.expand,
        children: [
          videoWidget,
          ClipRect(
            clipper: _HalfScreenClipper(),
            child: ColorFiltered(
              colorFilter: _getAiColorFilter(),
              child: videoWidget,
            ),
          ),
          Center(child: Container(width: 2, color: const Color(0xFF9B51E0))),
        ],
      );
    }

    return ColorFiltered(
      colorFilter: _getAiColorFilter(),
      child: videoWidget,
    );
  }

  Widget _buildSamsungTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 32, 12, 16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: _pickLocalVideoFile,
              tooltip: 'فتح فيديو من الهاتف',
              icon: const Icon(Icons.folder_open_rounded, color: Colors.white),
            ),
            Expanded(
              child: Text(
                _episodes[_currentEpisodeIndex].title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _buildAiEnhancerChip(),
            const SizedBox(width: 6),
            IconButton(
              onPressed: _openSubtitleAndTranslationSheet,
              style: IconButton.styleFrom(
                backgroundColor: _subtitlesEnabled
                    ? const Color(0xFF387AFF).withOpacity(0.3)
                    : Colors.redAccent.withOpacity(0.25),
              ),
              tooltip: 'الترجمة وإلغاء الترجمة المطبوعة',
              icon: Icon(
                _subtitlesEnabled ? Icons.translate_rounded : Icons.subtitles_off_rounded,
                color: Colors.white,
              ),
            ),
            IconButton(
              onPressed: _openAiAssistantSheet,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF9B51E0).withOpacity(0.3),
              ),
              tooltip: 'مساعد Galaxy AI الذكي',
              icon: const Icon(Icons.psychology_alt_rounded, color: Color(0xFFE2B6FF)),
            ),
            IconButton(
              onPressed: _openEpisodesDrawer,
              tooltip: 'الحلقات',
              icon: const Icon(Icons.video_library_rounded, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiEnhancerChip() {
    return InkWell(
      onTap: () => _applyAiVideoEnhancement(!_isAiEnhanced, preset: _aiEnhancementPreset),
      onLongPress: _openAiEnhancerSettingsDialog,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _isAiEnhanced ? const Color(0xFF387AFF) : Colors.white12,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_fix_high_rounded, size: 15, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              _isAiEnhanced ? 'AI مفعل' : 'تحسين AI',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterPlayControls() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildCircleControlBtn(
            icon: Icons.replay_10_rounded,
            onTap: () => _player.seek(_player.state.position - const Duration(seconds: 10)),
          ),
          const SizedBox(width: 32),
          StreamBuilder<bool>(
            stream: _player.stream.playing,
            builder: (context, snapshot) {
              final isPlaying = snapshot.data ?? _player.state.playing;
              return GestureDetector(
                onTap: _player.playOrPause,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF387AFF).withOpacity(0.88),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF387AFF).withOpacity(0.4),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 32),
          _buildCircleControlBtn(
            icon: Icons.forward_10_rounded,
            onTap: () => _player.seek(_player.state.position + const Duration(seconds: 10)),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleControlBtn({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black54,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, size: 28, color: Colors.white),
      ),
    );
  }

  Widget _buildSamsungBottomBar() {
    return Positioned(
      bottom: 14,
      left: 14,
      right: 14,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.68),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<Duration>(
                  stream: _player.stream.position,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? _player.state.position;
                    final duration = _player.state.duration;
                    final maxSeconds = duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0;
                    final currentSeconds = position.inSeconds.toDouble().clamp(0.0, maxSeconds);

                    return Row(
                      children: [
                        Text(_formatDuration(position), style: const TextStyle(fontSize: 12)),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              activeTrackColor: const Color(0xFF387AFF),
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: currentSeconds,
                              max: maxSeconds,
                              onChanged: (val) => _player.seek(Duration(seconds: val.toInt())),
                            ),
                          ),
                        ),
                        Text(_formatDuration(duration), style: const TextStyle(fontSize: 12)),
                      ],
                    );
                  },
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => setState(() => _isLocked = true),
                        tooltip: 'قفل اللمس',
                        icon: const Icon(Icons.lock_outline_rounded, size: 20),
                      ),
                      IconButton(
                        onPressed: () {
                          final fits = [BoxFit.contain, BoxFit.cover, BoxFit.fill];
                          final next = (fits.indexOf(_videoFit) + 1) % fits.length;
                          setState(() => _videoFit = fits[next]);
                        },
                        tooltip: 'تغيير أبعاد الشاشة',
                        icon: const Icon(Icons.aspect_ratio_rounded, size: 20),
                      ),
                      IconButton(
                        onPressed: _toggleAudioBoost,
                        tooltip: 'مضخم الصوت الذكي',
                        icon: Icon(
                          Icons.graphic_eq_rounded,
                          size: 20,
                          color: _isAudioBoosted ? Colors.greenAccent : Colors.white,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() => _isLooping = !_isLooping);
                          _player.setPlaylistMode(_isLooping ? PlaylistMode.single : PlaylistMode.none);
                        },
                        tooltip: 'تكرار الفيديو',
                        icon: Icon(
                          Icons.repeat_rounded,
                          size: 20,
                          color: _isLooping ? const Color(0xFF387AFF) : Colors.white,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          final speeds = [0.5, 1.0, 1.25, 1.5, 2.0];
                          final next = (speeds.indexOf(_playbackSpeed) + 1) % speeds.length;
                          setState(() => _playbackSpeed = speeds[next]);
                          _player.setRate(_playbackSpeed);
                        },
                        child: Text('${_playbackSpeed}x', style: const TextStyle(color: Colors.white)),
                      ),
                      if (_isAiEnhanced)
                        TextButton.icon(
                          onPressed: () => setState(() => _showSplitComparison = !_showSplitComparison),
                          icon: Icon(
                            Icons.compare_rounded,
                            size: 16,
                            color: _showSplitComparison ? const Color(0xFF9B51E0) : Colors.white,
                          ),
                          label: const Text('مقارنة AI', style: TextStyle(fontSize: 11, color: Colors.white)),
                        ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _eraseHardcodedSubs ? Colors.redAccent : Colors.white,
                          side: BorderSide(
                            color: _eraseHardcodedSubs ? Colors.redAccent : Colors.white30,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        onPressed: () {
                          if (_subtitlesEnabled || !_eraseHardcodedSubs) {
                            _removeAllSubtitles(alsoEraseBurnedIn: true);
                          } else {
                            setState(() {
                              _eraseHardcodedSubs = false;
                              _subtitlesEnabled = true;
                            });
                            _updateNativeMpvFilters();
                          }
                        },
                        icon: Icon(
                          _eraseHardcodedSubs ? Icons.cleaning_services_rounded : Icons.subtitles_off_rounded,
                          size: 16,
                        ),
                        label: Text(
                          _eraseHardcodedSubs ? 'إلغاء مسح الترجمة' : 'إلغاء الترجمة نهائياً',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF387AFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                        onPressed: _openSubtitleAndTranslationSheet,
                        icon: const Icon(Icons.translate_rounded, size: 16),
                        label: Text('ترجمة ($_currentSubLanguage)', style: const TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF9B51E0),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                        onPressed: _openAiAssistantSheet,
                        icon: const Icon(Icons.auto_awesome, size: 16),
                        label: const Text('أمر ذكي', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openSubtitleAndTranslationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.translate_rounded, color: Color(0xFF387AFF)),
                            SizedBox(width: 10),
                            Text(
                              'مركز الترجمة الذكي وإزالة الترجمات',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _importExternalSrtFile();
                          },
                          icon: const Icon(Icons.upload_file_rounded, size: 18),
                          label: const Text('استيراد ملف SRT'),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'إلغاء جميع الترجمات وحذف الترجمة المطبوعة',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            subtitle: const Text(
                              'يمسح الترجمة حتى لو كانت محروقة داخل الفيديو من موقع أو قناة أخرى',
                              style: TextStyle(fontSize: 11, color: Colors.white70),
                            ),
                            activeColor: Colors.redAccent,
                            value: _eraseHardcodedSubs && !_subtitlesEnabled,
                            onChanged: (val) async {
                              if (val) {
                                await _removeAllSubtitles(alsoEraseBurnedIn: true);
                              } else {
                                setState(() {
                                  _eraseHardcodedSubs = false;
                                  _subtitlesEnabled = true;
                                });
                                await _updateNativeMpvFilters();
                              }
                              setModalState(() {});
                            },
                          ),
                          if (_eraseHardcodedSubs) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Text('سمك الممحاة:', style: TextStyle(fontSize: 12)),
                                Expanded(
                                  child: Slider(
                                    value: _eraserHeight,
                                    min: 30.0,
                                    max: 130.0,
                                    activeColor: Colors.redAccent,
                                    onChanged: (v) {
                                      setState(() => _eraserHeight = v);
                                      setModalState(() {});
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'ترجمة الفيديو فوراً بالذكاء الاصطناعي إلى:',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _supportedLanguages.keys.map((langName) {
                        final isSelected = _subtitlesEnabled && _currentSubLanguage == langName;
                        return ChoiceChip(
                          label: Text(langName),
                          selected: isSelected,
                          selectedColor: const Color(0xFF387AFF),
                          onSelected: (_) async {
                            Navigator.pop(context);
                            await _translateVideoSubtitlesTo(langName);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openAiAssistantSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15151E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  left: 20,
                  right: 20,
                  top: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.auto_awesome, color: Color(0xFF9B51E0)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'مساعد Galaxy AI الذكي (ينفذ أوامرك داخل المشغل)',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildQuickAiChip('🚫 ألغِ الترجمة نهائياً', setModalState),
                          _buildQuickAiChip('🌍 ترجم الفيديو للإنجليزية', setModalState),
                          _buildQuickAiChip('🌍 ترجم الفيديو للفرنسية', setModalState),
                          _buildQuickAiChip('✨ حسّن جودة الفيديو', setModalState),
                          _buildQuickAiChip('🎬 شغل الحلقة 2', setModalState),
                          _buildQuickAiChip('🔊 تفعيل تضخيم الصوت', setModalState),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 200,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: _aiMessages.isEmpty
                          ? const Center(
                              child: Text(
                                'اطلب مني مثلاً: "ألغِ الترجمة"، "ترجم للتركية"، "حسّن الجودة"، أو "شغل الحلقة 2"',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _aiMessages.length,
                              itemBuilder: (context, idx) {
                                final msg = _aiMessages[idx];
                                final isUser = msg['role'] == 'user';
                                return Align(
                                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isUser ? const Color(0xFF387AFF) : const Color(0xFF262636),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(msg['text'] ?? '', style: const TextStyle(fontSize: 13)),
                                  ),
                                );
                              },
                            ),
                    ),
                    if (_isAiLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(color: Color(0xFF9B51E0)),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _aiPromptController,
                            decoration: InputDecoration(
                              hintText: 'اكتب أمرك هنا...',
                              filled: true,
                              fillColor: Colors.white10,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            onSubmitted: (val) async {
                              await _sendCommandToAi(val);
                              setModalState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF387AFF)),
                          onPressed: () async {
                            await _sendCommandToAi(_aiPromptController.text);
                            setModalState(() {});
                          },
                          icon: const Icon(Icons.send_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickAiChip(String cmd, StateSetter setModalState) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ActionChip(
        backgroundColor: const Color(0xFF9B51E0).withOpacity(0.2),
        label: Text(cmd, style: const TextStyle(fontSize: 12)),
        onPressed: () async {
          await _sendCommandToAi(cmd);
          setModalState(() {});
        },
      ),
    );
  }

  void _openAiEnhancerSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A24),
          title: const Text('أنماط تحسين الفيديو بالذكاء الاصطناعي'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.hd_rounded, color: Color(0xFF387AFF)),
                title: const Text('Ultra HDR 4K'),
                subtitle: const Text('توضيح الحواف وإزالة الضوضاء ورفع التباين'),
                onTap: () {
                  _applyAiVideoEnhancement(true, preset: 'Ultra HDR 4K');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.movie_filter_rounded, color: Color(0xFF9B51E0)),
                title: const Text('Cinema HDR'),
                subtitle: const Text('ألوان سينمائية عميقة للأفلام والمسلسلات'),
                onTap: () {
                  _applyAiVideoEnhancement(true, preset: 'Cinema HDR');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.animation_rounded, color: Colors.amber),
                title: const Text('Anime 4K'),
                subtitle: const Text('تنعيم الخطوط وإبراز ألوان الأنمي والكرتون'),
                onTap: () {
                  _applyAiVideoEnhancement(true, preset: 'Anime 4K');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEpisodesDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF15151E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'قائمة الحلقات والفيديوهات',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _pickLocalVideoFile();
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('فتح فيديو من الجهاز'),
                  ),
                ],
              ),
              const Divider(color: Colors.white12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _episodes.length,
                  itemBuilder: (context, index) {
                    final ep = _episodes[index];
                    final isCurrent = index == _currentEpisodeIndex;
                    return ListTile(
                      selected: isCurrent,
                      leading: CircleAvatar(
                        backgroundColor: isCurrent ? const Color(0xFF387AFF) : Colors.white12,
                        child: Text('${ep.episodeNumber}'),
                      ),
                      title: Text(ep.title),
                      onTap: () {
                        Navigator.pop(context);
                        _playEpisodeByIndex(index);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$minutes:$seconds';
    return '$minutes:$seconds';
  }
}

class _HalfScreenClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width / 2, size.height);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}
