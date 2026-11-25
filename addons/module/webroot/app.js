import { exec, toast, hasKsuBridge } from "./ksu.js";

const CTL = "/data/adb/modules/xmsrom_oneui95_addons/scripts/addon_ctl.sh";
const REMOTE_CATALOG_URL =
  "https://raw.githubusercontent.com/Gustyx-Power/xmsrom-oneui9.5-patch-ksumodule/main/addons/catalog.json";

const I18N = {
  id: {
    appTitle: "OneUI Add-ons",
    appSubtitle: "XMSROM 9.5 · GustyxPower",
    sysStatus: "Status Sistem",
    mountEngine: "Mount Engine",
    dataFree: "Penyimpanan /data Tersedia",
    activeAddons: "Add-on Terpasang",
    searchPlaceholder: "Cari Bixby, Routines, Edge, Photo AI...",
    allCategory: "Semua",
    installedBadge: "Terpasang",
    installBtn: "Pasang",
    removeBtn: "Hapus",
    unavailableBtn: "Belum Tersedia",
    dlWord: "Unduh",
    sizeWord: "Ukuran",
    packsWord: "paket",
    freeWord: "kosong",
    emptyState: "Tidak ada add-on yang cocok dengan filter.",
    rebootPrompt: "Reboot diperlukan agar sistem memuat add-on baru.",
    rebootBtn: "Mulai Ulang",
    settingsTitle: "Pengaturan Modul",
    langLabel: "Bahasa Antarmuka",
    mirrorLabel: "Mirror Base URL (.tar.xz)",
    modeLabel: "Mode Mount",
    modeAuto: "Otomatis (NoMount / Metamodule, else MagicMount)",
    modeMagic: "Magic Mount Bawaan (tmpfs + bind)",
    modeMeta: "Metamodule / NoMount Eksternal",
    cancelBtn: "Batal",
    saveBtn: "Simpan",
    logsTitle: "Log Diagnostik Mount",
    closeBtn: "Tutup",
    syncing: "Menyinkronkan katalog...",
    syncOk: "Katalog diperbarui",
    syncFail: "Gagal sinkronisasi, memakai katalog lokal",
    settingsSaved: "Pengaturan disimpan",
    engineMagicNoMount: "MagicMount (NoMount siap)",
    engineMagic: "MagicMount",
    engineNoMount: "NoMount VFS",
    engineMeta: "Metamodule",
    engineIdle: "Siap (Kosong)",
    jobDone: "Selesai",
    jobErr: "Gagal",
    jobProc: "Memproses",
    removedToast: "dihapus",
    errStart: "Gagal memulai",
    errRemove: "Gagal menghapus",
  },
  en: {
    appTitle: "OneUI Add-ons",
    appSubtitle: "XMSROM 9.5 · GustyxPower",
    sysStatus: "System Status",
    mountEngine: "Mount Engine",
    dataFree: "Available /data Space",
    activeAddons: "Installed Add-ons",
    searchPlaceholder: "Search Bixby, Routines, Edge, Photo AI...",
    allCategory: "All",
    installedBadge: "Installed",
    installBtn: "Install",
    removeBtn: "Remove",
    unavailableBtn: "Not Uploaded",
    dlWord: "Download",
    sizeWord: "Unpacked",
    packsWord: "packs",
    freeWord: "free",
    emptyState: "No add-on packages match your filter.",
    rebootPrompt: "Reboot required for Android to scan changed system packs.",
    rebootBtn: "Reboot",
    settingsTitle: "Module Settings",
    langLabel: "Interface Language",
    mirrorLabel: "Mirror Base URL (.tar.xz)",
    modeLabel: "Mount Mode",
    modeAuto: "Auto (NoMount / Metamodule, else MagicMount)",
    modeMagic: "Built-in Magic Mount (tmpfs + bind)",
    modeMeta: "External Metamodule / NoMount",
    cancelBtn: "Cancel",
    saveBtn: "Save",
    logsTitle: "Mount Diagnostics Log",
    closeBtn: "Close",
    syncing: "Syncing catalog...",
    syncOk: "Catalog updated",
    syncFail: "Sync failed, using bundled catalog",
    settingsSaved: "Settings saved",
    engineMagicNoMount: "MagicMount (NoMount ready)",
    engineMagic: "MagicMount",
    engineNoMount: "NoMount VFS",
    engineMeta: "Metamodule",
    engineIdle: "Ready (No packs)",
    jobDone: "Completed",
    jobErr: "Failed",
    jobProc: "Processing",
    removedToast: "removed",
    errStart: "Failed to start",
    errRemove: "Failed to remove",
  },
};

