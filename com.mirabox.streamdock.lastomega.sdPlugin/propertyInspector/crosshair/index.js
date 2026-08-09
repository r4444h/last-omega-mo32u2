const $local = false;
const $back = false;
const $dom = {
  main: $('.sdpi-wrapper'),
  mode: $('#mode'),
  style: $('#style'),
  statusText: $('#statusText'),
  btnRefresh: $('#btnRefresh'),
  btnOn: $('#btnOn'),
  btnOff: $('#btnOff')
};

function applySettingsToUi(settings = {}) {
  if (settings.mode) $dom.mode.value = settings.mode;
  if (settings.style) $dom.style.value = String(settings.style);
}

function renderStatus(payload) {
  if (!payload || payload.ok === false) {
    $dom.statusText.textContent = payload?.error || 'Error';
    return;
  }
  const on = !!payload.enabled;
  const style = payload.style || $dom.style.value || 1;
  const devices = payload.devices != null ? `, HID=${payload.devices}` : '';
  $dom.statusText.textContent = `${on ? 'ON' : 'OFF'} (style ${style}${devices})`;
}

function saveSettings({ applyStyleNow = false } = {}) {
  $websocket.sendToPlugin({
    type: 'applySettings',
    mode: $dom.mode.value,
    style: Number($dom.style.value) || 1,
    nameFilter: 'MO32U2',
    applyStyleNow: !!applyStyleNow
  });
}

const $propEvent = {
  didReceiveSettings(data) {
    applySettingsToUi(data?.settings || {});
  },

  sendToPropertyInspector(data) {
    if (!data) return;
    if (data.settings) applySettingsToUi(data.settings);
    if (data.type === 'crosshairStatus') renderStatus(data);
  }
};

$dom.mode.addEventListener('change', () => saveSettings());
$dom.style.addEventListener('change', () => saveSettings({ applyStyleNow: true }));
$dom.btnRefresh.addEventListener('click', () => {
  saveSettings();
  $websocket.sendToPlugin({ type: 'refresh' });
});
$dom.btnOn.addEventListener('click', () => {
  saveSettings();
  $websocket.sendToPlugin({ type: 'run', action: 'on' });
});
$dom.btnOff.addEventListener('click', () => {
  saveSettings();
  $websocket.sendToPlugin({ type: 'run', action: 'off' });
});
