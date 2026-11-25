import { exec, toast, hasKsuBridge } from "./ksu.js";

const CTL = "/data/adb/modules/xmsrom_oneui95_addons/scripts/addon_ctl.sh";
const REMOTE_CATALOG_URL =
  "https://raw.githubusercontent.com/Gustyx-Power/xmsrom-oneui9.5-patch-ksumodule/main/catalog.json";

const state = {
  catalog: { version: "1.0.0", base_url: "", fallback_base_url: "", packs: [] },
  device: null,
  category: "Semua",
  query: "",
  pollTimer: null,
};

const els = {
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
  list: document.getElementById("pack-list"),
  rebootBar: document.getElementById("reboot-bar"),
  btnReboot: document.getElementById("btn-reboot"),
  btnSync: document.getElementById("btn-sync"),
  btnLogs: document.getElementById("btn-logs"),
  btnSettings: document.getElementById("btn-settings"),
  settingsModal: document.getElementById("settings-modal"),
  inputMirror: document.getElementById("input-mirror"),
  selectMode: document.getElementById("select-mode"),
  btnSaveSettings: document.getElementById("btn-save-settings"),
  btnCloseSettings: document.getElementById("btn-close-settings"),
  btnPresetHf: document.getElementById("btn-preset-hf"),
  btnPresetGh: document.getElementById("btn-preset-gh"),
  logsModal: document.getElementById("logs-modal"),
  logsBox: document.getElementById("logs-box"),
  btnCloseLogs: document.getElementById("btn-close-logs"),
  btnOkLogs: document.getElementById("btn-ok-logs"),
};

function fmtMbFromBytes(bytes) {
  if (!bytes || bytes <= 0) return "0 MB";
  const mb = bytes / (1024 * 1024);
  return mb >= 1024 ? `${(mb / 1024).toFixed(2)} GB` : `${mb.toFixed(1)} MB`;
}

function fmtGbFromKb(kb) {
  return `${(kb / (1024 * 1024)).toFixed(1)} GB`;
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
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
    toast(`Gagal baca status: ${res.stderr}`);
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
  toast("Mengambil katalog terbaru...");
  const res = await runCtl(["fetch_catalog", REMOTE_CATALOG_URL]);
  els.btnSync.disabled = false;
  if (res.errno === 0 && res.stdout.trim()) {
    try {
      state.catalog = JSON.parse(res.stdout);
      renderCategories();
      renderPacks();
      toast("Katalog berhasil diperbarui");
      return;
    } catch (_) {}
  }
  toast("Gagal sync dari GitHub, memakai katalog lokal");
}

function renderStatus() {
  const d = state.device;
  if (!d) return;
  const labels = {
    magic_mount: d.has_nomount ? "MagicMount (NoMount ready)" : "MagicMount",
    nomount: "NoMount VFS",
    metamodule: "Metamodule",
    idle: d.has_nomount ? "Siap (NoMount)" : "Siap (MagicMount)",
  };
  els.engine.textContent = labels[d.mount_engine] || d.mount_engine;
  els.dataFree.textContent = fmtGbFromKb(d.data_free_kb);
  els.installedCount.textContent = `${d.installed.length} paket (${fmtMbFromBytes(d.staged_kb * 1024)})`;
  els.rebootBar.hidden = d.reboot_pending !== 1;
}

function renderCategories() {
  const cats = ["Semua", ...new Set((state.catalog.packs || []).map((p) => p.category))];
  els.chips.innerHTML = cats
    .map(
      (cat) =>
        `<button class="chip${state.category === cat ? " is-active" : ""}" type="button" role="tab" aria-selected="${
          state.category === cat
        }" data-cat="${escapeHtml(cat)}">${escapeHtml(cat)}</button>`
    )
    .join("");
}

