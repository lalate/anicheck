# アニちぇっく 開発ログ

## 2026-02-12 プロジェクト立ち上げと基盤実装

### 1. プロジェクト作成
Flutterプロジェクトを新規作成し、必要なパッケージを追加しました。

```bash
flutter create anicheck
cd anicheck
flutter pub add shared_preferences
```

### 2. ベースコードの実装 (`lib/main.dart`)
以下の機能を実装した `main.dart` を作成しました。
*   **地域設定**: `shared_preferences` を使用し、初回起動時に都道府県を選択・保存するダイアログ。
*   **リスト表示**: ダミーデータを使用したアニメ放送リスト（時間、タイトル、放送局）。
*   **UIデザイン**: Material 3 をベースに、白と青（#1A73E8）を基調とした清潔感のあるテーマ。

### 3. ビルドエラーの修正
Flutter SDKのバージョン起因による `DialogTheme` の型不一致エラーが発生したため、修正を行いました。

**修正前:**
```dart
dialogTheme: const DialogTheme(
  backgroundColor: Colors.white,
  surfaceTintColor: Colors.transparent,
),
```

**修正後:**
```dart
dialogTheme: const DialogThemeData(
  backgroundColor: Colors.white,
  surfaceTintColor: Colors.transparent,
),
```

### 4. バージョン管理
Gitリポジトリを初期化し、初期コードをコミットしました。

```bash
git init
git add .
git commit -m "Initial commit: アニちぇっくの基盤を作成（地域設定・リスト表示）"
```