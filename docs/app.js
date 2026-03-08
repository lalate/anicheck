/**
 * app.js — アニちぇっく静的サイト
 *
 * CORS対策: GitHub Actionsがデプロイ時に同じdocsディレクトリ内の
 * data/ へJSONをコピーするため、全てのfetchを相対パスで行う。
 */

const DATA_BASE = './data';
const ANIME_LIST_URL = `${DATA_BASE}/anime_list.json`;
const BROADCAST_URL  = `${DATA_BASE}/broadcast.json`;

let allAnime     = [];  // { master, broadcast? }
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
    // anime_list.json はワークフローが current/*_master.json を結合して生成する
    const [masterList, broadcastList] = await Promise.all([
      fetchJSON(ANIME_LIST_URL),
      fetchJSON(BROADCAST_URL).catch(() => []),  // broadcast がなくても続行
    ]);

    // broadcast を anime_id でインデックス化
    const broadcastMap = {};
    for (const b of broadcastList) {
      if (!broadcastMap[b.anime_id]) broadcastMap[b.anime_id] = [];
      broadcastMap[b.anime_id].push(b);
    }

    allAnime = masterList
      .filter(m => m.anime_id && m.title)  // anime_id または title が無いアイテムをスキップ
      .map(m => ({
        master:    m,
        broadcast: broadcastMap[m.anime_id] || [],
      }));

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

  // 曜日フィルター
  document.getElementById('dayFilters').addEventListener('click', e => {
    const btn = e.target.closest('.filter-btn');
    if (!btn) return;
    document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    activeDay = btn.dataset.day;
    render();
  });

  // モーダルを閉じる
  document.getElementById('modalClose').addEventListener('click', closeModal);
  document.getElementById('modalBackdrop').addEventListener('click', closeModal);
  document.addEventListener('keydown', e => { if (e.key === 'Escape') closeModal(); });
}

/* ===== Render ===== */
function render() {
  const grid     = document.getElementById('animeGrid');
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
    // 曜日フィルター
    if (activeDay !== 'all') {
      const match = broadcast.some(b => b.day_of_week === activeDay);
      if (!match) return false;
    }
    // 検索フィルター
    if (searchQuery) {
      const haystack = [
        master.title,
        master.staff?.studio,
        master.hashtag,
        ...(master.cast || []),
      ].filter(Boolean).join(' ').toLowerCase();
      if (!haystack.includes(searchQuery)) return false;
    }
    return true;
  });
}

function cardHTML({ master, broadcast }) {
  const day  = broadcast[0]?.day_of_week ?? '';
  const time = broadcast[0] ? formatTime(broadcast[0].start_time) : '';
  const studio = master.staff?.studio ?? '';
  const hashtag = master.hashtag ?? '';

  return `
    <article class="anime-card" data-anime-id="${esc(master.anime_id)}" role="listitem" tabindex="0"
      aria-label="${esc(master.title)}">
      <div class="card-title">${esc(master.title)}</div>
      <div class="card-meta">
        ${day ? `<span class="day-badge">${esc(day)} ${time}</span>` : ''}
        ${studio ? `<span class="tag studio-tag">${esc(studio)}</span>` : ''}
        ${hashtag ? `<span class="tag">${esc(hashtag)}</span>` : ''}
      </div>
    </article>`;
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

  // 放送情報
  if (broadcast.length > 0) {
    const rows = broadcast.map(b => {
      const time = formatTime(b.start_time);
      return `<li>${esc(b.station_id ?? m.station_master ?? '')}　${esc(b.day_of_week ?? '')} ${time}</li>`;
    }).join('');
    sections.push(section('📡 放送情報', `<ul>${rows}</ul>`));
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
    links.push(`<a class="btn-link btn-amazon" href="${esc(m.sources.manga_amazon)}" target="_blank" rel="noopener">📚 原作を購入</a>`);
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
function esc(str) {
  if (str == null) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/**
 * ISO 8601 の時刻文字列 (例: "2026-02-24T24:30:00+09:00") を
 * "24:30" 形式にフォーマット。24時超えもそのまま表示する。
 */
function formatTime(isoStr) {
  if (!isoStr) return '';
  const m = isoStr.match(/T(\d{2}:\d{2})/);
  return m ? m[1] : '';
}
