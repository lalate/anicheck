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

/* ===== Initialise ===== */
document.addEventListener('DOMContentLoaded', init);

async function init() {
  setupControls();
  await loadData();
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

  // 曜日フィルター (V2ではdaily_scheduleを使用するため、静的サイト側ではひとまず「すべて」を基本とする)
  document.getElementById('dayFilters')?.addEventListener('click', e => {
    const btn = e.target.closest('.filter-btn');
    if (!btn) return;
    document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    activeDay = btn.dataset.day;
    render();
  });

  // モーダルを閉じる
  document.getElementById('modalClose')?.addEventListener('click', closeModal);
  document.getElementById('modalBackdrop')?.addEventListener('click', closeModal);
  document.addEventListener('keydown', e => { if (e.key === 'Escape') closeModal(); });
}

/* ===== Render ===== */
function render() {
  const grid = document.getElementById('animeGrid');
  if (!grid) return;

  const filtered = filter(allAnime);

  if (filtered.length === 0) {
    grid.innerHTML = `<p style="color:var(--text-muted);grid-column:1/-1;text-align:center;padding:3rem 0;">
      該当するアニメが見つかりませんでした。</p>`;
    return;
  }

  grid.innerHTML = filtered.map(item => cardHTML(item)).join('');

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
    // 検索フィルター
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

function cardHTML({ master, broadcast }) {
  const studio = master.jikan_studio || master.studio || master.staff?.studio || '';
  const genres = master.genres ? master.genres.slice(0, 3).map(g => `<span class="tag genre-tag">${esc(g)}</span>`).join('') : '';
  const imageUrl = master.image_url || 'https://via.placeholder.com/300x400/2a2a2a/ffffff?text=No+Image';

  // 進捗情報 (broadcast_history.json)
  let progressHtml = '';
  if (broadcast && broadcast.overall_latest_ep) {
     progressHtml = `<span class="day-badge" style="background-color: #ff9800;">最新: 第${broadcast.overall_latest_ep}話</span>`;
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

  // 進捗情報
  if (broadcast && broadcast.platforms) {
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
