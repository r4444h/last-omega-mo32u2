const $local = false;
const $back = false;
const $dom = {
  main: $('.sdpi-wrapper'),
  nameFilter: $('#nameFilter'),
  mode: $('#mode'),
  statusText: $('#statusText'),
  btnRefresh: $('#btnRefresh'),
  btnOn: $('#btnOn'),
  btnOff: $('#btnOff')
};

function applySettingsToUi(settings = {}) {
  if (settings.nameFilter) {
    ensureOption(settings.nameFilter);
    $dom.nameFilter.value = settings.nameFilter;
  }
  if (settings.mode) {
    $dom.mode.value = settings.mode;
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
    const hdr = display.hdrSupported
      ? display.hdrEnabled
        ? 'HDR ON'
        : 'HDR OFF'
      : 'no HDR';
    opt.textContent = `${value} (${hdr})`;
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
  const state = display.hdrSupported
    ? display.hdrEnabled
      ? `ON (${display.mode})`
      : `OFF (${display.mode})`
    : 'HDR unsupported';
  $dom.statusText.textContent = `${display.name}: ${state}`;
}

function saveSettings() {
  $websocket.sendToPlugin({
    type: 'applySettings',
    mode: $dom.mode.value,
    nameFilter: $dom.nameFilter.value
  });
}

const $propEvent = {
  didReceiveSettings(data) {
    applySettingsToUi(data?.settings || {});
  },

  sendToPropertyInspector(data) {
    if (!data) return;
    if (data.settings) applySettingsToUi(data.settings);
    if (data.type === 'displayList' && data.ok) renderDisplays(data.displays || []);
    if (data.type === 'hdrStatus') {
      if (data.ok) renderStatus(data.display);
      else $dom.statusText.textContent = data.error || 'Error';
    }
  }
};

$dom.nameFilter.addEventListener('change', saveSettings);
$dom.mode.addEventListener('change', saveSettings);
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
