import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:share_plus/share_plus.dart';

class AppLogger {
  static File? _logFile;

  static Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    _logFile = File('${directory.path}/app_logs.txt');
    const startMsg = '\n=== App Started ===';
    debugPrint(startMsg);
    debugPrint('Log file path: ${_logFile!.path}');
    try {
      await _logFile?.writeAsString('$startMsg\n', mode: FileMode.append);
    } catch (e) {
      debugPrint('Failed to write start log: $e');
    }
  }

  static void log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logMsg = '[$timestamp] $message';
    debugPrint(logMsg);
    _logFile?.writeAsStringSync('$logMsg\n', mode: FileMode.append);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.init();
  await NotificationService.init();

  // アプリ全体のエラーをログに記録する設定
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details); // コンソールにもエラーを表示
    AppLogger.log('Flutter Error: ${details.exception}\nStack: ${details.stack}');
  };

  runApp(const AniCheckApp());
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    // タイムゾーンデータベースを初期化
    tz.initializeTimeZones();
    // デバイスのローカルタイムゾーンを設定
    final String timeZoneName = tz.local.name;
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    // Android用の初期化設定
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS/macOS用の初期化設定（通知許可をリクエスト）
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
    );

    await _notificationsPlugin.initialize(initializationSettings);
    AppLogger.log('NotificationService initialized.');
  }

  static Future<void> scheduleNotification(Anime anime) async {
    final id = anime.title.hashCode;
    final timeParts = anime.time.split(':');
    if (timeParts.length != 2) return;

    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    if (hour == null || minute == null) return;

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    // もし今日の放送時間が既に過ぎていたら、明日の同じ時間に予約する
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    // 放送5分前に設定
    final notificationTime = scheduledDate.subtract(const Duration(minutes: 5));

    await _notificationsPlugin.zonedSchedule(
      id,
      'まもなく放送開始',
      anime.title,
      notificationTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'anicheck_channel_id',
          'AniCheck Notifications',
          channelDescription: 'Notifications for upcoming anime broadcasts',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(sound: 'default'),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
    AppLogger.log('Scheduled notification for ${anime.title} at $notificationTime');
  }

  static Future<void> cancelNotification(Anime anime) async {
    final id = anime.title.hashCode;
    await _notificationsPlugin.cancel(id);
    AppLogger.log('Canceled notification for ${anime.title}');
  }

  // テスト用：30秒後に通知
  static Future<void> scheduleTestNotification(Anime anime) async {
    final id = anime.title.hashCode + 1000; // 通常の通知IDと被らないようにする
    final notificationTime = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 30));

    await _notificationsPlugin.zonedSchedule(
      id,
      'テスト通知',
      '${anime.title} のテスト通知です',
      notificationTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'anicheck_channel_id',
          'AniCheck Notifications',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(sound: 'default'),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
    AppLogger.log('Scheduled TEST notification for ${anime.title} at $notificationTime');
  }
}

// --- 新しいデータモデル定義 ---

class AnimeMaster {
  final String animeId;
  final String title;
  final String officialUrl;
  final String hashtag;
  final String stationMaster;
  final String? baseOpYoutubeId;
  final Map<String, dynamic> sources;

  AnimeMaster({
    required this.animeId,
    required this.title,
    required this.officialUrl,
    required this.hashtag,
    required this.stationMaster,
    this.baseOpYoutubeId,
    required this.sources,
  });

  factory AnimeMaster.fromJson(Map<String, dynamic> json) {
    return AnimeMaster(
      animeId: json['anime_id'] ?? '',
      title: json['title'] ?? '',
      officialUrl: json['official_url'] ?? '',
      hashtag: json['hashtag'] ?? '',
      stationMaster: json['station_master'] ?? '',
      baseOpYoutubeId: json['base_op_youtube_id'],
      sources: json['sources'] ?? {},
    );
  }
}

class AnimeEpisode {
  final String animeId;
  final int epNum;
  final String title;
  final String prevSummary;
  final String? nextPreviewYoutubeId;
  final int? originalVol;

  AnimeEpisode({
    required this.animeId,
    required this.epNum,
    required this.title,
    required this.prevSummary,
    this.nextPreviewYoutubeId,
    this.originalVol,
  });

  factory AnimeEpisode.fromJson(Map<String, dynamic> json) {
    return AnimeEpisode(
      animeId: json['anime_id'] ?? '',
      epNum: json['ep_num'] ?? 0,
      title: json['title'] ?? '',
      prevSummary: json['prev_summary'] ?? '',
      nextPreviewYoutubeId: json['next_preview_youtube_id'],
      originalVol: json['original_vol'],
    );
  }
}

