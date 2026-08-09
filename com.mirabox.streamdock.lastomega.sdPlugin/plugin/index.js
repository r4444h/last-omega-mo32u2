const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');
const { Plugins, Actions, log } = require('./utils/plugin');

const plugin = new Plugins();
const HDR_SCRIPT = path.join(__dirname, 'HdrControl.ps1');
const BRIGHTNESS_SCRIPT = path.join(__dirname, 'BrightnessControl.ps1');
const CROSSHAIR_SCRIPT = path.join(__dirname, 'CrosshairControl.ps1');
const PICTURE_SCRIPT = path.join(__dirname, 'PictureModeControl.ps1');
const REFRESH_SCRIPT = path.join(__dirname, 'RefreshRateControl.ps1');
const STATE_CACHE_FILE = path.join(__dirname, 'ui-state-cache.json');
const DEFAULT_FILTER = 'MO32U2';
const timers = {};
const brightnessByFilter = {}; // shared live state per monitor filter
const hdrByFilter = {}; // shared HDR on/off cache per monitor filter
const crosshairByFilter = {}; // shared crosshair on/off cache
const pictureByFilter = {}; // shared picture-mode state per monitor
const refreshRateByFilter = {}; // shared Hz cache per monitor
const controllerByContext = {}; // Keypad | Knob | Encoder
const lastVisualByContext = {}; // skip redundant setImage/setTitle (scene flicker)
const BRIGHTNESS_COMMIT_MS = 280;
// Browse freely; apply only after the dial stops. Ignore dial only while set runs.
const PICTURE_COMMIT_MS = 850;
const PICTURE_HOLD_MS = 0;
const REFRESH_RATE_POLL_DEFAULT = 60; // rare — Hz rarely changes
const SDR_MIN = 0;
const SDR_MAX = 100;
const HDR_MIN_DEFAULT = 80;
const HDR_MAX_DEFAULT = 480;
const VALUE_EPS = 0.001;

function readStateCacheFile() {
  try {
    const raw = JSON.parse(fs.readFileSync(STATE_CACHE_FILE, 'utf8'));
    return {
      brightness: raw.brightness && typeof raw.brightness === 'object' ? raw.brightness : {},
      hdr: raw.hdr && typeof raw.hdr === 'object' ? raw.hdr : {},
      crosshair: raw.crosshair && typeof raw.crosshair === 'object' ? raw.crosshair : {},
      picture: raw.picture && typeof raw.picture === 'object' ? raw.picture : {},
      refreshRate:
        raw.refreshRate && typeof raw.refreshRate === 'object' ? raw.refreshRate : {}
    };
  } catch (_) {
    return { brightness: {}, hdr: {}, crosshair: {}, picture: {}, refreshRate: {} };
  }
}

function writeStateCacheFile() {
  try {
    const brightness = {};
    for (const [filter, state] of Object.entries(brightnessByFilter)) {
      if (!state || !Number.isFinite(state.value)) continue;
      brightness[filter] = {
        value: state.value,
        hdrEnabled: !!state.hdrEnabled,
        unit: state.unit || (state.hdrEnabled ? 'nits' : 'percent'),
        lastSentValue: state.lastSentValue
      };
    }
    const hdr = {};
    for (const [filter, state] of Object.entries(hdrByFilter)) {
      if (!state) continue;
      hdr[filter] = {
        enabled: !!state.enabled,
        label: state.label || (state.enabled ? 'HDR ON' : 'HDR OFF')
      };
    }
    const crosshair = {};
    for (const [filter, state] of Object.entries(crosshairByFilter)) {
      if (!state) continue;
      crosshair[filter] = {
        enabled: !!state.enabled,
        style: Number(state.style) > 0 ? Number(state.style) : 1,
        label: state.label || (state.enabled ? 'AIM ON' : 'AIM OFF')
      };
    }

    const picture = {};
    for (const [filter, state] of Object.entries(pictureByFilter)) {
      if (!state) continue;
      picture[filter] = {
        value: state.value,
        short: state.short || state.label || '',
        name: state.name || '',
        hdrEnabled: !!state.hdrEnabled,
        lastSentValue: state.lastSentValue,
        modes: Array.isArray(state.modes) ? state.modes.slice(0, 16) : undefined
      };
    }

    const refreshRate = {};
    for (const [filter, state] of Object.entries(refreshRateByFilter)) {
      if (!state || !Number.isFinite(state.hzRounded)) continue;
      refreshRate[filter] = {
        hz: state.hz,
        hzRounded: state.hzRounded,
        label: state.label || `${state.hzRounded}Hz`
      };
    }

    // Fixed-size overwrite only (no append / history).
    const payload = JSON.stringify({
      brightness,
      hdr,
      crosshair,
      picture,
      refreshRate,
      updatedAt: Date.now()
    });
    if (payload.length > 8192) {
      log.error('ui-state-cache too large, skip write', payload.length);
      return;
    }
    fs.writeFileSync(STATE_CACHE_FILE, payload, 'utf8');
  } catch (error) {
    log.error('writeStateCacheFile', error);
  }
}

function hydrateStateCache() {
  const disk = readStateCacheFile();
  for (const [filter, cached] of Object.entries(disk.brightness)) {
    if (brightnessByFilter[filter]) continue;
    const value = Number(cached.value);
    if (!Number.isFinite(value)) continue;
    brightnessByFilter[filter] = {
      value,
      hdrEnabled: !!cached.hdrEnabled,
      unit: cached.unit || (cached.hdrEnabled ? 'nits' : 'percent'),
      commitTimer: null,
      committing: false,
      loading: false,
      pendingTicks: 0,
      lastSentValue: cached.lastSentValue
    };
  }
  for (const [filter, cached] of Object.entries(disk.hdr)) {
    if (hdrByFilter[filter]) continue;
    hdrByFilter[filter] = {
      enabled: !!cached.enabled,
      label: cached.label || (cached.enabled ? 'HDR ON' : 'HDR OFF')
    };
  }
  for (const [filter, cached] of Object.entries(disk.crosshair)) {
    if (crosshairByFilter[filter]) continue;
    const style = Number(cached.style);
    crosshairByFilter[filter] = {
      enabled: !!cached.enabled,
      style: Number.isFinite(style) && style >= 1 && style <= 4 ? style : 1,
      label: cached.label || (cached.enabled ? 'AIM ON' : 'AIM OFF')
    };
  }
  for (const [filter, cached] of Object.entries(disk.picture || {})) {
    if (pictureByFilter[filter]) continue;
    const value = Number(cached.value);
    if (!Number.isFinite(value)) continue;
    const modes = normalizePictureModes(cached.modes);
    pictureByFilter[filter] = {
      value,
      short: cached.short || cached.label || String(value),
      name: cached.name || cached.short || String(value),
      hdrEnabled: !!cached.hdrEnabled,
      modes: modes || [],
      commitTimer: null,
      committing: false,
      pendingValue: null,
      holdUntil: 0,
      loadingModes: false,
      lastSentValue: Number.isFinite(Number(cached.lastSentValue))
        ? Number(cached.lastSentValue)
        : value
    };
  }
  for (const [filter, cached] of Object.entries(disk.refreshRate || {})) {
    if (refreshRateByFilter[filter]) continue;
    const hzRounded = Number(cached.hzRounded);
    if (!Number.isFinite(hzRounded) || hzRounded <= 0) continue;
    refreshRateByFilter[filter] = {
      hz: Number(cached.hz) || hzRounded,
      hzRounded,
      label: cached.label || `${hzRounded}Hz`
    };
  }
}

hydrateStateCache();