const savedLang = localStorage.getItem("xms_lang");
const defaultLang = savedLang === "en" || savedLang === "id"
  ? savedLang
  : (navigator.language || "").toLowerCase().startsWith("id")
  ? "id"
  : "en";

const state = {
  lang: defaultLang,
  catalog: { version: "1.0.0", base_url: "", fallback_base_url: "", packs: [] },
  device: null,
  categoryKey: "ALL",
  query: "",
  pollTimer: null,
};

const els = {
  btnLang: document.getElementById("btn-lang"),
  engine: document.getElementById("stat-engine"),
  dataFree: document.getElementById("stat-data"),
  installedCount: document.getElementById("stat-installed"),
  jobBanner: document.getElementById("job-banner"),
  jobTitle: document.getElementById("job-title"),
  jobPct: document.getElementById("job-pct"),
  jobFill: document.getElementById("job-fill"),
  jobBarWrap: document.getElementById("job-bar-wrap"),
  jobMsg: document.getElementById("job-msg"),
  search: document.getElementById("search-input"),
  chips: document.getElementById("chips-row"),
  sections: document.getElementById("pack-sections"),
  rebootBar: document.getElementById("reboot-bar"),
  btnReboot: document.getElementById("btn-reboot"),
  btnSync: document.getElementById("btn-sync"),
  btnLogs: document.getElementById("btn-logs"),
  btnSettings: document.getElementById("btn-settings"),
  settingsModal: document.getElementById("settings-modal"),
  selectLang: document.getElementById("select-lang"),
  inputMirror: document.getElementById("input-mirror"),
  selectMode: document.getElementById("select-mode"),
  btnSaveSettings: document.getElementById("btn-save-settings"),
  btnCancelSettings: document.getElementById("btn-cancel-settings"),
  btnCloseSettings: document.getElementById("btn-close-settings"),
  btnPresetHf: document.getElementById("btn-preset-hf"),
  btnPresetGh: document.getElementById("btn-preset-gh"),
  logsModal: document.getElementById("logs-modal"),
  logsBox: document.getElementById("logs-box"),
  btnCloseLogs: document.getElementById("btn-close-logs"),
  btnOkLogs: document.getElementById("btn-ok-logs"),
};

function t(key) {
  return (I18N[state.lang] && I18N[state.lang][key]) || I18N.id[key] || key;
}

function pField(pack, field) {
  if (state.lang === "en" && pack[`${field}_en`]) return pack[`${field}_en`];
  return pack[field] || "";
}

function fmtMbFromBytes(bytes) {
  if (!bytes || bytes <= 0) return "0 MB";
  const mb = bytes / (1024 * 1024);
  return mb >= 1024 ? `${(mb / 1024).toFixed(2)} GB` : `${mb.toFixed(1)} MB`;
}