class AnimeSchedule {
  final String animeId;
  final int epNum;
  final String stationId;
  final DateTime startTime;
  final String status;

  AnimeSchedule({
    required this.animeId,
    required this.epNum,
    required this.stationId,
    required this.startTime,
    required this.status,
  });

  factory AnimeSchedule.fromJson(Map<String, dynamic> json) {
    DateTime parsedTime;
    final timeString = json['start_time'];
    try {
      if (timeString == null || timeString.toString().isEmpty) {
        throw const FormatException('start_time is null or empty');
      }
      
      // AIがよくやる "24:xx" 表記を "00:xx" の翌日に直す簡易補正（必要なら）
      // 標準のDateTime.parseは "24:00:00" で落ちることがある
      String safeTimeString = timeString.toString();
      if (safeTimeString.contains('T24:')) {
        safeTimeString = safeTimeString.replaceFirst('T24:', 'T00:');
        // 本当は日付も1日進めるべきだが、パース落ち回避を優先
      } else if (safeTimeString.contains('T25:')) {
        safeTimeString = safeTimeString.replaceFirst('T25:', 'T01:');
      } else if (safeTimeString.contains('T26:')) {
        safeTimeString = safeTimeString.replaceFirst('T26:', 'T02:');
      }
      
      parsedTime = DateTime.parse(safeTimeString);
    } catch (e) {
      AppLogger.log('⚠️ [Warning] Failed to parse start_time for anime_id: ${json['anime_id']}. Value was: "$timeString". Error: $e');
      // パース失敗時はアプリがクラッシュしないよう、現在時刻を入れる（または1970年など）
      parsedTime = DateTime.now(); 
    }

    return AnimeSchedule(
      animeId: json['anime_id'] ?? '',
      epNum: json['ep_num'] ?? 0,
      stationId: json['station_id'] ?? '',
      startTime: parsedTime,
      status: json['status'] ?? '',
    );
  }
}

class AnimeGoods {
  final String type;
  final String name;
  final String url;

  AnimeGoods({
    required this.type,
    required this.name,
    required this.url,
  });

  factory AnimeGoods.fromJson(Map<String, dynamic> json) {
    return AnimeGoods(
      type: json['type'] ?? '',
      name: json['name'] ?? '',
      url: json['url'] ?? '',
    );
  }
}

class SourceLinks {
  final String? webNovel;
  final String? lightNovelAmazon;
  final String? mangaAmazon;
  final List<AnimeGoods>? goods;

  SourceLinks({
    this.webNovel,
    this.lightNovelAmazon,
    this.mangaAmazon,
    this.goods,
  });

  factory SourceLinks.fromJson(Map<String, dynamic> json) {
    return SourceLinks(
      webNovel: json['web_novel'],
      lightNovelAmazon: json['light_novel_amazon'],
      mangaAmazon: json['manga_amazon'],
      goods: (json['goods'] as List?)?.map((i) => AnimeGoods.fromJson(i)).toList(),
    );
  }
}

class Anime {
  final String id;
  final String time;
  final String title;
  final int? epNum;
  final String? episodeTitle;
  final String station;
  final String? status;
  final int? originalVol;
  final String? previewYoutubeId;
  final String? opYoutubeId;
  final String? amazonKindleUrl;
  bool isNotified;
  final SourceLinks? sourceLinks;
  final String? summary;

  Anime({
    required this.id,
    required this.time,
    required this.title,
    this.epNum,
    this.episodeTitle,
    required this.station,
    this.status,
    this.originalVol,
    this.previewYoutubeId,
    this.opYoutubeId,
    this.amazonKindleUrl,
    required this.isNotified,
    this.sourceLinks,
    this.summary,
  });

  factory Anime.fromJson(Map<String, dynamic> json) {
    return Anime(
      id: json['anime_id'] ?? '',
      time: json['time'],
      title: json['title'],
      epNum: json['ep_num'],
      episodeTitle: json['episode_title'],
      station: json['station'],
      status: json['status'],
      originalVol: json['original_vol'],
      previewYoutubeId: json['preview_youtube_id'],
      opYoutubeId: json['op_youtube_id'],
      amazonKindleUrl: json['amazon_kindle_url'],
      isNotified: json['isNotified'] ?? false,
      sourceLinks: json['source_links'] != null ? SourceLinks.fromJson(json['source_links']) : null,
      summary: json['summary'],
    );
  }
}