function runPs(scriptPath, { action, nameFilter, delta, value, stepSdr, stepHdr }) {
  const args = [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    scriptPath,
    '-Action',
    action
  ];

  if (nameFilter) {
    args.push('-NameFilter', nameFilter);
  } else {
    args.push('-Primary');
  }

  if (typeof delta === 'number' && delta !== 0) {
    args.push('-Delta', String(delta));
  }

  if (typeof value === 'number' && value >= 0) {
    args.push('-Value', String(value));
  }

  if (typeof stepSdr === 'number' && stepSdr > 0) {
    args.push('-StepSdr', String(Math.round(stepSdr)));
  }

  if (typeof stepHdr === 'number' && stepHdr > 0) {
    args.push('-StepHdr', String(Math.round(stepHdr)));
  }

  return new Promise((resolve, reject) => {
    execFile(
      'powershell.exe',
      args,
      { windowsHide: true, timeout: 15000, encoding: 'utf8' },
      (error, stdout, stderr) => {
        if (error) {
          log.error(path.basename(scriptPath), 'failed', error.message, stderr);
          reject(new Error(stderr || error.message));
          return;
        }

        const text = String(stdout || '').trim();
        const jsonLine = text
          .split(/\r?\n/)
          .map((line) => line.trim())
          .filter(Boolean)
          .pop();

        try {
          resolve(JSON.parse(jsonLine));
        } catch (parseError) {
          log.error(path.basename(scriptPath), 'bad JSON', text);
          reject(parseError);
        }
      }
    );
  });
}

function runHdr(opts) {
  return runPs(HDR_SCRIPT, opts);
}

function runBrightness(opts) {
  return runPs(BRIGHTNESS_SCRIPT, opts);
}

function runRefreshRate(opts) {
  return runPs(REFRESH_SCRIPT, opts);
}

function runCrosshair({ action, style }) {
  const args = [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    CROSSHAIR_SCRIPT,
    '-Action',
    action
  ];

  if (typeof style === 'number' && style >= 1 && style <= 4) {
    args.push('-Style', String(Math.round(style)));
  }

  return new Promise((resolve, reject) => {
    execFile(
      'powershell.exe',
      args,
      { windowsHide: true, timeout: 10000, encoding: 'utf8' },
      (error, stdout, stderr) => {
        if (error) {
          log.error('CrosshairControl.ps1', 'failed', error.message, stderr);
          reject(new Error(stderr || error.message));
          return;
        }

        const text = String(stdout || '').trim();
        const jsonLine = text
          .split(/\r?\n/)
          .map((line) => line.trim())
          .filter(Boolean)
          .pop();

        try {
          resolve(JSON.parse(jsonLine));
        } catch (parseError) {
          log.error('CrosshairControl.ps1', 'bad JSON', text);
          reject(parseError);
        }
      }
    );
  });
}

function runPictureMode({ action, nameFilter, value, delta }) {
  const args = [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    PICTURE_SCRIPT,
    '-Action',
    action,
    '-NameFilter',
    nameFilter || DEFAULT_FILTER
  ];

  if (typeof value === 'number' && value >= 0) {
    args.push('-Value', String(Math.round(value)));
  }
  if (typeof delta === 'number' && delta !== 0) {
    args.push('-Delta', String(Math.round(delta)));
  }

  return new Promise((resolve, reject) => {
    execFile(
      'powershell.exe',
      args,
      { windowsHide: true, timeout: 20000, encoding: 'utf8' },
      (error, stdout, stderr) => {
        if (error) {
          log.error('PictureModeControl.ps1', 'failed', error.message, stderr);
          reject(new Error(stderr || error.message));
          return;
        }

        const text = String(stdout || '').trim();
        const jsonLine = text
          .split(/\r?\n/)
          .map((line) => line.trim())
          .filter(Boolean)
          .pop();

        try {
          resolve(JSON.parse(jsonLine));
        } catch (parseError) {
          log.error('PictureModeControl.ps1', 'bad JSON', text);
          reject(parseError);
        }
      }
    );
  });
}

function keyImage(label) {
  const text = String(label);
  const safe = text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
  const fontSize = text.length >= 5 ? 24 : 28;

  const svg = `
<svg xmlns="http://www.w3.org/2000/svg" width="144" height="144" viewBox="0 0 144 144">
  <text x="72" y="78" text-anchor="middle" dominant-baseline="middle"
        font-family="Segoe UI, Arial, sans-serif" font-size="${fontSize}" font-weight="700"
        fill="#FFFFFF">${safe}</text>
</svg>`.trim();

  return `data:image/svg+xml;charset=utf8,${encodeURIComponent(svg)}`;
}

function brightnessKeyImage(label) {
  const text = String(label);
  const safe = text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
  const fontSize = text.length >= 5 ? 22 : 26;

  // Small white sun icon + brightness value, centered as a group
  const svg = `
<svg xmlns="http://www.w3.org/2000/svg" width="144" height="144" viewBox="0 0 144 144">
  <g transform="translate(18 52)">
    <circle cx="18" cy="18" r="7" fill="none" stroke="#FFFFFF" stroke-width="2.5"/>
    <g stroke="#FFFFFF" stroke-width="2.5" stroke-linecap="round">
      <line x1="18" y1="2" x2="18" y2="6"/>
      <line x1="18" y1="30" x2="18" y2="34"/>
      <line x1="2" y1="18" x2="6" y2="18"/>
      <line x1="30" y1="18" x2="34" y2="18"/>
      <line x1="6.7" y1="6.7" x2="9.5" y2="9.5"/>
      <line x1="26.5" y1="26.5" x2="29.3" y2="29.3"/>
      <line x1="29.3" y1="6.7" x2="26.5" y2="9.5"/>
      <line x1="9.5" y1="26.5" x2="6.7" y2="29.3"/>
    </g>
  </g>
  <text x="92" y="78" text-anchor="middle" dominant-baseline="middle"
        font-family="Segoe UI, Arial, sans-serif" font-size="${fontSize}" font-weight="700"
        fill="#FFFFFF">${safe}</text>
</svg>`.trim();

  return `data:image/svg+xml;charset=utf8,${encodeURIComponent(svg)}`;
}

function rememberController(context, payload) {
  const controller = payload?.controller;
  if (controller) controllerByContext[context] = controller;
}

function isKnobContext(context) {
  const c = String(controllerByContext[context] || '').toLowerCase();
  if (c === 'knob' || c === 'encoder') return true;
  // Keep knob title mode after scene switch if controller payload is late/missing.
  return lastVisualByContext[context]?.mode === 'knob';
}