function fmtGbFromKb(kb) {
  return `${(kb / (1024 * 1024)).toFixed(1)} GB ${t("freeWord")}`;
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function applyStaticI18n() {
  document.documentElement.lang = state.lang;
  els.btnLang.textContent = state.lang.toUpperCase();
  els.search.placeholder = t("searchPlaceholder");
  document.querySelectorAll("[data-i18n]").forEach((node) => {
    const k = node.getAttribute("data-i18n");
    if (k) node.textContent = t(k);
  });
}

async function runCtl(args) {
  const escaped = args
    .map((a) => `'${String(a).replace(/'/g, `'\\''`)}'`)
    .join(" ");
  return exec(`sh '${CTL}' ${escaped}`);
}

async function loadStatus() {
  if (!hasKsuBridge) {
    els.engine.textContent = "Preview";
    els.dataFree.textContent = "No KSU";
    return;
  }
  const res = await runCtl(["status"]);
  if (res.errno !== 0) {
    toast(res.stderr || "Status error");
    return;
  }
  state.device = JSON.parse(res.stdout);
  renderStatus();
  renderPacks();
  handleJobPolling();
}

async function loadLocalCatalog() {
  if (!hasKsuBridge) {
    try {
      const resp = await fetch("../../catalog.json");
      state.catalog = await resp.json();
    } catch (_) {}
    renderCategories();
    renderPacks();
    return;
  }
  const res = await runCtl(["get_catalog"]);
  if (res.errno === 0 && res.stdout.trim()) {
    try {
      state.catalog = JSON.parse(res.stdout);
    } catch (_) {}
  }
  renderCategories();
  renderPacks();
}

async function syncRemoteCatalog() {
  els.btnSync.disabled = true;
  toast(t("syncing"));
  const res = await runCtl(["fetch_catalog", REMOTE_CATALOG_URL]);
  els.btnSync.disabled = false;
  if (res.errno === 0 && res.stdout.trim()) {
    try {
      state.catalog = JSON.parse(res.stdout);
      renderCategories();
      renderPacks();
      toast(t("syncOk"));
      return;
    } catch (_) {}
  }
  toast(t("syncFail"));
}

function renderStatus() {
  const d = state.device;
  if (!d) return;
  const map = {
    magic_mount: d.has_nomount ? t("engineMagicNoMount") : t("engineMagic"),
    nomount: t("engineNoMount"),
    metamodule: t("engineMeta"),
    idle: t("engineIdle"),
  };
  els.engine.textContent = map[d.mount_engine] || d.mount_engine;
  els.dataFree.textContent = fmtGbFromKb(d.data_free_kb);
  els.installedCount.textContent = `${d.installed.length} ${t("packsWord")} · ${fmtMbFromBytes(d.staged_kb * 1024)}`;
  els.rebootBar.hidden = d.reboot_pending !== 1;
}

function renderCategories() {
  const seen = new Map();
  for (const p of state.catalog.packs || []) {
    if (!seen.has(p.category)) {
      seen.set(p.category, pField(p, "category"));
    }
  }
  const items = [["ALL", t("allCategory")], ...seen.entries()];
  els.chips.innerHTML = items
    .map(
      ([key, label]) =>
        `<button class="oneui-chip${state.categoryKey === key ? " is-active" : ""}" type="button" role="tab" aria-selected="${
          state.categoryKey === key
        }" data-cat="${escapeHtml(key)}">${escapeHtml(label)}</button>`
    )
    .join("");
}

function tagClass(pack) {
  const raw = `${pack.badge || ""} ${pack.badge_en || ""}`.toLowerCase();
  if (raw.includes("eksperimen") || raw.includes("experimental") || raw.includes("berat") || raw.includes("heavy")) {
    return "tag-amber";
  }
  if (raw.includes("rekomendasi") || raw.includes("recommended") || raw.includes("ringan") || raw.includes("light")) {
    return "tag-green";
  }
  return "tag-blue";
}

function resolveDownloadUrl(pack) {
  const mirror = (state.device && state.device.mirror_url) || "";
  const base = (mirror || state.catalog.base_url || "").replace(/\/+$/, "");
  return `${base}/${pack.archive}`;
}

