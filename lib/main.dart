import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const AniCheckApp());
}

class AniCheckApp extends StatelessWidget {
  const AniCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    // アプリ全体のテーマ設定
    // 白(#FFFFFF)をベースに、アクセントカラーに青(#1A73E8)を使用
    return MaterialApp(
      title: 'アニちぇっく',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          primary: const Color(0xFF1A73E8),
          background: Colors.white,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1A73E8),
          elevation: 0,
          centerTitle: true,
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
  String? _selectedRegion;
  bool _isLoading = true;

  // ダミーデータ：後ほどAPI連携に置き換える部分
  final List<Map<String, String>> _dummyAnimeList = [
    {'time': '23:00', 'title': '異世界でカフェを開店しました', 'station': 'TOKYO MX'},
    {'time': '23:30', 'title': '魔法学園の劣等生', 'station': 'BS11'},
    {'time': '24:00', 'title': '週末のワルキューレ', 'station': 'テレビ東京'},
    {'time': '24:30', 'title': 'サイバーパンク・シティ', 'station': 'AT-X'},
    {'time': '25:00', 'title': '猫と私の日常', 'station': 'フジテレビ'},
  ];

  // 都道府県リスト（簡略化）
  final List<String> _prefectures = [
    '北海道', '宮城県', '東京都', '愛知県', '大阪府', '広島県', '福岡県', '沖縄県'
  ];

  @override
  void initState() {
    super.initState();
    _initRegion();
  }

  // 保存された地域を読み込む
  Future<void> _initRegion() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRegion = prefs.getString('region');

    if (mounted) {
      setState(() {
        _selectedRegion = savedRegion;
        _isLoading = false;
      });

      // 初回起動時（地域未設定）はダイアログを表示
      if (_selectedRegion == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showRegionDialog();
        });
      }
    }
  }

  // 地域を保存する
  Future<void> _saveRegion(String region) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('region', region);
    if (mounted) {
      setState(() {
        _selectedRegion = region;
      });
    }
  }

  // 地域選択ダイアログの表示
  void _showRegionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // 選択するまで閉じられないようにする
      builder: (context) {
        return AlertDialog(
          title: const Text('地域を選択してください'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _prefectures.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(_prefectures[index]),
                  onTap: () {
                    _saveRegion(_prefectures[index]);
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
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
        title: Text(
          _selectedRegion ?? '地域未設定',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.location_on_outlined),
            onPressed: _showRegionDialog,
            tooltip: '地域変更',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            alignment: Alignment.centerLeft,
            child: Text(
              '今日のアニメ',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _dummyAnimeList.length,
              itemBuilder: (context, index) {
                final anime = _dummyAnimeList[index];
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A73E8).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        anime['time'] ?? '',
                        style: const TextStyle(
                          color: Color(0xFF1A73E8),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      anime['title'] ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      anime['station'] ?? '',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.notifications_none_rounded),
                      color: Colors.grey.shade400,
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('「${anime['title']}」の通知をオンにしました'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}