function transparentKeyImage() {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="144" height="144" viewBox="0 0 144 144"></svg>`;
  return `data:image/svg+xml;charset=utf8,${encodeURIComponent(svg)}`;
}

function setContextState(context, stateIndex) {
  const prev = lastVisualByContext[context];
  if (prev && prev.state === stateIndex) return;
  plugin.setState(context, stateIndex);
  lastVisualByContext[context] = {
    ...(prev || {}),
    state: stateIndex
  };
}

// Knobs: stock plugins use setTitle (host keeps it across scenes).
// Keys: text baked into setImage SVG; skip re-send when label unchanged.
function applyVisual(context, label, { image = 'key', force = false } = {}) {
  const text = String(label ?? '');
  const knob = isKnobContext(context);
  const mode = knob ? 'knob' : image;
  const prev = lastVisualByContext[context] || {};

  if (knob) {
    // Title-only: no SVG reload flicker. Re-assert title; image only when leaving key mode.
    plugin.setTitle(context, text);
    if (prev.mode !== 'knob') {
      plugin.setImage(context, transparentKeyImage());
    }
    lastVisualByContext[context] = {
      label: text,
      mode: 'knob',
      state: prev.state
    };
    return true;
  }

  if (!force && !prev.stale && prev.label === text && prev.mode === mode) {
    return false;
  }

  plugin.setTitle(context, '');
  plugin.setImage(
    context,
    image === 'brightness' ? brightnessKeyImage(text) : keyImage(text)
  );

  lastVisualByContext[context] = {
    label: text,
    mode,
    state: prev.state
  };
  return true;
}

function applyKeyVisual(context, label, opts) {
  return applyVisual(context, label, { image: 'key', ...(opts || {}) });
}

function applyBrightnessVisual(context, label, opts) {
  return applyVisual(context, label, { image: 'brightness', ...(opts || {}) });
}

function hdrSettings(context) {
  return Object.assign(
    {
      mode: 'toggle',
      nameFilter: DEFAULT_FILTER
    },
    plugin.hdr.data[context] || {}
  );
}

function brightnessSettings(context) {
  const raw = Object.assign(
    {
      nameFilter: DEFAULT_FILTER,
      stepSdr: 1,
      stepHdr: 10,
      pollSec: 3,
      hdrMin: HDR_MIN_DEFAULT,
      hdrMax: HDR_MAX_DEFAULT
    },
    plugin.brightness.data[context] || {}
  );

  raw.stepSdr = normalizeStepValue(raw.stepSdr, 1);
  raw.stepHdr = normalizeStepValue(raw.stepHdr, 10);
  raw.pollSec = Math.max(1, Math.min(3600, Math.round(Number(raw.pollSec) || 3)));

  let hdrMin = Number(raw.hdrMin);
  let hdrMax = Number(raw.hdrMax);
  if (!Number.isFinite(hdrMin)) hdrMin = HDR_MIN_DEFAULT;
  if (!Number.isFinite(hdrMax)) hdrMax = HDR_MAX_DEFAULT;
  if (hdrMin < 0) hdrMin = 0;
  if (hdrMax < hdrMin) {
    const tmp = hdrMin;
    hdrMin = hdrMax;
    hdrMax = tmp;
  }
  raw.hdrMin = hdrMin;
  raw.hdrMax = hdrMax;
  return raw;
}

function normalizeStepValue(value, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.min(1000, n);
}

function restartBrightnessPoll(context) {
  if (timers[context]) {
    clearInterval(timers[context]);
    delete timers[context];
  }
  const settings = brightnessSettings(context);
  const ms = settings.pollSec * 1000;
  timers[context] = setInterval(() => {
    refreshBrightness(context).catch(() => {});
  }, ms);
}

function paintHdrFromCache(context) {
  const settings = hdrSettings(context);
  const filter = settings.nameFilter || DEFAULT_FILTER;
  const cached = hdrByFilter[filter];
  if (!cached) return false;
  applyKeyVisual(context, cached.label);
  setContextState(context, cached.enabled ? 1 : 0);
  return true;
}

function rememberHdrState(filter, enabled) {
  hdrByFilter[filter] = {
    enabled: !!enabled,
    label: enabled ? 'HDR ON' : 'HDR OFF'
  };
  writeStateCacheFile();
}

function crosshairSettings(context) {
  const raw = Object.assign(
    {
      mode: 'toggle',
      style: 1,
      nameFilter: DEFAULT_FILTER
    },
    plugin.crosshair?.data?.[context] || {}
  );
  let style = Number(raw.style);
  if (!Number.isFinite(style) || style < 1 || style > 4) style = 1;
  raw.style = Math.round(style);
  raw.mode = raw.mode || 'toggle';
  raw.nameFilter = raw.nameFilter || DEFAULT_FILTER;
  return raw;
}

function rememberCrosshairState(filter, enabled, style) {
  const s = Number(style);
  const safeStyle = Number.isFinite(s) && s >= 1 && s <= 4 ? Math.round(s) : 1;
  crosshairByFilter[filter] = {
    enabled: !!enabled,
    style: safeStyle,
    label: enabled ? 'AIM ON' : 'AIM OFF'
  };
  writeStateCacheFile();
}

function paintCrosshairFromCache(context) {
  const settings = crosshairSettings(context);
  const filter = settings.nameFilter || DEFAULT_FILTER;
  const cached = crosshairByFilter[filter];
  if (!cached) return false;
  applyKeyVisual(context, cached.label);
  setContextState(context, cached.enabled ? 1 : 0);
  return true;
}

async function refreshCrosshair(context) {
  const settings = crosshairSettings(context);
  const filter = settings.nameFilter || DEFAULT_FILTER;
  try {
    const result = await runCrosshair({ action: 'status', style: settings.style });
    const enabled = !!result.enabled;
    const style =
      Number(result.style) >= 1 && Number(result.style) <= 4
        ? Number(result.style)
        : settings.style;
    rememberCrosshairState(filter, enabled, style);
    applyKeyVisual(context, enabled ? 'AIM ON' : 'AIM OFF');
    setContextState(context, enabled ? 1 : 0);
    plugin.sendToPropertyInspector({
      type: 'crosshairStatus',
      ok: true,
      enabled,
      style,
      devices: result.devices,
      settings
    });
    return result;
  } catch (error) {
    log.error('refreshCrosshair', error);
    if (!paintCrosshairFromCache(context)) {
      applyKeyVisual(context, 'AIM ERR');
    }
    plugin.sendToPropertyInspector({
      type: 'crosshairStatus',
      ok: false,
      error: String(error.message || error),
      settings
    });
    return null;
  }
}

async function refreshHdr(context) {
  const settings = hdrSettings(context);
  const filter = settings.nameFilter || DEFAULT_FILTER;
  try {
    const result = await runHdr({
      action: 'status',
      nameFilter: filter
    });
    const display = result.display || {};
    const enabled = !!display.hdrEnabled;
    const label = enabled ? 'HDR ON' : 'HDR OFF';
    const prev = hdrByFilter[filter];
    const unchanged = prev && !!prev.enabled === enabled && prev.label === label;
    rememberHdrState(filter, enabled);
    if (!unchanged) {
      applyKeyVisual(context, label);
      setContextState(context, enabled ? 1 : 0);
    } else {
      paintHdrFromCache(context);
    }
    plugin.sendToPropertyInspector({
      type: 'hdrStatus',
      ok: true,
      display,
      settings
    });
    return display;
  } catch (error) {
    log.error('refreshHdr', error);
    if (!paintHdrFromCache(context)) {
      applyKeyVisual(context, 'HDR ERR');
    }
    plugin.sendToPropertyInspector({
      type: 'hdrStatus',
      ok: false,
      error: String(error.message || error),
      settings
    });
    return null;
  }
}

function brightnessLabel(value, hdrEnabled) {
  const rounded = Math.round(Number(value) * 10) / 10;
  const text = Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
  return hdrEnabled ? `${text}n` : `${text}%`;
}

function brightnessRange(settings, hdrEnabled) {
  if (hdrEnabled) {
    return {
      min: Number(settings.hdrMin ?? HDR_MIN_DEFAULT),
      max: Number(settings.hdrMax ?? HDR_MAX_DEFAULT)
    };
  }
  return { min: SDR_MIN, max: SDR_MAX };
}

function clampBrightnessValue(value, settings, hdrEnabled) {
  const { min, max } = brightnessRange(settings, hdrEnabled);
  const n = Number(value);
  if (!Number.isFinite(n)) return min;
  if (n < min) return min;
  if (n > max) return max;
  return n;
}

function valuesAlmostEqual(a, b) {
  return Math.abs(Number(a) - Number(b)) <= VALUE_EPS;
}

function settingsForFilter(filter) {
  let settings = {
    nameFilter: filter,
    stepSdr: 1,
    stepHdr: 10,
    hdrMin: HDR_MIN_DEFAULT,
    hdrMax: HDR_MAX_DEFAULT
  };
  forEachBrightnessContext(filter, (_context, ctxSettings) => {
    settings = ctxSettings;
  });
  return settings;
}

function monitorFilter(context) {
  return brightnessSettings(context).nameFilter || DEFAULT_FILTER;
}

function forEachBrightnessContext(filter, fn) {
  const data = plugin.brightness?.data || {};
  for (const context of Object.keys(data)) {
    if (monitorFilter(context) === filter) {
      fn(context, brightnessSettings(context));
    }
  }
}

function paintBrightnessEverywhere(filter, state) {
  const label = brightnessLabel(state.value, state.hdrEnabled);
  forEachBrightnessContext(filter, (context, settings) => {
    applyBrightnessVisual(context, label);
    setContextState(context, state.hdrEnabled ? 1 : 0);
    plugin.sendToPropertyInspector({
      type: 'brightnessStatus',
      ok: true,
      pending: !!state.commitTimer || !!state.committing,
      display: {
        name: filter,
        hdrEnabled: state.hdrEnabled,
        brightnessPercent: state.hdrEnabled ? undefined : state.value,
        sdrWhiteNits: state.hdrEnabled ? state.value : undefined,
        label,
        value: state.value,
        unit: state.unit
      },
      settings
    });
  });
}

function storeBrightnessFromDisplay(filter, display, keepTimers = true) {
  if (!display) return null;
  const prev = brightnessByFilter[filter] || {};
  const settings = settingsForFilter(filter);
  const hdrEnabled = !!display.hdrEnabled;
  const value = hdrEnabled
    ? Number(display.sdrWhiteNits ?? display.value ?? settings.hdrMin)
    : Number(display.brightnessPercent ?? display.value ?? 0);

  const state = {
    value: clampBrightnessValue(value, settings, hdrEnabled),
    hdrEnabled,
    unit: hdrEnabled ? 'nits' : 'percent',
    commitTimer: keepTimers ? prev.commitTimer || null : null,
    committing: keepTimers ? !!prev.committing : false,
    loading: false,
    pendingTicks: 0,
    lastSentValue: prev.lastSentValue
  };
  brightnessByFilter[filter] = state;
  return state;
}

function clearBrightnessCommit(filter) {
  const state = brightnessByFilter[filter];
  if (state?.commitTimer) {
    clearTimeout(state.commitTimer);
    state.commitTimer = null;
  }
}

function isBrightnessBusy(filter) {
  const state = brightnessByFilter[filter];
  return !!(state && (state.commitTimer || state.committing || state.loading));
}

async function applyBrightnessResult(context, result, settings, { fromCommit = false } = {}) {
  const filter = settings.nameFilter || DEFAULT_FILTER;
  const display = result?.display || {};

  if (!fromCommit && isBrightnessBusy(filter)) {
    return display;
  }

  const prev = brightnessByFilter[filter];
  const state = storeBrightnessFromDisplay(filter, display, !fromCommit);
  if (!state) return display;

  const unchanged =
    prev &&
    valuesAlmostEqual(prev.value, state.value) &&
    !!prev.hdrEnabled === !!state.hdrEnabled;

  if (unchanged && !fromCommit) {
    // Same reading — do not touch dial/key face (avoids scene/poll flicker).
    return display;
  }

  paintBrightnessEverywhere(filter, state);
  return display;
}

function paintBrightnessFromCache(context) {
  const filter = monitorFilter(context);
  const state = brightnessByFilter[filter];
  if (!state || !Number.isFinite(state.value)) return false;
  applyBrightnessVisual(context, brightnessLabel(state.value, state.hdrEnabled));
  setContextState(context, state.hdrEnabled ? 1 : 0);
  return true;
}

async function refreshBrightness(context) {
  const settings = brightnessSettings(context);
  const filter = settings.nameFilter || DEFAULT_FILTER;
  if (isBrightnessBusy(filter)) {
    paintBrightnessFromCache(context);
    return null;
  }

  try {
    const result = await runBrightness({
      action: 'status',
      nameFilter: filter
    });
    await applyBrightnessResult(context, result, settings);
    writeStateCacheFile();
    return result.display;
  } catch (error) {
    log.error('refreshBrightness', error);
    if (!paintBrightnessFromCache(context)) {
      applyBrightnessVisual(context, 'ERR');
    }
    plugin.sendToPropertyInspector({
      type: 'brightnessStatus',
      ok: false,
      error: String(error.message || error),
      settings
    });
    return null;
  }
}

async function commitBrightness(filter) {
  const state = brightnessByFilter[filter];
  if (!state) return;

  state.commitTimer = null;
  const settings = settingsForFilter(filter);
  const targetValue = clampBrightnessValue(state.value, settings, state.hdrEnabled);
  state.value = targetValue;

  // Already matching last sent hardware value — do not send again.
  if (state.lastSentValue != null && valuesAlmostEqual(targetValue, state.lastSentValue)) {
    state.committing = false;
    paintBrightnessEverywhere(filter, state);
    return;
  }

  state.committing = true;

  try {
    const result = await runBrightness({
      action: 'set',
      nameFilter: filter,
      value: targetValue
    });

    const latest = brightnessByFilter[filter];
    if (latest && !valuesAlmostEqual(latest.value, targetValue)) {
      latest.committing = false;
      scheduleBrightnessCommit(filter);
      paintBrightnessEverywhere(filter, latest);
      return;
    }

    if (result?.display) {
      storeBrightnessFromDisplay(filter, result.display, false);
    }

    const committed = brightnessByFilter[filter];
    if (committed) {
      committed.committing = false;
      committed.lastSentValue = clampBrightnessValue(
        committed.value,
        settingsForFilter(filter),
        committed.hdrEnabled
      );
      paintBrightnessEverywhere(filter, committed);
      writeStateCacheFile();
    }
  } catch (error) {
    log.error('commitBrightness', error);
    if (brightnessByFilter[filter]) {
      brightnessByFilter[filter].committing = false;
    }
  }
}

function scheduleBrightnessCommit(filter) {
  const state = brightnessByFilter[filter];
  if (!state) return;
  if (state.commitTimer) clearTimeout(state.commitTimer);
  state.commitTimer = setTimeout(() => {
    commitBrightness(filter).catch((error) => log.error('commit timer', error));
  }, BRIGHTNESS_COMMIT_MS);
}

function applyBrightnessDelta(filter, context, deltaTicks) {
  const settings = brightnessSettings(context);
  const shared = brightnessByFilter[filter];
  if (!shared || !Number.isFinite(shared.value)) return false;

  const step = shared.hdrEnabled ? settings.stepHdr : settings.stepSdr;
  const prev = shared.value;
  const next = clampBrightnessValue(prev + deltaTicks * step, settings, shared.hdrEnabled);
  shared.value = next;
  paintBrightnessEverywhere(filter, shared);

  // No real change after clamp (already at min/max) — do not send to monitor.
  if (valuesAlmostEqual(prev, next)) {
    return false;
  }

  scheduleBrightnessCommit(filter);
  return true;
}

async function loadBrightnessBaseline(filter, context) {
  const existing = brightnessByFilter[filter];
  if (existing?.loading) return;

  if (!brightnessByFilter[filter]) {
    brightnessByFilter[filter] = {
      value: NaN,
      hdrEnabled: false,
      unit: 'percent',
      commitTimer: null,
      committing: false,
      loading: true,
      pendingTicks: 0
    };
  } else {
    brightnessByFilter[filter].loading = true;
  }

  try {
    const result = await runBrightness({
      action: 'status',
      nameFilter: filter
    });
    const pendingTicks = brightnessByFilter[filter]?.pendingTicks || 0;
    const state = storeBrightnessFromDisplay(filter, result.display, false);
    if (!state) return;

    state.lastSentValue = state.value;

    if (pendingTicks) {
      applyBrightnessDelta(filter, context, pendingTicks);
    } else {
      paintBrightnessEverywhere(filter, state);
    }
  } catch (error) {
    log.error('loadBrightnessBaseline', error);
    if (brightnessByFilter[filter]) {
      brightnessByFilter[filter].loading = false;
    }
  }
}

function adjustBrightness(context, ticks) {
  const settings = brightnessSettings(context);
  const filter = settings.nameFilter || DEFAULT_FILTER;
  const deltaTicks = Number(ticks) || 0;
  if (!deltaTicks) {
    refreshBrightness(context).catch(() => {});
    return;
  }

  const shared = brightnessByFilter[filter];

  // No baseline yet: queue ticks and load once in background (don't block UI).
  if (!shared || !Number.isFinite(shared.value) || shared.loading) {
    if (!brightnessByFilter[filter]) {
      brightnessByFilter[filter] = {
        value: NaN,
        hdrEnabled: false,
        unit: 'percent',
        commitTimer: null,
        committing: false,
        loading: false,
        pendingTicks: deltaTicks
      };
    } else {
      brightnessByFilter[filter].pendingTicks =
        (brightnessByFilter[filter].pendingTicks || 0) + deltaTicks;
    }
    loadBrightnessBaseline(filter, context).catch((error) =>
      log.error('baseline', error)
    );
    return;
  }

  // Fast path: update counter immediately; send only if value actually changed after clamp.
  applyBrightnessDelta(filter, context, deltaTicks);
}

plugin.hdr = new Actions({
  default: {
    mode: 'toggle',
    nameFilter: DEFAULT_FILTER
  },

  async _willAppear({ context, payload }) {
    rememberController(context, payload);
    // Instant paint from memory/disk cache — avoids flicker on scene switch.
    paintHdrFromCache(context);
    timers[context] && clearInterval(timers[context]);
    timers[context] = setInterval(() => {
      refreshHdr(context).catch(() => {});
    }, 5000);
    // Soft refresh in background (does not clear current image first).
    refreshHdr(context).catch(() => {});
  },

  _willDisappear({ context }) {
    if (timers[context]) {
      clearInterval(timers[context]);
      delete timers[context];
    }
    if (lastVisualByContext[context]) lastVisualByContext[context].stale = true;
    // Keep hdrByFilter cache across scenes.
  },

  async _didReceiveSettings({ context }) {
    paintHdrFromCache(context);
    refreshHdr(context).catch(() => {});
  },

  async _propertyInspectorDidAppear({ context }) {
    try {
      const list = await runHdr({ action: 'list' });
      plugin.sendToPropertyInspector({
        type: 'displayList',
        ok: true,
        displays: list.displays || [],
        settings: hdrSettings(context)
      });
    } catch (error) {
      plugin.sendToPropertyInspector({
        type: 'displayList',
        ok: false,
        error: String(error.message || error),
        settings: hdrSettings(context)
      });
    }
    await refreshHdr(context);
  },

  async keyUp({ context, payload }) {
    const settings = Object.assign(hdrSettings(context), payload?.settings || {});
    plugin.hdr.data[context] = settings;

    const mode = settings.mode || 'toggle';
    const action = mode === 'on' ? 'on' : mode === 'off' ? 'off' : 'toggle';

    try {
      const result = await runHdr({
        action,
        nameFilter: settings.nameFilter || DEFAULT_FILTER
      });

      if (!result.ok) return;

      const enabled = !!result.display?.hdrEnabled;
      rememberHdrState(settings.nameFilter || DEFAULT_FILTER, enabled);
      applyKeyVisual(context, enabled ? 'HDR ON' : 'HDR OFF');
      setContextState(context, enabled ? 1 : 0);
      plugin.sendToPropertyInspector({
        type: 'hdrStatus',
        ok: true,
        display: result.display,
        settings
      });
    } catch (error) {
      log.error('keyUp HDR', error);
    }
  },

  async sendToPlugin({ context, payload }) {
    if (!payload || typeof payload !== 'object') return;

    if (payload.type === 'refresh') {
      await refreshHdr(context);
      return;
    }

    if (payload.type === 'applySettings') {
      const next = Object.assign(hdrSettings(context), {
        mode: payload.mode || 'toggle',
        nameFilter: payload.nameFilter || DEFAULT_FILTER
      });
      plugin.hdr.data[context] = next;
      plugin.setSettings(context, next);
      await refreshHdr(context);
      return;
    }

    if (payload.type === 'run') {
      const settings = hdrSettings(context);
      const action = payload.action || settings.mode || 'toggle';
      try {
        await runHdr({
          action,
          nameFilter: settings.nameFilter || DEFAULT_FILTER
        });
        await refreshHdr(context);
      } catch (error) {
        log.error('sendToPlugin HDR run', error);
      }
    }
  }
});

plugin.brightness = new Actions({
  default: {
    nameFilter: DEFAULT_FILTER,
    stepSdr: 1,
    stepHdr: 10,
    pollSec: 3,
    hdrMin: 80,
    hdrMax: 480
  },

  async _willAppear({ context, payload }) {
    rememberController(context, payload);
    // Instant paint from cache so scene switches don't blank Key/Knob.
    paintBrightnessFromCache(context);
    restartBrightnessPoll(context);
    refreshBrightness(context).catch(() => {});
  },

  _willDisappear({ context }) {
    if (timers[context]) {
      clearInterval(timers[context]);
      delete timers[context];
    }
    if (lastVisualByContext[context]) lastVisualByContext[context].stale = true;
    // Keep brightnessByFilter + disk cache across scene switches.
    // Do NOT delete shared monitor state here.
  },

  async _didReceiveSettings({ context }) {
    plugin.brightness.data[context] = brightnessSettings(context);
    paintBrightnessFromCache(context);
    restartBrightnessPoll(context);
  },

  async _propertyInspectorDidAppear({ context }) {
    try {
      const list = await runBrightness({ action: 'list' });
      plugin.sendToPropertyInspector({
        type: 'displayList',
        ok: true,
        displays: list.displays || [],
        settings: brightnessSettings(context)
      });
    } catch (error) {
      plugin.sendToPropertyInspector({
        type: 'displayList',
        ok: false,
        error: String(error.message || error),
        settings: brightnessSettings(context)
      });
    }
    await refreshBrightness(context);
  },

  keyUp({ context }) {
    refreshBrightness(context).catch(() => {});
  },

  dialRotate({ context, payload }) {
    // Sync UI first; hardware set is debounced in background.
    adjustBrightness(context, payload?.ticks || 0);
  },

  dialDown({ context }) {
    const filter = monitorFilter(context);
    clearBrightnessCommit(filter);
    const state = brightnessByFilter[filter];
    if (state && Number.isFinite(state.value)) {
      commitBrightness(filter).catch(() => {});
    } else {
      refreshBrightness(context).catch(() => {});
    }
  },

  sendToPlugin({ context, payload }) {
    if (!payload || typeof payload !== 'object') return;

    if (payload.type === 'refresh') {
      clearBrightnessCommit(monitorFilter(context));
      refreshBrightness(context).catch(() => {});
      return;
    }

    if (payload.type === 'adjust') {
      adjustBrightness(context, payload.delta || 0);
      return;
    }

    if (payload.type === 'applySettings') {
      plugin.brightness.data[context] = {
        nameFilter: payload.nameFilter || DEFAULT_FILTER,
        stepSdr: payload.stepSdr,
        stepHdr: payload.stepHdr,
        pollSec: payload.pollSec,
        hdrMin: payload.hdrMin,
        hdrMax: payload.hdrMax
      };
      const normalized = brightnessSettings(context);
      plugin.brightness.data[context] = normalized;
      plugin.setSettings(context, normalized);
      restartBrightnessPoll(context);

      // Re-clamp current live value to new HDR bounds if needed.
      const filter = normalized.nameFilter || DEFAULT_FILTER;
      const live = brightnessByFilter[filter];
      if (live && Number.isFinite(live.value)) {
        const clamped = clampBrightnessValue(live.value, normalized, live.hdrEnabled);
        if (!valuesAlmostEqual(live.value, clamped)) {
          live.value = clamped;
          paintBrightnessEverywhere(filter, live);
          scheduleBrightnessCommit(filter);
        }
      }
    }
  }
});

plugin.crosshair = new Actions({
  default: {
    mode: 'toggle',
    style: 1,
    nameFilter: DEFAULT_FILTER
  },

  async _willAppear({ context, payload }) {
    rememberController(context, payload);
    paintCrosshairFromCache(context);
    refreshCrosshair(context).catch(() => {});
  },

  _willDisappear({ context }) {
    if (lastVisualByContext[context]) lastVisualByContext[context].stale = true;
    // Keep crosshairByFilter cache across scenes.
  },

  async _didReceiveSettings({ context }) {
    paintCrosshairFromCache(context);
    refreshCrosshair(context).catch(() => {});
  },

  async _propertyInspectorDidAppear({ context }) {
    plugin.sendToPropertyInspector({
      type: 'crosshairStatus',
      ok: true,
      settings: crosshairSettings(context)
    });
    await refreshCrosshair(context);
  },

  async keyUp({ context, payload }) {
    const settings = Object.assign(crosshairSettings(context), payload?.settings || {});
    plugin.crosshair.data[context] = settings;

    const mode = settings.mode || 'toggle';
    const action = mode === 'on' ? 'on' : mode === 'off' ? 'off' : 'toggle';

    try {
      const result = await runCrosshair({
        action,
        style: settings.style
      });

      if (!result.ok) {
        applyKeyVisual(context, 'AIM ERR');
        return;
      }

      const enabled = !!result.enabled;
      const style =
        Number(result.style) >= 1 && Number(result.style) <= 4
          ? Number(result.style)
          : settings.style;
      rememberCrosshairState(settings.nameFilter || DEFAULT_FILTER, enabled, style);
      applyKeyVisual(context, enabled ? 'AIM ON' : 'AIM OFF');
      setContextState(context, enabled ? 1 : 0);
      plugin.sendToPropertyInspector({
        type: 'crosshairStatus',
        ok: true,
        enabled,
        style,
        settings
      });
    } catch (error) {
      log.error('keyUp crosshair', error);
      applyKeyVisual(context, 'AIM ERR');
    }
  },

  async sendToPlugin({ context, payload }) {
    if (!payload || typeof payload !== 'object') return;

    if (payload.type === 'refresh') {
      await refreshCrosshair(context);
      return;
    }

    if (payload.type === 'applySettings') {
      plugin.crosshair.data[context] = {
        mode: payload.mode || 'toggle',
        style: payload.style,
        nameFilter: payload.nameFilter || DEFAULT_FILTER
      };
      const finalSettings = crosshairSettings(context);
      plugin.crosshair.data[context] = finalSettings;
      plugin.setSettings(context, finalSettings);

      if (payload.applyStyleNow) {
        try {
          const result = await runCrosshair({
            action: 'set',
            style: finalSettings.style
          });
          if (result?.ok) {
            rememberCrosshairState(
              finalSettings.nameFilter || DEFAULT_FILTER,
              !!result.enabled,
              Number(result.style) >= 1 ? Number(result.style) : finalSettings.style
            );
            applyKeyVisual(context, result.enabled ? 'AIM ON' : 'AIM OFF');
            setContextState(context, result.enabled ? 1 : 0);
            plugin.sendToPropertyInspector({
              type: 'crosshairStatus',
              ok: true,
              enabled: !!result.enabled,
              style: finalSettings.style,
              settings: finalSettings
            });
            return;
          }
        } catch (error) {
          log.error('apply crosshair style now', error);
          applyKeyVisual(context, 'AIM ERR');
          return;
        }
      }

      await refreshCrosshair(context);
      return;
    }

    if (payload.type === 'run') {
      const settings = crosshairSettings(context);
      const action = payload.action || settings.mode || 'toggle';
      try {
        await runCrosshair({
          action,
          style: settings.style
        });
        await refreshCrosshair(context);
      } catch (error) {
        log.error('sendToPlugin crosshair run', error);
      }
    }
  }
});

function pictureSettings(context) {
  const raw = Object.assign(
    {
      nameFilter: DEFAULT_FILTER,
      pollSec: 5
    },
    plugin.pictureMode?.data?.[context] || {}
  );
  raw.pollSec = Math.max(1, Math.min(3600, Math.round(Number(raw.pollSec) || 5)));
  raw.nameFilter = raw.nameFilter || DEFAULT_FILTER;
  return raw;
}

function pictureFilter(context) {
  return pictureSettings(context).nameFilter || DEFAULT_FILTER;
}

function applyPictureVisual(context, label) {
  applyKeyVisual(context, label || '—');
}

function normalizePictureModes(modes) {
  if (!Array.isArray(modes) || !modes.length) return null;
  return modes
    .map((m) => ({
      id: Number(m.id),
      name: String(m.name || m.short || m.id),
      short: String(m.short || m.name || m.id)
    }))
    .filter((m) => Number.isFinite(m.id));
}

function ensurePictureState(filter) {
  if (!pictureByFilter[filter]) {
    pictureByFilter[filter] = {
      value: 0,
      short: '…',
      name: '…',
      hdrEnabled: false,
      modes: [],
      commitTimer: null,
      committing: false,
      pendingValue: null,
      holdUntil: 0,
      lastSentValue: null,
      loadingModes: false
    };
  }
  return pictureByFilter[filter];
}

function paintPictureFromCache(context) {
  const filter = pictureFilter(context);
  const state = pictureByFilter[filter];
  if (!state || !Number.isFinite(state.value)) return false;
  applyPictureVisual(context, state.short || state.name || String(state.value));
  return true;
}

function paintPictureEverywhere(filter, state) {
  const data = plugin.pictureMode?.data || {};
  for (const context of Object.keys(data)) {
    if (pictureFilter(context) !== filter) continue;
    applyPictureVisual(context, state.short || state.name || String(state.value));
    plugin.sendToPropertyInspector({
      type: 'pictureModeStatus',
      ok: true,
      value: state.value,
      short: state.short,
      name: state.name,
      hdrEnabled: state.hdrEnabled,
      modes: state.modes,
      pending: state.pendingValue != null || !!state.commitTimer || !!state.committing,
      settings: pictureSettings(context)
    });
  }
}

// Mutate in place — never replace the object (avoids stale refs / lost modes).
function rememberPictureState(filter, result, { keepPending = false } = {}) {
  const state = ensurePictureState(filter);
  const modes = normalizePictureModes(result.modes) || state.modes;

  if (Number.isFinite(Number(result.value))) {
    state.value = Number(result.value);
  }
  state.short = result.short || result.label || state.short || String(state.value);
  state.name = result.name || result.short || state.name || String(state.value);
  state.hdrEnabled = !!result.hdrEnabled;
  if (modes && modes.length) state.modes = modes;

  if (!keepPending) {
    state.commitTimer = null;
    state.committing = false;
    state.pendingValue = null;
  }
  writeStateCacheFile();
  return state;
}

function isPictureBusy(filter) {
  const state = pictureByFilter[filter];
  if (!state) return false;
  // Block status poll only while user is browsing or a set is running.
  return !!(state.committing || state.commitTimer || state.pendingValue != null);
}

async function refreshPictureMode(context) {
  const settings = pictureSettings(context);
  const filter = settings.nameFilter || DEFAULT_FILTER;
  if (isPictureBusy(filter)) {
    paintPictureFromCache(context);
    return null;
  }
  try {
    const result = await runPictureMode({
      action: 'status',
      nameFilter: filter
    });
    if (!result?.ok) throw new Error(result?.error || 'picture status failed');
    if (isPictureBusy(filter)) {
      paintPictureFromCache(context);
      return null;
    }
    const prev = pictureByFilter[filter];
    const nextValue = Number(result.value);
    const nextShort = result.short || result.label || String(result.value);
    const unchanged =
      prev &&
      Number.isFinite(prev.value) &&
      prev.value === nextValue &&
      String(prev.short || '') === String(nextShort) &&
      !!prev.hdrEnabled === !!result.hdrEnabled;

    const state = rememberPictureState(filter, result);
    // Keep lastSentValue across status polls.
    if (unchanged) paintPictureFromCache(context);
    else paintPictureEverywhere(filter, state);
    return result;
  } catch (error) {
    log.error('refreshPictureMode', error);
    if (!paintPictureFromCache(context)) applyPictureVisual(context, 'PIC ERR');
    plugin.sendToPropertyInspector({
      type: 'pictureModeStatus',
      ok: false,
      error: String(error.message || error),
      settings
    });
    return null;
  }
}

function restartPicturePoll(context) {
  if (timers[context]) {
    clearInterval(timers[context]);
    delete timers[context];
  }
  const ms = pictureSettings(context).pollSec * 1000;
  timers[context] = setInterval(() => {
    refreshPictureMode(context).catch(() => {});
  }, ms);
}

function unlockPictureCommit(filter) {
  const state = pictureByFilter[filter];
  if (!state) return;
  state.committing = false;
  state.holdUntil = 0;
  if (state.commitWatchdog) {
    clearTimeout(state.commitWatchdog);
    state.commitWatchdog = null;
  }
}

async function commitPictureMode(filter) {
  const state = ensurePictureState(filter);
  if (state.committing) return;

  const target =
    state.pendingValue != null ? Number(state.pendingValue) : Number(state.value);

  if (state.commitTimer) {
    clearTimeout(state.commitTimer);
    state.commitTimer = null;
  }
  state.pendingValue = null;

  if (!Number.isFinite(target)) return;

  if (state.lastSentValue != null && Number(state.lastSentValue) === target) {
    unlockPictureCommit(filter);
    paintPictureEverywhere(filter, state);
    return;
  }

  state.committing = true;
  // Safety: never leave dial locked if PowerShell hangs.
  state.commitWatchdog = setTimeout(() => {
    log.error('commitPictureMode watchdog — forcing unlock', filter);
    unlockPictureCommit(filter);
  }, 12000);

  try {
    const result = await runPictureMode({
      action: 'set',
      nameFilter: filter,
      value: target
    });
    if (!result?.ok) throw new Error(result?.error || 'picture set failed');

    const live = ensurePictureState(filter);
    const modes = normalizePictureModes(result.modes) || live.modes;
    const match = (modes || []).find((m) => Number(m.id) === target);
    const browsedAway =
      live.pendingValue != null && Number(live.pendingValue) !== target;

    live.lastSentValue = target;
    if (modes && modes.length) live.modes = modes;

    if (!browsedAway) {
      live.value = target;
      live.short = match?.short || result.short || String(target);
      live.name = match?.name || result.name || String(target);
      live.hdrEnabled = !!result.hdrEnabled;
      live.pendingValue = null;
      paintPictureEverywhere(filter, live);
    }
    writeStateCacheFile();
  } catch (error) {
    log.error('commitPictureMode', error);
  } finally {
    const live = ensurePictureState(filter);
    unlockPictureCommit(filter);
    // Apply whatever the user browsed to while set was running.
    if (
      live.pendingValue != null &&
      Number(live.pendingValue) !== Number(live.lastSentValue)
    ) {
      schedulePictureCommit(filter);
    }
  }
}

function schedulePictureCommit(filter) {
  const state = ensurePictureState(filter);
  if (state.commitTimer) clearTimeout(state.commitTimer);
  state.commitTimer = setTimeout(() => {
    state.commitTimer = null;
    commitPictureMode(filter).catch((error) => log.error('picture commit timer', error));
  }, PICTURE_COMMIT_MS);
}

async function ensurePictureModes(filter) {
  const state = ensurePictureState(filter);
  if (normalizePictureModes(state.modes)) return state.modes;
  if (state.loadingModes) return null;

  state.loadingModes = true;
  try {
    const list = await runPictureMode({ action: 'list', nameFilter: filter });
    if (list?.ok) {
      const modes = normalizePictureModes(
        list.hdrEnabled ? list.hdrModes : list.sdrModes
      );
      if (modes) {
        // Always write to the live map entry, not a stale closure ref.
        const live = ensurePictureState(filter);
        live.modes = modes;
        live.hdrEnabled = !!list.hdrEnabled;
        return modes;
      }
    }
  } catch (error) {
    log.error('ensurePictureModes', error);
  } finally {
    ensurePictureState(filter).loadingModes = false;
  }
  return null;
}

async function adjustPictureMode(context, ticks) {
  const filter = pictureFilter(context);
  const delta = Math.sign(Number(ticks) || 0);
  if (!delta) {
    if (!isPictureBusy(filter)) refreshPictureMode(context).catch(() => {});
    return;
  }

  const state = ensurePictureState(filter);
  let modes = normalizePictureModes(state.modes);
  if (!modes) {
    modes = await ensurePictureModes(filter);
    if (!modes) return;
  }

  let idx = modes.findIndex((m) => Number(m.id) === Number(state.value));
  if (idx < 0) idx = 0;
  const nextIdx = ((idx + delta) % modes.length + modes.length) % modes.length;
  const next = modes[nextIdx];
  if (!next) return;

  // Preview always moves. Hardware waits for idle pause.
  state.value = Number(next.id);
  state.short = next.short || next.name || String(next.id);
  state.name = next.name || state.short;
  state.pendingValue = Number(next.id);
  applyPictureVisual(context, state.short);
  paintPictureEverywhere(filter, state);

  // Queue another set after the in-flight one; don't block the dial face.
  if (!state.committing) schedulePictureCommit(filter);
}

plugin.pictureMode = new Actions({
  default: {
    nameFilter: DEFAULT_FILTER,
    pollSec: 5
  },

  async _willAppear({ context, payload }) {
    rememberController(context, payload);
    paintPictureFromCache(context);
    restartPicturePoll(context);

    const filter = pictureFilter(context);
    ensurePictureState(filter);
    await ensurePictureModes(filter);
    refreshPictureMode(context).catch(() => {});
  },

  _willDisappear({ context }) {
    if (timers[context]) {
      clearInterval(timers[context]);
      delete timers[context];
    }
    if (lastVisualByContext[context]) lastVisualByContext[context].stale = true;
  },

  async _didReceiveSettings({ context }) {
    plugin.pictureMode.data[context] = pictureSettings(context);
    paintPictureFromCache(context);
    restartPicturePoll(context);
  },

  async _propertyInspectorDidAppear({ context }) {
    plugin.sendToPropertyInspector({
      type: 'pictureModeStatus',
      ok: true,
      settings: pictureSettings(context)
    });
    await refreshPictureMode(context);
  },

  keyUp({ context }) {
    refreshPictureMode(context).catch(() => {});
  },

  dialRotate({ context, payload }) {
    adjustPictureMode(context, payload?.ticks || 0).catch((error) =>
      log.error('dialRotate picture', error)
    );
  },

  dialDown({ context }) {
    const filter = pictureFilter(context);
    const state = pictureByFilter[filter];
    if (state?.committing) return;
    if (state?.pendingValue != null || state?.commitTimer) {
      if (state.commitTimer) {
        clearTimeout(state.commitTimer);
        state.commitTimer = null;
      }
      commitPictureMode(filter).catch(() => {});
      return;
    }
    refreshPictureMode(context).catch(() => {});
  },

  sendToPlugin({ context, payload }) {
    if (!payload || typeof payload !== 'object') return;

    if (payload.type === 'refresh') {
      refreshPictureMode(context).catch(() => {});
      return;
    }

    if (payload.type === 'delta') {
      adjustPictureMode(context, payload.delta || 0).catch(() => {});
      return;
    }

    if (payload.type === 'applySettings') {
      plugin.pictureMode.data[context] = {
        nameFilter: payload.nameFilter || DEFAULT_FILTER,
        pollSec: payload.pollSec
      };
      const normalized = pictureSettings(context);
      plugin.pictureMode.data[context] = normalized;
      plugin.setSettings(context, normalized);
      restartPicturePoll(context);
      refreshPictureMode(context).catch(() => {});
    }
  }
});

function refreshRateSettings(context) {
  const raw = Object.assign(
    {
      nameFilter: DEFAULT_FILTER,
      pollSec: REFRESH_RATE_POLL_DEFAULT
    },
    plugin.refreshRate?.data?.[context] || {}
  );
  // Poll interval is user-configurable (seconds). Floor at 5s so it stays light.
  raw.pollSec = Math.max(5, Math.min(3600, Math.round(Number(raw.pollSec) || REFRESH_RATE_POLL_DEFAULT)));
  raw.nameFilter = raw.nameFilter || DEFAULT_FILTER;
  return raw;
}

function refreshRateFilter(context) {
  return refreshRateSettings(context).nameFilter || DEFAULT_FILTER;
}

function rememberRefreshRate(filter, display) {
  const hzRounded = Number(display?.hzRounded);
  const hz = Number(display?.hz);
  if (!Number.isFinite(hzRounded) || hzRounded <= 0) return null;
  refreshRateByFilter[filter] = {
    hz: Number.isFinite(hz) ? hz : hzRounded,
    hzRounded,
    label: display.label || `${hzRounded}Hz`,
    width: Number(display.width) || 0,
    height: Number(display.height) || 0,
    name: display.name || filter
  };
  writeStateCacheFile();
  return refreshRateByFilter[filter];
}

function paintRefreshRateFromCache(context) {
  const filter = refreshRateFilter(context);
  const state = refreshRateByFilter[filter];
  if (!state || !Number.isFinite(state.hzRounded)) return false;
  applyKeyVisual(context, state.label || `${state.hzRounded}Hz`);
  return true;
}

function paintRefreshRateEverywhere(filter, state) {
  const data = plugin.refreshRate?.data || {};
  for (const context of Object.keys(data)) {
    if (refreshRateFilter(context) !== filter) continue;
    applyKeyVisual(context, state.label || `${state.hzRounded}Hz`);
    plugin.sendToPropertyInspector({
      type: 'refreshRateStatus',
      ok: true,
      display: {
        name: state.name || filter,
        hz: state.hz,
        hzRounded: state.hzRounded,
        label: state.label,
        width: state.width,
        height: state.height
      },
      settings: refreshRateSettings(context)
    });
  }
}

function restartRefreshRatePoll(context) {
  if (timers[context]) {
    clearInterval(timers[context]);
    delete timers[context];
  }
  const ms = refreshRateSettings(context).pollSec * 1000;
  timers[context] = setInterval(() => {
    refreshRefreshRate(context).catch(() => {});
  }, ms);
}

async function refreshRefreshRate(context) {
  const settings = refreshRateSettings(context);
  const filter = settings.nameFilter || DEFAULT_FILTER;
  try {
    const result = await runRefreshRate({
      action: 'status',
      nameFilter: filter
    });
    if (!result?.ok) throw new Error(result?.error || 'refresh rate status failed');
    const prev = refreshRateByFilter[filter];
    const state = rememberRefreshRate(filter, result.display);
    if (!state) throw new Error('invalid refresh rate');
    const unchanged =
      prev &&
      prev.hzRounded === state.hzRounded &&
      String(prev.label || '') === String(state.label || '');
    if (unchanged) paintRefreshRateFromCache(context);
    else paintRefreshRateEverywhere(filter, state);
    return result.display;
  } catch (error) {
    log.error('refreshRefreshRate', error);
    if (!paintRefreshRateFromCache(context)) applyKeyVisual(context, 'Hz ERR');
    plugin.sendToPropertyInspector({
      type: 'refreshRateStatus',
      ok: false,
      error: String(error.message || error),
      settings
    });
    return null;
  }
}

plugin.refreshRate = new Actions({
  default: {
    nameFilter: DEFAULT_FILTER,
    pollSec: REFRESH_RATE_POLL_DEFAULT
  },

  async _willAppear({ context, payload }) {
    rememberController(context, payload);
    paintRefreshRateFromCache(context);
    restartRefreshRatePoll(context);
    refreshRefreshRate(context).catch(() => {});
  },

  _willDisappear({ context }) {
    if (timers[context]) {
      clearInterval(timers[context]);
      delete timers[context];
    }
    if (lastVisualByContext[context]) lastVisualByContext[context].stale = true;
  },

  async _didReceiveSettings({ context }) {
    plugin.refreshRate.data[context] = refreshRateSettings(context);
    paintRefreshRateFromCache(context);
    restartRefreshRatePoll(context);
  },

  async _propertyInspectorDidAppear({ context }) {
    try {
      const list = await runRefreshRate({ action: 'list' });
      plugin.sendToPropertyInspector({
        type: 'displayList',
        ok: true,
        displays: list.displays || [],
        settings: refreshRateSettings(context)
      });
    } catch (error) {
      plugin.sendToPropertyInspector({
        type: 'displayList',
        ok: false,
        error: String(error.message || error),
        settings: refreshRateSettings(context)
      });
    }
    await refreshRefreshRate(context);
  },

  keyUp({ context }) {
    // Manual refresh on press — no need for frequent polling.
    refreshRefreshRate(context).catch(() => {});
  },

  sendToPlugin({ context, payload }) {
    if (!payload || typeof payload !== 'object') return;

    if (payload.type === 'refresh') {
      refreshRefreshRate(context).catch(() => {});
      return;
    }

    if (payload.type === 'applySettings') {
      plugin.refreshRate.data[context] = {
        nameFilter: payload.nameFilter || DEFAULT_FILTER,
        pollSec: payload.pollSec
      };
      const normalized = refreshRateSettings(context);
      plugin.refreshRate.data[context] = normalized;
      plugin.setSettings(context, normalized);
      paintRefreshRateFromCache(context);
      restartRefreshRatePoll(context);
      refreshRefreshRate(context).catch(() => {});
    }
  }
});
