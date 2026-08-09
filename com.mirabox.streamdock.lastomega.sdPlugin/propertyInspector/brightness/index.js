const $local = false;
const $back = false;
const $dom = {
  main: $('.sdpi-wrapper'),
  nameFilter: $('#nameFilter'),
  stepSdr: $('#stepSdr'),
  stepHdr: $('#stepHdr'),
  hdrMin: $('#hdrMin'),
  hdrMax: $('#hdrMax'),
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
  if (!Number.isFinite(n) || n < 1) return fallback;
  return Math.min(3600, n);
}

function normalizeBound(value, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.min(10000, n));
}

function isEditingFields() {
  return (
    document.activeElement === $dom.stepSdr ||
    document.activeElement === $dom.stepHdr ||
    document.activeElement === $dom.hdrMin ||
    document.activeElement === $dom.hdrMax ||
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
    $dom.stepHdr.value = normalizeStep(settings.stepHdr, 10);
  }
  if (settings.hdrMin != null && document.activeElement !== $dom.hdrMin) {
    $dom.hdrMin.value = normalizeBound(settings.hdrMin, 80);
  }
  if (settings.hdrMax != null && document.activeElement !== $dom.hdrMax) {
    $dom.hdrMax.value = normalizeBound(settings.hdrMax, 480);
  }
  if (settings.pollSec != null && document.activeElement !== $dom.pollSec) {
    $dom.pollSec.value = normalizePoll(settings.pollSec, 3);
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

  if (display.hdrEnabled) {
    $dom.statusText.textContent = `${display.name || 'Display'}: HDR, SDR ${display.sdrWhiteNits || display.value} nits`;
  } else {
    $dom.statusText.textContent = `${display.name || 'Display'}: brightness ${display.brightnessPercent ?? display.value}%`;
  }
}

function currentSettingsPayload() {
  let hdrMin = normalizeBound($dom.hdrMin.value, 80);
  let hdrMax = normalizeBound($dom.hdrMax.value, 480);
  if (hdrMax < hdrMin) {
    const tmp = hdrMin;
    hdrMin = hdrMax;
    hdrMax = tmp;
  }

  return {
    type: 'applySettings',
    nameFilter: $dom.nameFilter.value,
    stepSdr: normalizeStep($dom.stepSdr.value, 1),
    stepHdr: normalizeStep($dom.stepHdr.value, 10),
    pollSec: normalizePoll($dom.pollSec.value, 3),
    hdrMin,
    hdrMax
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

[$dom.stepSdr, $dom.stepHdr, $dom.hdrMin, $dom.hdrMax, $dom.pollSec].forEach((el) => {
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