class AniCheckApp extends StatelessWidget {
  const AniCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'アニちぇっく',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        // 白と青（#1A73E8）を基調とした清潔感のあるスタイル
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          primary: const Color(0xFF1A73E8),
          background: Colors.white,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  List<String> _selectedStations = [];
  bool _isLoading = true;
  late Future<List<Anime>> _animeListFuture;

  // 放送局のプリセット定義
  final Map<String, List<String>> _stationPresets = {
    '関東広域圏 (TOKYO MX中心)': ['mx', 'tx', 'ntv', 'tbs', 'fujitv', 'tv_asahi'],
    '関西広域圏 (MBS中心)': ['mbs', 'ytv', 'ktv', 'abc', 'sun', 'tv_osaka'],
    '中京広域圏 (メ〜テレ中心)': ['tva', 'nagoya_tv', 'cbc', 'tokai_tv', 'ctv'],
    'BS / 全国ネット中心': ['bs11', 'bs_fuji', 'bs_tbs', 'bs_ntv', 'nhk'],
    'ネット配信最速 (Abema等)': ['abema', 'prime_video', 'netflix', 'u_next'],
  };

  // アプリで扱うすべての放送局ID（手動カスタマイズ用）
  final Map<String, String> _allAvailableStations = {
    'mx': 'TOKYO MX',
    'tx': 'テレビ東京',
    'ntv': '日本テレビ',
    'tbs': 'TBS',
    'fujitv': 'フジテレビ',
    'tv_asahi': 'テレビ朝日',
    'mbs': 'MBS',
    'ytv': '読売テレビ',
    'ktv': '関西テレビ',
    'abc': 'ABCテレビ',
    'sun': 'サンテレビ',
    'tv_osaka': 'テレビ大阪',
    'tva': 'テレビ愛知',
    'nagoya_tv': 'メ〜テレ',
    'cbc': 'CBC',
    'tokai_tv': '東海テレビ',
    'ctv': '中京テレビ',
    'bs11': 'BS11',
    'bs_fuji': 'BSフジ',
    'bs_tbs': 'BS-TBS',
    'bs_ntv': 'BS日テレ',
    'nhk': 'NHK',
    'abema': 'AbemaTV',
    'prime_video': 'Prime Video',
    'netflix': 'Netflix',
    'u_next': 'U-NEXT',
    'tokyomx': 'TOKYO MX', // 表記ゆれ対応
  };

  @override
  void initState() {
    super.initState();
    _loadStationFilter();
    _animeListFuture = _loadAnimeList();
  }

