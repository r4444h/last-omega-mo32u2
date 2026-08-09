const $local = false;
const $back = false;
const $dom = {
  main: $('.sdpi-wrapper'),
  nameFilter: $('#nameFilter'),
  pollSec: $('#pollSec'),
  statusText: $('#statusText'),
  btnRefresh: $('#btnRefresh')
};

function applySettingsToUi(settings = {}) {
  if (settings.nameFilter) {
    ensureOption(settings.nameFilter);
    $dom.nameFilter.value = settings.nameFilter;
  }
  if (settings.pollSec != null) {
    $dom.pollSec.value = String(settings.pollSec);
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
    const hz = display.label || (display.hzRounded ? `${display.hzRounded}Hz` : '');
    opt.textContent = hz ? `${value} (${hz})` : value;
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
  const res =
    display.width && display.height ? `${display.width}×${display.height}` : '';
  const hz = display.label || (display.hzRounded ? `${display.hzRounded}Hz` : '—');
  $dom.statusText.textContent = res
    ? `${display.name || 'Display'}: ${hz} · ${res}`
    : `${display.name || 'Display'}: ${hz}`;
}

function saveSettings() {
  let poll = Math.round(Number($dom.pollSec.value));
  if (!Number.isFinite(poll) || poll < 5) poll = 5;
  if (poll > 3600) poll = 3600;
  $dom.pollSec.value = String(poll);
  $websocket.sendToPlugin({
    type: 'applySettings',
    nameFilter: $dom.nameFilter.value,
    pollSec: poll
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
    if (data.type === 'refreshRateStatus') {
      if (data.ok) renderStatus(data.display);
      else $dom.statusText.textContent = data.error || 'Error';
    }
  }
};

$dom.nameFilter.addEventListener('change', saveSettings);
$dom.pollSec.addEventListener('change', saveSettings);
$dom.pollSec.addEventListener('blur', saveSettings);
$dom.btnRefresh.addEventListener('click', () => {
  saveSettings();
  $websocket.sendToPlugin({ type: 'refresh' });
});
