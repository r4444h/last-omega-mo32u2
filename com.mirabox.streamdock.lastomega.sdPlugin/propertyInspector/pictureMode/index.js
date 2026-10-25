const $local = false;
const $back = false;
const $dom = {
  main: $('.sdpi-wrapper'),
  nameFilter: $('#nameFilter'),
  pollSec: $('#pollSec'),
  statusText: $('#statusText'),
  modesText: $('#modesText'),
  btnRefresh: $('#btnRefresh'),
  btnPrev: $('#btnPrev'),
  btnNext: $('#btnNext')
};

function applySettingsToUi(settings = {}) {
  if (settings.nameFilter) $dom.nameFilter.value = settings.nameFilter;
  if (settings.pollSec != null) $dom.pollSec.value = String(settings.pollSec);
}

function renderStatus(payload) {
  if (!payload || payload.ok === false) {
    $dom.statusText.textContent = payload?.error || 'Error';
    return;
  }
  const available = payload.controlAvailable !== false;
  $dom.btnPrev.disabled = !available;
  $dom.btnNext.disabled = !available;
  if (!available) {
    $dom.statusText.textContent = 'HDR-профили — в меню монитора (OSD).';
    $dom.modesText.textContent = 'Профили SDR доступны после выключения HDR.';
    return;
  }
  const hdr = payload.hdrEnabled ? 'HDR' : 'SDR';
  const src = payload.source ? ` [${payload.source}]` : '';
  $dom.statusText.textContent = `${hdr}: ${payload.name || payload.short || '—'} (${payload.value})${src}`;
  if (Array.isArray(payload.modes)) {
    $dom.modesText.textContent = payload.modes.map((m) => m.name || m.short).join(' · ');
  }
}

function saveSettings() {
  $websocket.sendToPlugin({
    type: 'applySettings',
    nameFilter: $dom.nameFilter.value || 'MO32U2',
    pollSec: Math.max(5, Number($dom.pollSec.value) || 30),
    performanceVersion: 1
  });
}

const $propEvent = {
  didReceiveSettings(data) {
    applySettingsToUi(data?.settings || {});
  },

  sendToPropertyInspector(data) {
    if (!data) return;
    if (data.settings) applySettingsToUi(data.settings);
    if (data.type === 'pictureModeStatus') renderStatus(data);
  }
};

$dom.nameFilter.addEventListener('change', saveSettings);
$dom.pollSec.addEventListener('change', saveSettings);
$dom.btnRefresh.addEventListener('click', () => {
  saveSettings();
  $websocket.sendToPlugin({ type: 'refresh' });
});
$dom.btnPrev.addEventListener('click', () => {
  saveSettings();
  $websocket.sendToPlugin({ type: 'delta', delta: -1 });
});
$dom.btnNext.addEventListener('click', () => {
  saveSettings();
  $websocket.sendToPlugin({ type: 'delta', delta: 1 });
});
