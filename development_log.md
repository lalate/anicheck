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


## 2026-02-22 詳細画面の実装とデータ連携の強化
### 1. 詳細画面の実装 
* アニメの詳細情報を表示する AnimeDetailScreen を追加。 
* url_launcher パッケージを導入し、公式サイトや原作（Amazon）、YouTubeへのリンク機能を実装。 
* YouTubeのサムネイル画像表示と再生ボタンのUIを追加。 

### 2. データ構造の刷新 
* ハードコーディングしていたダミーデータを assets/anime_data.json に移行。 
* Anime モデルクラスを定義し、JSONデータのパース処理を実装。 
* FutureBuilder を使用した非同期データ読み込みに対応。 

### 3. ログ機能とデバッグ対応 
* AppLogger クラスを実装し、動作ログをファイルに保存する仕組みを導入。 
* macOSでの画像表示に必要なネットワーク権限（Entitlements）を追加設定。

## 2026-02-XX データ構造のリファクタリング

### 1. データソースの分割と結合
*   単一のJSONファイルから、3つのJSONファイル（Master, Episode, Schedule）による構成へ移行。
*   `anime_id` と `ep_num` をキーにしてデータを結合するロジックを実装。

```

[PROMPT_SUGGESTION]通知設定を保存して、アプリを再起動しても消えないようにしたいです。[/PROMPT_SUGGESTION]
[PROMPT_SUGGESTION]指定した時間（放送開始5分前など）に通知が来る機能を実装したいです。[/PROMPT_SUGGESTION]

```


### 4. 解説：何が変わったのか？

今回実装した内容は以下の3点です。

1.  **詳細画面の実装**:
    *   リストをタップすると、そのアニメの専用画面が開くようになりました。
    *   YouTubeのIDがあればサムネイルを表示し、Amazonの原作リンクがあればボタンを表示するなど、データに応じて画面が変化するようになりました。
2.  **データ構造の刷新**:
    *   これまではプログラムの中に直接書いていた「ダミーデータ」をやめ、外部の `JSONファイル` から読み込むようにしました。これにより、アプリのプログラムを書き換えなくても、JSONファイルを更新するだけで番組データを増やせるようになりました。
3.  **ログ機能とデバッグ対応**:
    *   アプリが裏で何をしているか（読み込み成功、エラー発生など）をファイルに記録する「ログ機能」を追加しました。
    *   macOSでインターネット上の画像を表示するための「通行手形（Entitlements）」を設定しました。

### 3. コミットコマンド

ターミナルで以下を実行して、変更を保存（コミット）してください。

```bash
git add .
git commit -m "Update: 詳細画面の実装、JSONデータ連携、ログ機能の追加"

```