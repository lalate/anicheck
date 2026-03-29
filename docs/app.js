/**
 * app.js — アニちぇっく静的サイト (V2 DB型フラット構造対応)
 *
 * CORS対策: GitHub Actionsがデプロイ時に同じdocsディレクトリ内の
 * data/ へJSONをコピーするため、全てのfetchを相対パスで行う。
 */

const DATA_BASE      = './data';
const ANIME_LIST_URL = `${DATA_BASE}/anime_list.json`;
const BROADCAST_URL  = `${DATA_BASE}/broadcast_history.json`;
const WATCH_LIST_URL = `${DATA_BASE}/watch_list.json`;
const AFFILIATE_ID   = 'anicheck0f-22';

let allAnime     = [];  
let activeDay    = 'all';
let searchQuery  = '';
let activeSeason = 'all';
let activeGenre  = 'all';
let activeStudio = 'all';
let sortKey      = 'title';
let isSpoilerEnabled = false;

/* ===== Initialise ===== */
document.addEventListener('DOMContentLoaded', init);

async function init() {
  loadSettings();
  setupControls();
  await loadData();
}

function loadSettings() {
  const saved = localStorage.getItem('anicheck_settings');
  if (saved) {
    try {
      const settings = JSON.parse(saved);
      isSpoilerEnabled = settings.isSpoilerEnabled || false;
      sortKey = settings.sortKey || 'title';
      // UIの状態に反映
      const spoilerEl = document.getElementById('spoilerToggle');
      if (spoilerEl) spoilerEl.checked = isSpoilerEnabled;
      const sortEl = document.getElementById('sortSelect');
      if (sortEl) sortEl.value = sortKey;
    } catch (e) { console.error('Settings load failed', e); }
  }

  // URLパラメータの処理
  const params = new URLSearchParams(window.location.search);
  const s = params.get('season');
  if (s) activeSeason = s;
}

function saveSettings() {
  const settings = { isSpoilerEnabled, sortKey };
  localStorage.setItem('anicheck_settings', JSON.stringify(settings));
}

/* ===== Data loading ===== */
async function loadData() {
  const loadingEl = document.getElementById('loadingMsg');
  const errorEl   = document.getElementById('errorMsg');

  try {
    // 1. 各種JSONを並行取得
    const [masterList, broadcastHistory, watchList] = await Promise.all([
      fetchJSON(ANIME_LIST_URL),
      fetchJSON(BROADCAST_URL).catch(() => ({})),
      fetchJSON(WATCH_LIST_URL).catch(() => [])
    ]);

    // 2. 現在監視中（is_active: true）の anime_id リストを作成
    const activeIds = new Set(watchList.filter(w => w.is_active).map(w => w.anime_id));

    // 3. masterList をベースに、アクティブな作品だけを抽出し、放送履歴を結合
    allAnime = masterList
      .filter(m => activeIds.has(m.anime_id))
      .map(master => {
        return {
          master: master,
          broadcast: broadcastHistory[master.anime_id] || null
        };
      });

    setupDynamicFilters();
    loadingEl.style.display = 'none';
    render();
  } catch (err) {
    console.error('[AniCheck] データ読み込み失敗:', err);
    loadingEl.style.display = 'none';
    errorEl.style.display   = 'block';
    errorEl.textContent     =
      `データの読み込みに失敗しました。GitHub Actionsによるデプロイ後にご確認ください。\n(${err.message})`;
  }
}