function renderPacks() {
  const installedSet = new Set((state.device && state.device.installed) || []);
  const jobActive =
    state.device &&
    state.device.job &&
    ["downloading", "verifying", "extracting"].includes(state.device.job.state);

  const q = state.query.trim().toLowerCase();
  const filtered = (state.catalog.packs || []).filter((p) => {
    const matchCat = state.categoryKey === "ALL" || p.category === state.categoryKey;
    const matchQ =
      !q ||
      p.name.toLowerCase().includes(q) ||
      pField(p, "description").toLowerCase().includes(q) ||
      p.id.toLowerCase().includes(q);
    return matchCat && matchQ;
  });

  if (!filtered.length) {
    els.sections.innerHTML = `<div class="oneui-card empty-card">${escapeHtml(t("emptyState"))}</div>`;
    return;
  }

  // Group into One UI rounded category containers
  const groups = new Map();
  for (const p of filtered) {
    const groupLabel = pField(p, "category");
    if (!groups.has(groupLabel)) groups.set(groupLabel, []);
    groups.get(groupLabel).push(p);
  }

  let html = "";
  for (const [groupLabel, packs] of groups.entries()) {
    html += `<p class="section-label">${escapeHtml(groupLabel)}</p><section class="oneui-card">`;
    packs.forEach((p, idx) => {
      const isInstalled = installedSet.has(p.id);
      const badgeLabel = pField(p, "badge");
      const badgeHtml = badgeLabel
        ? `<span class="oneui-tag ${tagClass(p)}">${escapeHtml(badgeLabel)}</span>`
        : "";
      const instHtml = isInstalled
        ? `<span class="oneui-tag tag-green">${escapeHtml(t("installedBadge"))}</span>`
        : "";
      const noteText = pField(p, "note");
      const noteHtml = noteText ? `<p class="pack-note">${escapeHtml(noteText)}</p>` : "";
      const missingHash = !p.sha256 || p.sha256.startsWith("PENDING");

      let actionBtn = "";
      if (isInstalled) {
        actionBtn = `<button class="btn-oneui btn-red-tint" type="button" data-action="remove" data-id="${escapeHtml(
          p.id
        )}" ${jobActive ? "disabled" : ""}>${escapeHtml(t("removeBtn"))}</button>`;
      } else if (missingHash && !p.archive_bytes) {
        actionBtn = `<button class="btn-oneui btn-tonal" type="button" disabled>${escapeHtml(t("unavailableBtn"))}</button>`;
      } else {
        actionBtn = `<button class="btn-oneui btn-blue" type="button" data-action="install" data-id="${escapeHtml(
          p.id
        )}" ${jobActive ? "disabled" : ""}>${escapeHtml(t("installBtn"))}</button>`;
      }

      const specText = p.archive_bytes
        ? `${t("dlWord")} ${fmtMbFromBytes(p.archive_bytes)} · ${p.unpacked_mb} MB`
        : `${t("sizeWord")} ~${p.unpacked_mb} MB`;

      if (idx > 0) html += `<div class="kv-divider"></div>`;
      html += `
        <article class="pack-row">
          <div class="pack-row-head">
            <div class="pack-row-main">
              <div class="pack-title-line">
                <h3 class="pack-title">${escapeHtml(p.name)}</h3>
                ${badgeHtml}
                ${instHtml}
              </div>
              <p class="pack-summary">${escapeHtml(pField(p, "description"))}</p>
              ${noteHtml}
            </div>
          </div>
          <div class="pack-bottom">
            <span class="pack-specs">${escapeHtml(specText)}</span>
            ${actionBtn}
          </div>
        </article>`;
    });
    html += `</section>`;
  }

  els.sections.innerHTML = html;
}

function handleJobPolling() {
  const job = state.device && state.device.job;
  if (!job || job.state === "idle") {
    els.jobBanner.hidden = true;
    stopPolling();
    return;
  }

  els.jobBanner.hidden = false;
  els.jobBanner.classList.toggle("is-error", job.state === "error");
  els.jobTitle.textContent =
    job.state === "done"
      ? `${t("jobDone")}: ${job.pack}`
      : job.state === "error"
      ? `${t("jobErr")}: ${job.pack}`
      : `${t("jobProc")} ${job.pack}`;
  els.jobPct.textContent = `${job.percent || 0}%`;
  els.jobFill.style.width = `${job.percent || 0}%`;
  els.jobBarWrap.setAttribute("aria-valuenow", String(job.percent || 0));

  const extra =
    job.total > 0 && job.state === "downloading"
      ? ` (${fmtMbFromBytes(job.downloaded)} / ${fmtMbFromBytes(job.total)})`
      : "";
  els.jobMsg.textContent = `${job.message || ""}${extra}`;

  if (["downloading", "verifying", "extracting"].includes(job.state)) {
    startPolling();
  } else {
    stopPolling();
  }
}