  // 設定の読み込み
  Future<void> _loadStationFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _selectedStations = prefs.getStringList('selected_stations') ?? [];
        _isLoading = false;
      });

      // 初回起動時はダイアログを表示
      if (_selectedStations.isEmpty && mounted) {
        _showFilterDialog();
      }
      AppLogger.log('Stations loaded: ${_selectedStations.length} stations');
    } catch (e) {
      AppLogger.log('初期化エラー: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 設定の保存とリストの再読み込み
  Future<void> _saveStationFilter(List<String> stations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('selected_stations', stations);
    AppLogger.log('Stations saved: ${stations.length} stations');
    setState(() {
      _selectedStations = stations;
      // フィルターが変わったのでリストを再読み込み
      _animeListFuture = _loadAnimeList();
    });
  }

  // JSONファイルからアニメデータを読み込む
  Future<List<Anime>> _loadAnimeList() async {
    AppLogger.log('Loading anime list from 3 sources...');
    try {
      // 読み込み中の表示を確認しやすくするために少し遅延を入れる（本番では不要）
      await Future.delayed(const Duration(seconds: 1));

      // GitHubの生データURL
      const baseUrl = 'https://raw.githubusercontent.com/lalate/anicheck-data/master/current';
      
      // daily_schedule.jsonを取得
      final scheduleResponse = await http.get(Uri.parse('$baseUrl/daily_schedule.json'));
      if (scheduleResponse.statusCode != 200) {
        throw Exception('Failed to load daily_schedule.json: ${scheduleResponse.statusCode}');
      }
      
      // UTF-8でデコードしてパース
      final String scheduleJsonString = utf8.decode(scheduleResponse.bodyBytes);
      final List<dynamic> schedulesJson = json.decode(scheduleJsonString);
      final schedules = schedulesJson.map((j) => AnimeSchedule.fromJson(j)).toList();

      final List<Anime> mergedList = [];
      final prefs = await SharedPreferences.getInstance();

      // 各アニメの詳細情報を並行して取得
      await Future.wait(schedules.map((schedule) async {
        try {
          // MasterデータとEpisodeデータを同時に取得
          final masterResFuture = http.get(Uri.parse('$baseUrl/${schedule.animeId}_master.json'));
          final episodeResFuture = http.get(Uri.parse('$baseUrl/${schedule.animeId}_episode.json'));

          final responses = await Future.wait([masterResFuture, episodeResFuture]);
          final masterRes = responses[0];
          final episodeRes = responses[1];

          AnimeMaster master;
          if (masterRes.statusCode == 200) {
            final decoded = json.decode(utf8.decode(masterRes.bodyBytes));
            master = AnimeMaster.fromJson(decoded);
          } else {
            master = AnimeMaster(animeId: schedule.animeId, title: 'Unknown', officialUrl: '', hashtag: '', stationMaster: '', sources: {});
          }

          AnimeEpisode episode;
          if (episodeRes.statusCode == 200) {
            final decoded = json.decode(utf8.decode(episodeRes.bodyBytes));
            episode = AnimeEpisode.fromJson(decoded);
          } else {
            episode = AnimeEpisode(animeId: schedule.animeId, epNum: schedule.epNum, title: '', prevSummary: '');
          }

          // 時間のフォーマット (HH:mm)
          final dt = schedule.startTime;
          final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

          // 保存された通知設定を読み込む
          final notifyKey = 'notify_${master.title}';
          final isNotified = prefs.getBool(notifyKey) ?? false;

          // 放送局が選択リストに含まれているかチェック (空の場合はすべて表示)
          final stationLower = schedule.stationId.toLowerCase();
          if (_selectedStations.isEmpty || _selectedStations.contains(stationLower)) {
            mergedList.add(Anime(
              id: schedule.animeId,
              time: timeStr,
              title: master.title,
              epNum: schedule.epNum,
              episodeTitle: episode.title,
              station: master.stationMaster, // Masterの放送局名を使用
              status: schedule.status,
              originalVol: episode.originalVol,
              previewYoutubeId: episode.nextPreviewYoutubeId,
              opYoutubeId: master.baseOpYoutubeId,
              amazonKindleUrl: master.sources['manga_amazon'],
              isNotified: isNotified,
              sourceLinks: SourceLinks.fromJson(master.sources),
              summary: episode.prevSummary,
            ));
          }
        } catch (e) {
          AppLogger.log('Error processing anime ${schedule.animeId}: $e');
        }
      }));

      // 放送時間順にソート
      mergedList.sort((a, b) => a.time.compareTo(b.time));

      AppLogger.log('Loaded ${mergedList.length} items from GitHub data (Filtered).');
      return mergedList;
    } catch (e) {
      AppLogger.log('Error loading anime list: $e');
      rethrow;
    }
  }

  // 通知設定の保存と状態更新
  Future<void> _saveNotificationState(Anime anime, bool isNotified) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notify_${anime.title}', isNotified);
    AppLogger.log('Saved notification state for ${anime.title}: $isNotified');

    if (isNotified) {
      await NotificationService.scheduleNotification(anime);
    } else {
      await NotificationService.cancelNotification(anime);
    }

    setState(() {
      anime.isNotified = isNotified;
    });
  }

  void _showFilterDialog() {
    List<String> tempSelected = List.from(_selectedStations);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.9,
              minChildSize: 0.5,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, controller) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('視聴環境のカスタマイズ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          TextButton(
                            onPressed: () {
                              _saveStationFilter(tempSelected);
                              Navigator.pop(context);
                            },
                            child: const Text('完了'),
                          )
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: controller,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Text('プリセットから選ぶ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                          ),
                          ..._stationPresets.entries.map((entry) {
                            return ListTile(
                              title: Text(entry.key),
                              trailing: OutlinedButton(
                                onPressed: () {
                                  setModalState(() {
                                    // 既存の選択をクリアしてプリセットで上書きするか、追加するか
                                    // ここでは分かりやすさのため上書きにする
                                    tempSelected = List.from(entry.value);
                                  });
                                },
                                child: const Text('適用'),
                              ),
                            );
                          }).toList(),
                          const Divider(),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Text('個別にカスタマイズ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                          ),
                          ..._allAvailableStations.entries.map((entry) {
                            final isSelected = tempSelected.contains(entry.key);
                            return CheckboxListTile(
                              title: Text(entry.value),
                              value: isSelected,
                              onChanged: (bool? value) {
                                setModalState(() {
                                  if (value == true) {
                                    tempSelected.add(entry.key);
                                  } else {
                                    tempSelected.remove(entry.key);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'アニちぇっく',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: TextButton.icon(
              onPressed: _showFilterDialog,
              icon: const Icon(Icons.tune, size: 18),
              label: Text(_selectedStations.isEmpty ? 'すべて表示' : '${_selectedStations.length}局選択中'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).primaryColor,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            color: const Color(0xFFF8F9FA),
            child: Text(
              '本日の放送リスト',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Anime>>(
              future: _animeListFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('エラーが発生しました: ${snapshot.error}'));
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('データがありません'));
                }

                final animeList = snapshot.data!;
                return ListView.separated(
                  itemCount: animeList.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) {
                    final anime = animeList[index];
                final isNotified = anime.isNotified;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  onTap: () {
                    AppLogger.log('Opening detail screen for: ${anime.title}');
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => AnimeDetailScreen(
                          anime: anime, // Pass the Anime object
                          initialIsNotified: isNotified,
                          onToggleNotification: (newValue) {
                            _saveNotificationState(anime, newValue);
                          },
                        ),
                      ),
                    );
                  },
                  leading: Text(
                    anime.time,
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  title: Text( // Access properties directly
                    anime.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(anime.station),
                  trailing: IconButton(
                    icon: Icon(
                      isNotified ? Icons.notifications : Icons.notifications_none,
                      color: isNotified ? Colors.orange : Colors.grey,
                    ),
                    onPressed: () {
                      final newState = !isNotified;
                      _saveNotificationState(anime, newState);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              '${anime.title} の通知を${newState ? "ON" : "OFF"}にしました'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                );
              },
            );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AnimeDetailScreen extends StatefulWidget {
  final Anime anime;
  final bool initialIsNotified;
  final ValueChanged<bool> onToggleNotification;

  const AnimeDetailScreen({
    super.key,
    required this.anime,
    required this.initialIsNotified,
    required this.onToggleNotification,
  });

  @override
  State<AnimeDetailScreen> createState() => _AnimeDetailScreenState();
}

class _AnimeDetailScreenState extends State<AnimeDetailScreen> {
  late bool _isNotified;
  SpoilerMode _currentSpoilerMode = SpoilerMode.clean;

  @override
  void initState() {
    super.initState();
    _isNotified = widget.initialIsNotified;
  }

  void _toggleNotification() {
    final newState = !_isNotified;
    AppLogger.log('Toggled notification for ${widget.anime.title} on detail: $newState');
    setState(() {
      _isNotified = newState;
    });
    widget.onToggleNotification(_isNotified);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.anime.title} の通知を${_isNotified ? "ON" : "OFF"}にしました'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _launchURL(BuildContext context, String? urlString) async {
    if (urlString == null) return;
    final Uri url = Uri.parse(urlString);
    AppLogger.log('Launching URL: $urlString');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      AppLogger.log('Failed to launch URL: $urlString');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('URLを開けませんでした: $urlString')),
        );
      }
    }
  }

  Future<void> _addToCalendar(BuildContext context) async {
    AppLogger.log('Attempting to add event to calendar...');
    // 1. 放送日時を計算
    final timeParts = widget.anime.time.split(':');
    if (timeParts.length != 2) return;
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    if (hour == null || minute == null) return;

    final now = DateTime.now();
    DateTime startTime = DateTime(now.year, now.month, now.day, hour, minute);
    // もし今日の放送時間が既に過ぎていたら、明日の同じ時間に設定
    if (startTime.isBefore(now)) {
      startTime = startTime.add(const Duration(days: 1));
    }
    // 放送時間は30分と仮定
    final endTime = startTime.add(const Duration(minutes: 30));

    // iCalendar形式の日時文字列に変換 (例: 20260223T140000Z)
    String toIcalFormat(DateTime dt) {
      return dt.toUtc().toIso8601String().replaceAll(RegExp(r'[-:.]'), '').substring(0, 15) + 'Z';
    }

    // 2. UIDを生成 (タイトルとエピソード番号でユニークに)
    final uniquePart = widget.anime.epNum?.toString() ?? startTime.toIso8601String().substring(0, 10);
    final uid = '${widget.anime.title}-$uniquePart@anicheck.app';

    // 3. iCalendar (.ics) ファイルの内容を生成
    final icsContent = """
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//AniCheckApp//EN
BEGIN:VEVENT
UID:$uid
DTSTAMP:${toIcalFormat(DateTime.now())}
DTSTART:${toIcalFormat(startTime)}
DTEND:${toIcalFormat(endTime)}
SUMMARY:【放送】${widget.anime.title}
DESCRIPTION:アニメ「${widget.anime.title}」の放送時間です。
BEGIN:VALARM
TRIGGER:-PT5M
ACTION:DISPLAY
DESCRIPTION:まもなく放送開始: ${widget.anime.title}
END:VALARM
END:VEVENT
END:VCALENDAR
""";

    // 4. 一時ファイルに保存して共有インテントを開く
    try {
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/anicheck_event.ics';
      final file = File(filePath);
      await file.writeAsString(icsContent);
      AppLogger.log('Generated iCal file at $filePath');

      final box = context.findRenderObject() as RenderBox?;
      final sharePositionOrigin = box!.localToGlobal(Offset.zero) & box.size;

      await Share.shareXFiles(
        [XFile(filePath, mimeType: 'text/calendar')],
        text: 'カレンダーに予定を追加',
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (e) {
      AppLogger.log('Error creating or sharing iCal file: $e');
    }
  }

  void _shareOnX() {
    final animeTitle = widget.anime.title;
    final text = '「$animeTitle」を今見てる！ #アニちぇっく';
    // ハッシュタグ用にタイトルから空白や記号を削除
    final hashtag = animeTitle.replaceAll(RegExp(r"[\s/:!?'.,]"), '');
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // キーボード表示時にUIが隠れないようにする
      builder: (context) {
        return ComposeXPostSheet(initialText: text, hashtag: hashtag, spoilerMode: _currentSpoilerMode);
      },
    );
  }

  // Amazon URLにアフィリエイトタグを付与する関数
  String _buildAmazonUrl(String url) {
    // TODO: ここにあなたのアフィリエイトIDを設定してください
    const String affiliateTag = 'anicheck-22';
    try {
      final uri = Uri.parse(url);
      final newQueryParameters = Map<String, String>.from(uri.queryParameters);
      newQueryParameters['tag'] = affiliateTag;
      return uri.replace(queryParameters: newQueryParameters).toString();
    } catch (e) {
      AppLogger.log('Failed to build Amazon URL: $e');
      return url;
    }
  }

  Widget _buildYoutubeThumbnail(BuildContext context, String youtubeId, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _launchURL(
            context,
            'https://www.youtube.com/watch?v=$youtubeId',
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                child: Image.network(
                  'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg',
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: double.infinity,
                      height: 200,
                      color: Colors.grey[300],
                      child: const Center(child: Icon(Icons.broken_image)),
                    );
                  },
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(12),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  IconData _getIconForGoodsType(String type) {
    type = type.toLowerCase();
    if (type.contains('blu-ray') || type.contains('dvd') || type.contains('円盤')) {
      return Icons.album_outlined;
    } else if (type.contains('figure') || type.contains('フィギュア')) {
      return Icons.accessibility_new_outlined;
    } else if (type.contains('book') || type.contains('本') || type.contains('コミック')) {
      return Icons.menu_book_outlined;
    } else if (type.contains('music') || type.contains('cd') || type.contains('音楽')) {
      return Icons.music_note_outlined;
    }
    return Icons.shopping_bag_outlined;
  }

  // セクションを生成するヘルパー
  Widget _buildSection(BuildContext context, {required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        child,
        const Divider(height: 48),
      ],
    );
  }

  // SliverAppBar用ヘッダー背景（サムネイル＋グラデーション）
  Widget _buildHeaderBackground(String youtubeId) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              Container(color: Colors.grey[800]),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withOpacity(0.7),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final headerYoutubeId =
        widget.anime.previewYoutubeId ?? widget.anime.opYoutubeId ?? '';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220.0,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.anime.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
              background: headerYoutubeId.isNotEmpty
                  ? _buildHeaderBackground(headerYoutubeId)
                  : null,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: _shareOnX,
              ),
              IconButton(
                icon: const Icon(Icons.hourglass_bottom),
                tooltip: '30秒後にテスト通知',
                onPressed: () {
                  NotificationService.scheduleTestNotification(widget.anime);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('30秒後にテスト通知を予約しました')),
                  );
                },
              ),
              IconButton(
                icon: Icon(_isNotified
                    ? Icons.notifications
                    : Icons.notifications_none),
                color: _isNotified ? Colors.orange : Colors.grey,
                onPressed: _toggleNotification,
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // エピソードタイトル
                  if (widget.anime.episodeTitle != null &&
                      widget.anime.episodeTitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        '#${widget.anime.epNum} ${widget.anime.episodeTitle}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  // 情報チップ（話数・放送局・ステータス）
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (widget.anime.epNum != null)
                        Chip(label: Text('第${widget.anime.epNum}話')),
                      Chip(label: Text(widget.anime.station)),
                      if (widget.anime.status != null &&
                          widget.anime.status!.isNotEmpty)
                        Chip(label: Text(widget.anime.status!)),
                    ],
                  ),
                  const Divider(height: 48),
                  // 次回予告
                  if (widget.anime.previewYoutubeId != null)
                    _buildYoutubeThumbnail(
                        context, widget.anime.previewYoutubeId!, '次回予告'),
                  // あらすじ
                  _buildSection(
                    context,
                    title: 'あらすじ',
                    child: Text(
                      widget.anime.summary ?? 'あらすじ情報がありません。',
                      style: const TextStyle(height: 1.6, color: Colors.black87),
                    ),
                  ),
                  // オープニング
                  if (widget.anime.opYoutubeId != null)
                    _buildYoutubeThumbnail(
                        context, widget.anime.opYoutubeId!, 'オープニング'),
                  // 関連ポスト
                  _buildSection(
                    context,
                    title: '関連ポスト',
                    child: SizedBox(
                      height: 400,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12.0),
                        child: HashtagWebView(
                          hashtag: widget.anime.title,
                          onSpoilerModeChanged: (mode) => setState(() => _currentSpoilerMode = mode),
                        ),
                      ),
                    ),
                  ),
                  // 原作ボタン
                  if (widget.anime.originalVol != null &&
                      widget.anime.sourceLinks?.mangaAmazon != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Center(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final url = _buildAmazonUrl(
                                widget.anime.sourceLinks!.mangaAmazon!);
                            _launchURL(context, url);
                          },
                          icon: const Icon(Icons.book_outlined),
                          label: Text(
                              '原作 第${widget.anime.originalVol}巻を読む (Kindle)'),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: const Color(0xFFF09819),
                          ),
                        ),
                      ),
                    ),
                  // 関連グッズ・円盤カルーセル
                  if (widget.anime.sourceLinks?.goods != null &&
                      widget.anime.sourceLinks!.goods!.isNotEmpty)
                    _buildSection(
                      context,
                      title: '関連グッズ・円盤',
                      child: SizedBox(
                        height: 110,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.anime.sourceLinks!.goods!.length,
                          itemBuilder: (context, index) {
                            final item =
                                widget.anime.sourceLinks!.goods![index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: GestureDetector(
                                onTap: () => _launchURL(context, item.url),
                                child: Card(
                                  child: SizedBox(
                                    width: 120,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                              _getIconForGoodsType(item.type),
                                              size: 32),
                                          const SizedBox(height: 4),
                                          Text(
                                            item.name,
                                            style: const TextStyle(fontSize: 11),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  // 外部リンク
                  _buildSection(
                    context,
                    title: '外部リンク',
                    child: Column(
                      children: [
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: () => _launchURL(
                                context,
                                widget.anime.sourceLinks?.goods?.firstOrNull
                                        ?.url ??
                                    'https://flutter.dev'),
                            icon: const Icon(Icons.public),
                            label: const Text('公式サイトを見る'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton.icon(
                            onPressed: () {
                              final githubUrl =
                                  'https://github.com/lalate/anicheck-data/edit/master/current/${widget.anime.id}_master.json';
                              _launchURL(context, githubUrl);
                            },
                            icon: const Icon(Icons.edit_note, size: 18),
                            label: const Text('番組データを修正する (GitHub)',
                                style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Center(
                    child: Builder(
                      builder: (BuildContext buttonContext) {
                        return OutlinedButton.icon(
                          onPressed: () => _addToCalendar(buttonContext),
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: const Text('カレンダーに追加'),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum TagMode { anicheck, official }

enum SpoilerMode { clean, spoiler }

class HashtagWebView extends StatefulWidget {
  final String hashtag;
  final void Function(SpoilerMode)? onSpoilerModeChanged;

  const HashtagWebView({super.key, required this.hashtag, this.onSpoilerModeChanged});

  @override
  State<HashtagWebView> createState() => _HashtagWebViewState();
}

class _HashtagWebViewState extends State<HashtagWebView> {
  late final WebViewController _controller;
  TagMode _tagMode = TagMode.official;
  SpoilerMode _spoilerMode = SpoilerMode.clean;

  String _buildHtml() {
    final cleanHashtag = widget.hashtag.replaceAll(RegExp(r"[\s/:!?'.,]"), '');
    String query = '#$cleanHashtag';
    if (_tagMode == TagMode.anicheck) query += ' #アニちぇっく';
    if (_spoilerMode == SpoilerMode.clean) {
      query += ' -#ネタバレ';
    } else {
      query += ' #ネタバレ';
    }
    
    final encodedQuery = Uri.encodeComponent(query);
    final searchUrl = 'https://twitter.com/search?q=$encodedQuery';

    return '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body { 
            margin: 0; 
            padding: 0; 
            background-color: transparent; 
            display: flex;
            justify-content: center;
          }
        </style>
      </head>
      <body>
        <a class="twitter-timeline" 
           data-chrome="noheader nofooter noborders transparent"
           data-dnt="true"
           data-theme="dark"
           href="$searchUrl">
           Tweets about $query
        </a>
        <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>
      </body>
      </html>
    ''';
  }

  void _loadUrl() {
    _controller.loadHtmlString(_buildHtml());
  }

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Set a desktop-like user agent to avoid app-opening redirects
      ..setUserAgent('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36')
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            AppLogger.log('WebView loading: $progress%');
          },
          onPageStarted: (String url) {},
          onPageFinished: (String url) {},
          onWebResourceError: (WebResourceError error) {
            AppLogger.log('WebView error: ${error.description}');
          },
          onNavigationRequest: (NavigationRequest request) {
            if (!request.url.startsWith('http')) {
              AppLogger.log('Blocked navigation to: ${request.url}');
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    // Android specific settings for Twitter widget
    if (Platform.isAndroid) {
      final androidController = _controller.platform as AndroidWebViewController;
      androidController.setMixedContentMode(MixedContentMode.alwaysAllow);
    }

    // setBackgroundColor is not supported on macOS, so we only call it on other platforms.
    if (!Platform.isMacOS) {
      _controller.setBackgroundColor(const Color(0x00000000));
    }
    _loadUrl();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: CupertinoSegmentedControl<TagMode>(
            groupValue: _tagMode,
            children: const {
              TagMode.official: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('公式タグ'),
              ),
              TagMode.anicheck: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('アニちぇっくID'),
              ),
            },
            onValueChanged: (value) {
              setState(() => _tagMode = value);
              _loadUrl();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: CupertinoSegmentedControl<SpoilerMode>(
            groupValue: _spoilerMode,
            children: const {
              SpoilerMode.clean: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('クリーン'),
              ),
              SpoilerMode.spoiler: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('ネタバレ'),
              ),
            },
            onValueChanged: (value) {
              setState(() => _spoilerMode = value);
              widget.onSpoilerModeChanged?.call(value);
              _loadUrl();
            },
          ),
        ),
        Expanded(child: WebViewWidget(controller: _controller)),
      ],
    );
  }
}

class ComposeXPostSheet extends StatefulWidget {
  final String initialText;
  final String hashtag;
  final SpoilerMode spoilerMode;

  const ComposeXPostSheet({
    super.key,
    required this.initialText,
    required this.hashtag,
    this.spoilerMode = SpoilerMode.clean,
  });

  @override
  State<ComposeXPostSheet> createState() => _ComposeXPostSheetState();
}

class _ComposeXPostSheetState extends State<ComposeXPostSheet> {
  late final TextEditingController _textController;
  final int _maxLength = 280; // X's character limit

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _postToX() {
    final text = _textController.text;
    final extraTags = widget.spoilerMode == SpoilerMode.spoiler
        ? '${widget.hashtag},アニちぇっく,ネタバレ'
        : '${widget.hashtag},アニちぇっく';
    final url = 'https://twitter.com/intent/tweet'
        '?text=${Uri.encodeComponent(text)}'
        '&hashtags=${Uri.encodeComponent(extraTags)}';

    AppLogger.log('Sharing on X from sheet: $url');
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    Navigator.of(context).pop(); // ボトムシートを閉じる
  }

  @override
  Widget build(BuildContext context) {
    // キーボードの高さに合わせてUIを上に持ち上げる
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(top: 20, left: 20, right: 20, bottom: bottomPadding + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Xで共有', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _textController,
            autofocus: true,
            maxLines: 5,
            maxLength: _maxLength,
            decoration: const InputDecoration(
              hintText: '今なにしてる？',
              border: OutlineInputBorder(),
            ),
            onChanged: (text) => setState(() {}), // 文字数カウンターを更新
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: _textController.text.isEmpty ? null : _postToX,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
              child: const Text('ポストする'),
            ),
          )
        ],
      ),
    );
  }
}