async function fetchJSON(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${url}`);
  return res.json();
}

/* ===== Controls ===== */
function setupControls() {
  // 検索
  document.getElementById('searchInput').addEventListener('input', e => {
    searchQuery = e.target.value.trim().toLowerCase();
    render();
  });

  // シーズン選択
  document.getElementById('seasonSelect')?.addEventListener('change', e => {
    activeSeason = e.target.value;
    render();
  });

  // 曜日フィルター
  document.getElementById('dayFilters')?.addEventListener('click', e => {
    const btn = e.target.closest('.filter-btn');
    if (!btn) return;
    document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    activeDay = btn.dataset.day;
    render();
  });

  // ソート
  document.getElementById('sortSelect')?.addEventListener('change', e => {
    sortKey = e.target.value;
    saveSettings();
    render();
  });

  // ネタバレ
  document.getElementById('spoilerToggle')?.addEventListener('change', e => {
    isSpoilerEnabled = e.target.checked;
    saveSettings();
    render();
  });

  // モーダルを閉じる
  document.getElementById('modalClose')?.addEventListener('click', closeModal);
  document.getElementById('modalBackdrop')?.addEventListener('click', closeModal);
  document.addEventListener('keydown', e => { if (e.key === 'Escape') closeModal(); });
}

function setupDynamicFilters() {
  const genres = new Set();
  const studios = new Set();
  const seasons = new Set();

  allAnime.forEach(({ master }) => {
    if (master.genres) master.genres.forEach(g => genres.add(g));
    const studio = master.jikan_studio || master.studio || master.staff?.studio;
    if (studio) studios.add(studio);
    
    // YYYYMM
    if (master.anime_id && master.anime_id.length >= 6) {
      seasons.add(master.anime_id.substring(0, 6));
    }
  });

  // シーズン選択肢
  const seasonSelect = document.getElementById('seasonSelect');
  if (seasonSelect) {
    const sortedSeasons = Array.from(seasons).sort().reverse();
    sortedSeasons.forEach(s => {
      const year = s.substring(0, 4);
      const month = s.substring(4, 6);
      const label = `${year}年 ${month === '01' ? '冬' : month === '04' ? '春' : month === '07' ? '夏' : '秋'}`;
      const opt = new Option(label, s);
      seasonSelect.add(opt);
    });
    // 初期選択
    if (activeSeason !== 'all') seasonSelect.value = activeSeason;
    else if (sortedSeasons.length > 0) {
      // 最新のシーズンをデフォルトにする（URLパラメータやlocalStorageがない場合）
      activeSeason = sortedSeasons[0];
      seasonSelect.value = activeSeason;
    }
  }

  // ジャンル・スタジオチップ
  const container = document.getElementById('dynamicFilters');
  if (container) {
    let html = '<b>ジャンル:</b> ';
    const sortedGenres = Array.from(genres).sort();
    html += `<span class="chip ${activeGenre==='all'?'active':''}" data-type="genre" data-value="all">全て</span>`;
    sortedGenres.forEach(g => {
      html += `<span class="chip ${activeGenre===g?'active':''}" data-type="genre" data-value="${esc(g)}">${esc(g)}</span>`;
    });

    html += '<br><b>スタジオ:</b> ';
    const sortedStudios = Array.from(studios).sort();
    html += `<span class="chip ${activeStudio==='all'?'active':''}" data-type="studio" data-value="all">全て</span>`;
    sortedStudios.forEach(s => {
      html += `<span class="chip ${activeStudio===s?'active':''}" data-type="studio" data-value="${esc(s)}">${esc(s)}</span>`;
    });
    
    container.innerHTML = html;
    
    container.addEventListener('click', e => {
      const chip = e.target.closest('.chip');
      if (!chip) return;
      
      const type = chip.dataset.type;
      const val = chip.dataset.value;
      
      if (type === 'genre') activeGenre = val;
      if (type === 'studio') activeStudio = val;
      
      container.querySelectorAll(`.chip[data-type="${type}"]`).forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      render();
    });
  }
}

/* ===== Render ===== */
function render() {
  const grid = document.getElementById('animeGrid');
  if (!grid) return;

  const filtered = filter(allAnime);
  const sorted = sort(filtered);

  if (sorted.length === 0) {
    grid.innerHTML = `<p style="color:var(--text-muted);grid-column:1/-1;text-align:center;padding:3rem 0;">
      該当するアニメが見つかりませんでした。</p>`;
    return;
  }

  grid.innerHTML = sorted.map(item => cardHTML(item)).join('');

  // カードクリックでモーダル表示
  grid.querySelectorAll('.anime-card').forEach(card => {
    card.addEventListener('click', () => {
      const id = card.dataset.animeId;
      const item = allAnime.find(a => a.master.anime_id === id);
      if (item) openModal(item);
    });
  });
}

function filter(list) {
  return list.filter(({ master, broadcast }) => {
    // 1. シーズン
    if (activeSeason !== 'all' && master.anime_id && !master.anime_id.startsWith(activeSeason)) {
      return false;
    }

    // 2. 曜日
    if (activeDay !== 'all') {
      const dayMatches = master.station_master?.includes(activeDay) || 
                         (broadcast?.platforms && Object.values(broadcast.platforms).some(p => p.remarks?.includes(activeDay)));
      if (!dayMatches) return false;
    }

    // 3. ジャンル
    if (activeGenre !== 'all' && (!master.genres || !master.genres.includes(activeGenre))) {
      return false;
    }

    // 4. スタジオ
    if (activeStudio !== 'all') {
      const studio = master.jikan_studio || master.studio || master.staff?.studio;
      if (studio !== activeStudio) return false;
    }

    // 5. 検索フィルター
    if (searchQuery) {
      const haystack = [
        master.title,
        master.title_english,
        master.title_japanese,
        master.studio,
        master.jikan_studio,
        master.hashtag,
        ...(master.genres || []),
        ...(master.cast || []),
      ].filter(Boolean).join(' ').toLowerCase();
      if (!haystack.includes(searchQuery)) return false;
    }
    return true;
  });
}

function sort(list) {
  return [...list].sort((a, b) => {
    if (sortKey === 'score') {
      return (b.master.score || 0) - (a.master.score || 0);
    }
    // デフォルト: タイトル順
    return a.master.title.localeCompare(b.master.title, 'ja');
  });
}

function cardHTML({ master, broadcast }) {
  const studio = master.jikan_studio || master.studio || master.staff?.studio || '';
  const genres = master.genres ? master.genres.slice(0, 3).map(g => `<span class="tag genre-tag">${esc(g)}</span>`).join('') : '';
  const imageUrl = master.image_url || 'https://via.placeholder.com/300x400/2a2a2a/ffffff?text=No+Image';

  // 進捗情報 (ネタバレ解禁時のみ表示)
  let progressHtml = '';
  if (isSpoilerEnabled && broadcast && broadcast.overall_latest_ep) {
     progressHtml = `<span class="day-badge" style="background-color: #ff9800; color: #fff; padding: 0.1rem 0.4rem; border-radius: 4px;">最新: 第${broadcast.overall_latest_ep}話</span>`;
  }

  return `
    <article class="anime-card" data-anime-id="${esc(master.anime_id)}" role="listitem" tabindex="0"
      aria-label="${esc(master.title)}">
      <div class="card-image" style="background-image: url('${esc(imageUrl)}');"></div>
      <div class="card-content">
        <div class="card-title">${esc(master.title)}</div>
        <div class="card-meta">
          ${progressHtml}
          ${master.station_master ? `<span class="tag station-tag">${esc(master.station_master)}</span>` : ''}
          ${studio ? `<span class="tag studio-tag">${esc(studio)}</span>` : ''}
          ${genres}
          ${master.score ? `<span class="tag score-tag" style="background:rgba(255,215,0,0.1); border-color:gold; color:gold;">★${master.score.toFixed(1)}</span>` : ''}
        </div>
      </div>
    </article>
  `;
}

/* ===== Modal ===== */
function openModal({ master, broadcast }) {
  document.getElementById('modalTitle').textContent = master.title;
  document.getElementById('modalBody').innerHTML = buildModalBody(master, broadcast);
  document.getElementById('modal').style.display = 'flex';
  document.body.style.overflow = 'hidden';
}

function closeModal() {
  document.getElementById('modal').style.display = 'none';
  document.body.style.overflow = '';
}

function buildModalBody(m, broadcast) {
  const sections = [];

  // スコア
  if (m.score) {
    sections.push(`<div class="score-display">★ ${m.score.toFixed(2)}</div>`);
  }

  // 進捗情報 (ネタバレ解禁時のみ詳細を表示)
  if (broadcast && broadcast.platforms && isSpoilerEnabled) {
    const rows = Object.entries(broadcast.platforms).map(([station, info]) => {
      const ep = info.last_ep_num ? `第${info.last_ep_num}話` : '';
      const rem = info.remarks ? ` <small>(${esc(info.remarks)})</small>` : '';
      return `<li><b>${esc(station)}</b>: ${ep}${rem}</li>`;
    }).join('');
    sections.push(section('📡 局別進捗', `<ul>${rows}</ul>`));
  } else if (m.station_master) {
    sections.push(section('📡 放送局', `<p>${esc(m.station_master)}</p>`));
  }

  // ハッシュタグ
  if (m.hashtag) {
    const twitterUrl = `https://twitter.com/search?q=${encodeURIComponent(m.hashtag)}&f=live`;
    sections.push(section('🏷️ ハッシュタグ',
      `<a class="hashtag-chip" href="${twitterUrl}" target="_blank" rel="noopener">${esc(m.hashtag)}</a>`));
  }

  // スタッフ
  if (m.staff) {
    const rows = Object.entries(m.staff).map(([k, v]) =>
      `<li><b>${esc(k)}</b>: ${esc(String(v))}</li>`).join('');
    sections.push(section('🎬 スタッフ', `<ul>${rows}</ul>`));
  }

  // キャスト
  if (m.cast?.length) {
    sections.push(section('🎤 キャスト', `<ul>${m.cast.map(c => `<li>${esc(c)}</li>`).join('')}</ul>`));
  }

  // リンク
  const links = [];
  if (m.official_url) {
    links.push(`<a class="btn-link btn-official" href="${esc(m.official_url)}" target="_blank" rel="noopener">🌐 公式サイト</a>`);
  }
  if (m.sources?.manga_amazon) {
    const amazonUrl = buildAmazonUrl(m.sources.manga_amazon);
    links.push(`<a class="btn-link btn-amazon" href="${esc(amazonUrl)}" target="_blank" rel="noopener">📚 原作を購入</a>`);
  }
  if (links.length) {
    sections.push(`<div class="modal-links">${links.join('')}</div>`);
  }

  return sections.join('');
}

function section(heading, content) {
  return `<div class="modal-section"><h3>${heading}</h3>${content}</div>`;
}

/* ===== Utilities ===== */
function buildAmazonUrl(baseUrl) {
  if (!baseUrl) return null;
  try {
    const url = new URL(baseUrl);
    url.searchParams.set('tag', AFFILIATE_ID);
    return url.toString();
  } catch (_) {
    // URLパースに失敗した場合はそのまま返す
    return baseUrl;
  }
}

function esc(str) {
  if (str == null) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
