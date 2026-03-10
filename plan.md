あなたはGitHub Copilot CLIの実行エージェントです。

# Mission
以下の実装計画を、壊れにくく最小変更で、順序立てて実行してください。

# Repository Context
- Working directory: /Volumes/DevSSD/Dev/AniCheck/anicheck
- Scope hint: `docs/` ディレクトリおよび `.github/workflows/pages.yml`

# Execution Rules
1. 各ステップの指示を厳密に守り、推測でコードを生成しないこと。
2. ファイルを新規作成する際は、指定されたパスとファイル名を使用すること。
3. エラーハンドリングやCORS対策など、指示されたコードスニペットを正確に含めること。
4. ステップごとに検証（ローカルでのHTMLファイル確認など）を推奨する。

# Plan (from Gemini & Grok, v2.2)

**全体像:**
- `anicheck` リポジトリのルートに `docs` ディレクトリを作成する。
- `docs` 内に `index.html`, `style.css`, `app.js` を配置する。
- **【重要:CORS対策】** サイトは、GitHub Actionsによってデプロイ時に同じ `docs` ディレクトリ内にコピーされる `data/` ディレクトリ内のJSONを、**相対パスで** `fetch` して表示する。
- GitHub Actions (`.github/workflows/pages.yml`) は、`anicheck-data`リポジトリからJSONデータをチェックアウトし、`docs/data`に配置した上で、`docs` ディレクトリ全体をGitHub Pagesにデプロイする。

**Step 1: `docs/index.html` の作成**
- **指示:**
  - `docs/index.html` を新規作成し、以下の内容を書き込め。
    ```html
    <!DOCTYPE html>
    <html lang="ja">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>アニちぇっく - 今期の放送予定</title>
      <link rel="stylesheet" href="style.css">
    </head>
    <body>
      <header>
        <h1>アニちぇっく - 今期の放送予定</h1>
      </header>
      <main>
        <div id="anime-list-container">
          <div id="loading">データを読み込んでいます...</div>
          <div id="anime-list" class="grid-container"></div>
        </div>
      </main>
      <div id="modal" class="modal" role="dialog" aria-modal="true" aria-labelledby="modal-title">
        <div class="modal-content">
          <button id="modal-close" class="modal-close-button">&times;</button>
          <h2 id="modal-title"></h2>
          <p id="modal-summary"></p>
          <a id="modal-url" href="#" target="_blank" rel="noopener noreferrer">公式サイト</a>
        </div>
      </div>
      <script src="app.js" defer></script>
    </body>
    </html>
    ```

**Step 2: `docs/style.css` の作成**
- **指示:**
  - `docs/style.css` を新規作成し、以下のダークテーマとモーダル、グリッドレイアウトのスタイルを書き込め。
    ```css
    body {
      background-color: #121212;
      color: #FFFFFF;
      font-family: sans-serif;
      margin: 0;
      padding: 20px;
    }
    header h1 { text-align: center; }
    .grid-container {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
      gap: 20px;
    }
    .anime-card {
      background-color: #1e1e1e;
      border: 1px solid #333;
      border-radius: 8px;
      padding: 15px;
      cursor: pointer;
      transition: transform 0.2s;
    }
    .anime-card:hover { transform: translateY(-5px); }
    #loading { text-align: center; margin-top: 50px; }
    .modal {
      display: none;
      position: fixed;
      z-index: 1000;
      left: 0; top: 0;
      width: 100%; height: 100%;
      background-color: rgba(0,0,0,0.7);
      align-items: center;
      justify-content: center;
    }
    .modal-content {
      background-color: #2a2a2a;
      padding: 20px;
      border-radius: 8px;
      max-width: 600px;
      position: relative;
    }
    .modal-close-button {
      position: absolute;
      top: 10px; right: 15px;
      font-size: 24px;
      color: #fff;
      background: none;
      border: none;
      cursor: pointer;
    }
    ```

**Step 3: `docs/app.js` の作成**
- **指示:**
  - `docs/app.js` を新規作成し、以下のJavaScriptロジックを書き込め。
    ```javascript
    document.addEventListener('DOMContentLoaded', () => {
      const animeListContainer = document.getElementById('anime-list');
      const loadingIndicator = document.getElementById('loading');
      const modal = document.getElementById('modal');
      const modalClose = document.getElementById('modal-close');
      const modalTitle = document.getElementById('modal-title');
      const modalSummary = document.getElementById('modal-summary');
      const modalUrl = document.getElementById('modal-url');

      const LIST_JSON_URL = './data/daily_schedule.json'; // 相対パス
      const DETAIL_JSON_BASE_URL = './data/'; // 相対パス

      async function fetchAnimeList() {
        try {
          const response = await fetch(LIST_JSON_URL, { cache: 'no-cache' });
          if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
          const data = await response.json();
          
          loadingIndicator.style.display = 'none';
          
          // daily_schedule.json の構造が {"date": ..., "schedule": [...]} であることを仮定
          const animes = data.schedule || []; 
          
          animes.forEach(anime => {
            const card = document.createElement('div');
            card.className = 'anime-card';
            card.textContent = anime.title; // daily_schedule.json に title があると仮定
            card.dataset.animeId = anime.id; // daily_schedule.json に id があると仮定
            card.addEventListener('click', () => showModal(anime.id));
            animeListContainer.appendChild(card);
          });

        } catch (error) {
          loadingIndicator.textContent = 'データの読み込みに失敗しました。';
          console.error('Fetch error:', error);
        }
      }

      async function showModal(animeId) {
        try {
          const response = await fetch(`${DETAIL_JSON_BASE_URL}${animeId}_master.json`, { cache: 'no-cache' });
          if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
          const animeDetails = await response.json();

          modalTitle.textContent = animeDetails.title;
          modalSummary.textContent = animeDetails.synopsis || 'あらすじ情報がありません。'; // synopsis を仮定
          modalUrl.href = animeDetails.official_url || '#'; // official_url を仮定

          modal.style.display = 'flex';

        } catch (error) {
          console.error('Modal fetch error:', error);
          alert('詳細情報の取得に失敗しました。');
        }
      }

      modalClose.addEventListener('click', () => modal.style.display = 'none');
      window.addEventListener('click', (event) => {
        if (event.target === modal) modal.style.display = 'none';
      });

      fetchAnimeList();
    });
    ```

**Step 4: `.github/workflows/pages.yml` の作成**
- **指示:**
  - `.github/workflows/pages.yml` を新規作成し、以下の内容を書き込め。
    ```yaml
    name: Deploy GitHub Pages

    on:
      push:
        branches:
          - main
      workflow_dispatch:

    permissions:
      contents: read
      pages: write
      id-token: write

    jobs:
      deploy:
        runs-on: ubuntu-latest
        steps:
          - name: Checkout main repo
            uses: actions/checkout@v4
            with:
              path: main-repo

          - name: Checkout data repo
            uses: actions/checkout@v4
            with:
              repository: lalate/anicheck-data # あなたのデータリポジトリ
              path: data-repo

          - name: Setup Pages
            run: |
              mkdir -p main-repo/docs/data
              cp -r data-repo/current/* main-repo/docs/data/
          
          - name: Upload artifact
            uses: actions/upload-pages-artifact@v3
            with:
              path: ./main-repo/docs

          - name: Deploy to GitHub Pages
            uses: actions/deploy-pages@v4
    ```

# Deliverable Format
- Step log: 実行した順に箇条書き
- Files changed: パス一覧
- Validation: 実行コマンドと結果（`flutter analyze` 等は不要）
- Next actions: 変更をコミットし、GitHubにプッシュしてActionsの実行結果を確認することを提案する。