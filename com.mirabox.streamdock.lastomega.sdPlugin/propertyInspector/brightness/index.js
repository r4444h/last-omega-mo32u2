const $local = false;
const $back = false;
const $dom = {
  main: $('.sdpi-wrapper'),
  nameFilter: $('#nameFilter'),
  stepSdr: $('#stepSdr'),
  stepHdr: $('#stepHdr'),
  pollSec: $('#pollSec'),
  statusText: $('#statusText'),
  btnRefresh: $('#btnRefresh'),
  btnDown: $('#btnDown'),
  btnUp: $('#btnUp')
};

let saveTimer = null;

function normalizeStep(value, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.min(1000, n);
}

function normalizePoll(value, fallback) {
  const n = Math.round(Number(value));
  if (!Number.isFinite(n) || n < 5) return fallback;
  return Math.min(3600, n);
}

function isEditingFields() {
  return (
    document.activeElement === $dom.stepSdr ||
    document.activeElement === $dom.stepHdr ||
    document.activeElement === $dom.pollSec
  );
}

function applySettingsToUi(settings = {}, { force = false } = {}) {
  if (settings.nameFilter && document.activeElement !== $dom.nameFilter) {
    ensureOption(settings.nameFilter);
    $dom.nameFilter.value = settings.nameFilter;
  }

  if (!force && isEditingFields()) return;

  if (settings.stepSdr != null && document.activeElement !== $dom.stepSdr) {
    $dom.stepSdr.value = normalizeStep(settings.stepSdr, 1);
  }
  if (settings.stepHdr != null && document.activeElement !== $dom.stepHdr) {
    $dom.stepHdr.value = settings.controlVersion === 2 ? normalizeStep(settings.stepHdr, 1) : 1;
  }
  if (settings.pollSec != null && document.activeElement !== $dom.pollSec) {
    $dom.pollSec.value = normalizePoll(settings.pollSec, 15);
  }
}

function ensureOption(value) {
  const exists = Array.from($dom.nameFilter.options).some((opt) => opt.value === value);
  if (!exists) {
    const opt = document.createElement('option');
    opt.value = value;
    opt.textContent = value;
    $dom.nameFilter.appendChild(opt);
  }
}

function renderDisplays(displays = []) {
  const current = $dom.nameFilter.value || 'MO32U2';
  $dom.nameFilter.innerHTML = '';

  if (!displays.length) {
    ensureOption('MO32U2');
    $dom.nameFilter.value = 'MO32U2';
    return;
  }

  displays.forEach((display) => {
    const value = display.name || 'Display';
    const opt = document.createElement('option');
    opt.value = value;
    opt.textContent = `${value} (${display.label || '—'})`;
    $dom.nameFilter.appendChild(opt);
  });

  ensureOption(current);
  $dom.nameFilter.value = current;
}

function renderStatus(display) {
  if (!display) {
    $dom.statusText.textContent = '—';
    return;
  }
  const available = display.controlAvailable !== false;
  $dom.btnDown.disabled = !available;
  $dom.btnUp.disabled = !available;
  $dom.stepHdr.disabled = !available;
  if (!available) {
    $dom.statusText.textContent = 'Яркость HDR — в меню монитора (OSD). Нажатие крутилки переключает HDR/SDR.';
    return;
  }

  const mode = display.hdrEnabled ? 'HDR' : 'SDR';
  const value = display.brightnessPercent;
  $dom.statusText.textContent = value == null ? `${display.name || 'Display'}: unavailable` :
    `${display.name || 'Display'}: ${mode}, monitor ${value}%`;
}

function currentSettingsPayload() {
  return {
    type: 'applySettings',
    nameFilter: $dom.nameFilter.value,
    stepSdr: normalizeStep($dom.stepSdr.value, 1),
    stepHdr: normalizeStep($dom.stepHdr.value, 1),
    pollSec: normalizePoll($dom.pollSec.value, 15),
    controlVersion: 2,
    performanceVersion: 1
  };
}

function saveSettingsSoon() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    $websocket.sendToPlugin(currentSettingsPayload());
  }, 400);
}

function saveSettingsNow() {
  clearTimeout(saveTimer);
  $websocket.sendToPlugin(currentSettingsPayload());
}

const $propEvent = {
  didReceiveSettings(data) {
    applySettingsToUi(data?.settings || {}, { force: !isEditingFields() });
  },

  sendToPropertyInspector(data) {
    if (!data) return;

    if (data.type === 'brightnessStatus') {
      if (data.ok) renderStatus(data.display);
      else $dom.statusText.textContent = data.error || 'Error';
      return;
    }

    if (data.type === 'displayList') {
      if (data.settings) applySettingsToUi(data.settings);
      if (data.ok) renderDisplays(data.displays || []);
      return;
    }

    if (data.settings) applySettingsToUi(data.settings);
  }
};

$dom.nameFilter.addEventListener('change', saveSettingsNow);

[$dom.stepSdr, $dom.stepHdr, $dom.pollSec].forEach((el) => {
  el.addEventListener('input', saveSettingsSoon);
  el.addEventListener('change', saveSettingsNow);
  el.addEventListener('blur', saveSettingsNow);
});

$dom.btnRefresh.addEventListener('click', () => {
  saveSettingsNow();
  $websocket.sendToPlugin({ type: 'refresh' });
});
$dom.btnDown.addEventListener('click', () => {
  saveSettingsNow();
  $websocket.sendToPlugin({ type: 'adjust', delta: -1 });
});
$dom.btnUp.addEventListener('click', () => {
  saveSettingsNow();
  $websocket.sendToPlugin({ type: 'adjust', delta: 1 });
});
