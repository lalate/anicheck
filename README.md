# anicheck - Flutter App

「アニちぇっく」エコシステムの公式フロントエンドアプリケーションです。
Flutterで構築されており、iOS, Android, macOS, Webに対応しています。

## 🚀 Getting Started

### 1. 環境構築

- **Flutter SDK**: 公式サイト ([https://flutter.dev/](https://flutter.dev/)) の手順に従い、お使いのOSにFlutter SDKをインストールしてください。
- **依存関係のインストール**:
  ```bash
  flutter pub get
  ```
- **プラットフォームごとの設定**:
  - **Mobile (iOS/Android)**: Android Studio / Xcode をインストールし、`flutter doctor` で環境を確認してください。
  - **Desktop (macOS)**: macOS向けビルドに必要な設定を行います。
  - **Web**: Chromeなどのモダンブラウザがあれば実行可能です。

### 2. アプリの実行

以下のコマンドで、各プラットフォーム向けにアプリを実行できます。

- **macOS Desktop**:
  ```bash
  flutter run -d macos
  ```
- **Web (Chrome)**:
  ```bash
  flutter run -d chrome
  ```
- **接続されたiOS/Androidデバイス**:
  ```bash
  flutter run
  ```

### 3. ビルド

各プラットフォーム向けのバイナリをビルドします。

```bash
flutter build <platform>
# 例: flutter build macos
```

## 🔗 関連プロジェクト

- **[anicheck-data](https://github.com/lalate/anicheck-data)**: このアプリが参照するJSONデータのリポジトリ。