function startPolling() {
  if (state.pollTimer) return;
  state.pollTimer = setInterval(loadStatus, 900);
}

function stopPolling() {
  if (!state.pollTimer) return;
  clearInterval(state.pollTimer);
  state.pollTimer = null;
}

function setLanguage(lang) {
  state.lang = lang === "en" ? "en" : "id";
  localStorage.setItem("xms_lang", state.lang);
  applyStaticI18n();
  renderStatus();
  renderCategories();
  renderPacks();
  handleJobPolling();
}

els.btnLang.addEventListener("click", () => {
  setLanguage(state.lang === "id" ? "en" : "id");
});

els.chips.addEventListener("click", (e) => {
  const btn = e.target.closest("[data-cat]");
  if (!btn) return;
  state.categoryKey = btn.dataset.cat;
  renderCategories();
  renderPacks();
});

els.search.addEventListener("input", (e) => {
  state.query = e.target.value;
  renderPacks();
});

els.sections.addEventListener("click", async (e) => {
  const btn = e.target.closest("[data-action]");
  if (!btn) return;
  const id = btn.dataset.id;
  const pack = (state.catalog.packs || []).find((p) => p.id === id);
  if (!pack) return;

  if (btn.dataset.action === "install") {
    const url = resolveDownloadUrl(pack);
    const sha = pack.sha256 || "skip";
    const bytes = pack.archive_bytes || 0;
    const res = await runCtl(["install", pack.id, url, sha, String(bytes)]);
    if (res.errno !== 0) {
      toast(`${t("errStart")}: ${res.stderr}`);
      return;
    }
    await loadStatus();
  } else if (btn.dataset.action === "remove") {
    btn.disabled = true;
    const res = await runCtl(["remove", pack.id]);
    if (res.errno !== 0) {
      toast(`${t("errRemove")}: ${res.stderr}`);
      btn.disabled = false;
      return;
    }
    toast(`${pack.name} ${t("removedToast")}`);
    await loadStatus();
  }
});

els.btnSync.addEventListener("click", syncRemoteCatalog);

els.btnReboot.addEventListener("click", async () => {
  els.btnReboot.disabled = true;
  await runCtl(["reboot"]);
});

els.btnSettings.addEventListener("click", () => {
  els.selectLang.value = state.lang;
  els.inputMirror.value = (state.device && state.device.mirror_url) || "";
  els.selectMode.value = (state.device && state.device.mount_override) || "auto";
  els.settingsModal.showModal();
});
els.btnCloseSettings.addEventListener("click", () => els.settingsModal.close());
els.btnCancelSettings.addEventListener("click", () => els.settingsModal.close());
els.btnPresetHf.addEventListener("click", () => {
  els.inputMirror.value = state.catalog.base_url || "";
});
els.btnPresetGh.addEventListener("click", () => {
  els.inputMirror.value = state.catalog.fallback_base_url || "";
});
els.btnSaveSettings.addEventListener("click", async () => {
  setLanguage(els.selectLang.value);
  await runCtl(["set_mirror", els.inputMirror.value.trim()]);
  await runCtl(["set_mount_mode", els.selectMode.value]);
  els.settingsModal.close();
  toast(t("settingsSaved"));
  await loadStatus();
});

els.btnLogs.addEventListener("click", async () => {
  els.logsModal.showModal();
  const res = await runCtl(["read_log"]);
  els.logsBox.textContent = res.errno === 0 ? res.stdout : res.stderr || "Error";
});
els.btnCloseLogs.addEventListener("click", () => els.logsModal.close());
els.btnOkLogs.addEventListener("click", () => els.logsModal.close());

applyStaticI18n();
loadLocalCatalog().then(loadStatus);