function badgeClass(badge) {
  if (!badge) return "";
  const low = badge.toLowerCase();
  if (low.includes("eksperimen") || low.includes("berat")) return "badge-warn";
  if (low.includes("rekomendasi") || low.includes("ringan")) return "badge-ok";
  return "badge-info";
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
    const matchCat = state.category === "Semua" || p.category === state.category;
    const matchQ =
      !q ||
      p.name.toLowerCase().includes(q) ||
      p.description.toLowerCase().includes(q) ||
      p.id.toLowerCase().includes(q);
    return matchCat && matchQ;
  });

  if (!filtered.length) {
    els.list.innerHTML = '<div class="empty-state">Tidak ada paket yang cocok dengan pencarian ini.</div>';
    return;
  }

  els.list.innerHTML = filtered
    .map((p) => {
      const isInstalled = installedSet.has(p.id);
      const badgeHtml = p.badge
        ? `<span class="badge ${badgeClass(p.badge)}">${escapeHtml(p.badge)}</span>`
        : "";
      const noteHtml = p.note ? `<p class="pack-note">${escapeHtml(p.note)}</p>` : "";
      const missingHash = !p.sha256 || p.sha256.startsWith("PENDING");

      let actionBtn = "";
      if (isInstalled) {
        actionBtn = `<button class="btn btn-danger" type="button" data-action="remove" data-id="${escapeHtml(
          p.id
        )}" ${jobActive ? "disabled" : ""}>Hapus</button>`;
      } else if (missingHash && !p.archive_bytes) {
        actionBtn = `<button class="btn btn-secondary" type="button" disabled>Belum diunggah ke server</button>`;
      } else {
        actionBtn = `<button class="btn btn-primary" type="button" data-action="install" data-id="${escapeHtml(
          p.id
        )}" ${jobActive ? "disabled" : ""}>Pasang</button>`;
      }

      const sizeText = p.archive_bytes
        ? `Unduh ${fmtMbFromBytes(p.archive_bytes)} · Ekstrak ${p.unpacked_mb} MB`
        : `Ukuran APK ~${p.unpacked_mb} MB`;

      return `
        <article class="pack-card${isInstalled ? " is-installed" : ""}">
          <div class="pack-top">
            <div class="pack-title-row">
              <h3 class="pack-name">${escapeHtml(p.name)}</h3>
              ${badgeHtml}
              ${isInstalled ? '<span class="badge badge-ok">Terpasang</span>' : ""}
            </div>
            <span class="pack-meta">${escapeHtml(sizeText)}</span>
          </div>
          <p class="pack-desc">${escapeHtml(p.description)}</p>
          ${noteHtml}
          <div class="pack-footer">
            <span class="pack-targets">${escapeHtml((p.targets || []).join(", "))}</span>
            ${actionBtn}
          </div>
        </article>`;
    })
    .join("");
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
      ? `Selesai: ${job.pack}`
      : job.state === "error"
      ? `Gagal: ${job.pack}`
      : `Memproses ${job.pack} (${job.state})`;
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

els.chips.addEventListener("click", (e) => {
  const btn = e.target.closest("[data-cat]");
  if (!btn) return;
  state.category = btn.dataset.cat;
  renderCategories();
  renderPacks();
});

els.search.addEventListener("input", (e) => {
  state.query = e.target.value;
  renderPacks();
});

els.list.addEventListener("click", async (e) => {
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
      toast(`Gagal memulai: ${res.stderr}`);
      return;
    }
    await loadStatus();
  } else if (btn.dataset.action === "remove") {
    btn.disabled = true;
    const res = await runCtl(["remove", pack.id]);
    if (res.errno !== 0) {
      toast(`Gagal menghapus: ${res.stderr}`);
      btn.disabled = false;
      return;
    }
    toast(`${pack.name} dihapus`);
    await loadStatus();
  }
});

els.btnSync.addEventListener("click", syncRemoteCatalog);

els.btnReboot.addEventListener("click", async () => {
  els.btnReboot.disabled = true;
  await runCtl(["reboot"]);
});

els.btnSettings.addEventListener("click", () => {
  els.inputMirror.value = (state.device && state.device.mirror_url) || "";
  els.selectMode.value = (state.device && state.device.mount_override) || "auto";
  els.settingsModal.showModal();
});
els.btnCloseSettings.addEventListener("click", () => els.settingsModal.close());
els.btnPresetHf.addEventListener("click", () => {
  els.inputMirror.value = state.catalog.base_url || "";
});
els.btnPresetGh.addEventListener("click", () => {
  els.inputMirror.value = state.catalog.fallback_base_url || "";
});
els.btnSaveSettings.addEventListener("click", async () => {
  await runCtl(["set_mirror", els.inputMirror.value.trim()]);
  await runCtl(["set_mount_mode", els.selectMode.value]);
  els.settingsModal.close();
  toast("Pengaturan disimpan");
  await loadStatus();
});

els.btnLogs.addEventListener("click", async () => {
  els.logsModal.showModal();
  const res = await runCtl(["read_log"]);
  els.logsBox.textContent = res.errno === 0 ? res.stdout : res.stderr || "Gagal membaca log";
});
els.btnCloseLogs.addEventListener("click", () => els.logsModal.close());
els.btnOkLogs.addEventListener("click", () => els.logsModal.close());

loadLocalCatalog().then(loadStatus);
