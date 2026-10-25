const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const workerBridge = require('./worker-bridge.cjs');
const pluginDir = path.resolve(__dirname, '../com.mirabox.streamdock.lastomega.sdPlugin/plugin');
const source = fs.readFileSync(path.join(pluginDir, 'index.js'), 'utf8');
const tick = () => new Promise(setImmediate);

function fixture(t, { hdr = false, cache = {}, intercept } = {}) {
  const messages = [], calls = [], writes = [], cacheWrites = [], timers = new Set();
  const hardware = { hdr, sdr: 70, hdrBrightness: 10, pictureSdr: 0, pictureHdr: 0 };
  class Plugins {
    setTitle(context, title) { messages.push({ type: 'title', context, title }); }
    setImage(context, image) { messages.push({ type: 'image', context, image: decodeURIComponent(image) }); }
    setState(context, state) { messages.push({ type: 'state', context, state }); }
    setSettings(context, settings) { messages.push({ type: 'settings', context, settings }); }
    sendToPropertyInspector(payload) { messages.push({ type: 'inspector', payload }); }
  }
  class Actions { constructor(options) { this.data = {}; Object.assign(this, options); } }
  const sandbox = vm.createContext({
    __dirname: pluginDir,
    require: function fixtureRequire(name) {
      if (name === 'path') return path;
      if (name === 'fs') return { readFileSync: () => JSON.stringify(cache),
        writeFileSync(file, value) { cacheWrites.push({ type: 'write', file, value }); },
        renameSync(from, to) { cacheWrites.push({ type: 'rename', from, to }); } };
      if (name === './utils/plugin') return { Plugins, Actions, log: { error() {} } };
      if (name === './utils/monitor-worker') return { MonitorWorker: workerBridge(fixtureRequire('child_process').execFile) };
      if (name === './utils/shared-polling') return require('../com.mirabox.streamdock.lastomega.sdPlugin/plugin/utils/shared-polling');
      if (name === 'child_process') return { execFile(exe, args, options, callback) {
        const script = path.basename(args[args.indexOf('-File') + 1]);
        const action = args[args.indexOf('-Action') + 1];
        const call = { script, action, args, callback };
        calls.push(call);
        const execute = () => {
          if (script === 'PictureModeControl.ps1') {
            if (action === 'set') {
              const value = Number(args[args.indexOf('-Value') + 1]);
              hardware[hardware.hdr ? 'pictureHdr' : 'pictureSdr'] = value;
              hardware[hardware.hdr ? 'hdrBrightness' : 'sdr'] = hardware.hdr ? 35 : 25;
            }
            const modes = [{ id: 0, short: 'STD', name: 'Standard' }, { id: 1, short: 'GAME', name: 'Gaming' }];
            const value = hardware[hardware.hdr ? 'pictureHdr' : 'pictureSdr'];
            callback(null, JSON.stringify({ ok: true, hdrEnabled: hardware.hdr, value, modes,
              short: modes[value].short, name: modes[value].name, hdrModes: modes, sdrModes: modes }), '');
            return;
          }
          if (script === 'HdrControl.ps1' && action !== 'status') {
            hardware.hdr = action === 'on' ? true : action === 'off' ? false : !hardware.hdr;
          }
          if (script === 'BrightnessControl.ps1' && action === 'set') {
            const value = Number(args[args.indexOf('-Value') + 1]);
            const expected = args[args.indexOf('-ExpectedHdr') + 1];
            assert.equal(expected, hardware.hdr ? 'on' : 'off');
            writes.push({ value, hdr: hardware.hdr });
            hardware[hardware.hdr ? 'hdrBrightness' : 'sdr'] = value;
          }
          const brightnessPercent = hardware.hdr ? hardware.hdrBrightness : hardware.sdr;
          callback(null, JSON.stringify({ ok: true, display: {
            name: 'MO32U2', hdrEnabled: hardware.hdr, brightnessPercent,
            sdrWhiteNits: 210, unit: 'percent', value: brightnessPercent
          } }), '');
        };
        if (!intercept?.(call, execute)) queueMicrotask(execute);
      } };
      throw new Error(`Unexpected dependency: ${name}`);
    },
    setTimeout(fn, ms) { const id = setTimeout(() => { timers.delete(id); fn(); }, ms); timers.add(id); return id; },
    clearTimeout(id) { timers.delete(id); clearTimeout(id); },
    setInterval() { return 1; }, clearInterval() {}
  });
  vm.runInContext(`${source}\nglobalThis.api = { plugin, refreshBrightness, refreshHdr, brightnessSettings,
    brightnessByFilter, hdrByFilter, controllerByContext, adjustBrightness, commitBrightness,
    paintBrightnessFromCache, flushStateCacheFile, ensurePictureState,
    adjustPictureMode, commitPictureMode, refreshPictureMode };`, sandbox);
  const api = sandbox.api;
  const settings = { nameFilter: 'MO32U2', stepSdr: 1, stepHdr: 1, pollSec: 3, controlVersion: 2 };
  api.plugin.brightness.data.key = { ...settings };
  api.plugin.brightness.data.knob = { ...settings };
  api.plugin.hdr.data.hdr = { nameFilter: 'MO32U2', mode: 'toggle' };
  api.plugin.pictureMode.data.picture = { nameFilter: 'MO32U2', pollSec: 30, performanceVersion: 1 };
  api.controllerByContext.knob = 'Knob';
  api.controllerByContext.picture = 'Knob';
  t.after(() => { for (const id of timers) clearTimeout(id); });
  return { ...api, messages, calls, writes, cacheWrites, hardware };
}

for (const hdr of [false, true]) {
  test(`applying a picture profile immediately refreshes both brightness faces in ${hdr ? 'HDR' : 'SDR'}`, async t => {
    const f = fixture(t, { hdr });
    await f.refreshBrightness('key');
    const state = f.ensurePictureState('MO32U2');
    state.pendingValue = 1;
    await f.commitPictureMode('MO32U2');
    const expected = hdr ? 35 : 25;
    const label = `${hdr ? 'HDR' : 'SDR'} ${expected}%`;
    assert.equal(f.brightnessByFilter.MO32U2.value, expected);
    assert.equal(f.brightnessByFilter.MO32U2.lastSentValue, expected);
    assert.equal(f.messages.filter(m => m.type === 'title' && m.context === 'knob').at(-1).title, label);
    assert.ok(f.messages.filter(m => m.type === 'image' && m.context === 'key').at(-1).image.includes(`${expected}%`));
    assert.equal(f.calls.filter(c => c.script === 'BrightnessControl.ps1' && c.action === 'status').length, 2);
    assert.equal(f.writes.length, 0, 'reading the profile must not write an old brightness back');
  });
}

test('profile previews do not read brightness until a profile is applied', async t => {
  const f = fixture(t);
  await f.refreshBrightness('key');
  await f.refreshPictureMode('picture');
  await f.adjustPictureMode('picture', 1);
  assert.equal(f.calls.filter(c => c.script === 'BrightnessControl.ps1').length, 1);
  assert.equal(f.calls.filter(c => c.script === 'PictureModeControl.ps1' && c.action === 'set').length, 0);
});

test('HDR switching reloads the active profile and does not skip the same numeric profile in SDR', async t => {
  const f = fixture(t, { hdr: true });
  await f.refreshBrightness('key');
  await f.refreshPictureMode('picture');
  f.ensurePictureState('MO32U2').pendingValue = 1;
  await f.commitPictureMode('MO32U2');
  assert.equal(f.ensurePictureState('MO32U2').lastSentValue, 1);
  await f.plugin.brightness.dialDown({ context: 'knob' });
  assert.equal(f.ensurePictureState('MO32U2').hdrEnabled, false);
  assert.equal(f.ensurePictureState('MO32U2').value, 0);
  f.ensurePictureState('MO32U2').pendingValue = 1;
  await f.commitPictureMode('MO32U2');
  assert.equal(f.hardware.pictureSdr, 1);
  assert.equal(f.brightnessByFilter.MO32U2.value, 25);
  assert.equal(f.calls.filter(c => c.script === 'PictureModeControl.ps1' && c.action === 'set').length, 2);
});

test('a picture change cancels old pending brightness and applies new dial ticks to the profile baseline', async t => {
  let release;
  const f = fixture(t, { intercept(call, execute) {
    if (call.script === 'PictureModeControl.ps1' && call.action === 'set') { release = execute; return true; }
  } });
  await f.refreshBrightness('key');
  f.adjustBrightness('knob', 1); // An old-profile 71% write is still pending.
  f.ensurePictureState('MO32U2').pendingValue = 1;
  const change = f.commitPictureMode('MO32U2');
  await tick();
  f.adjustBrightness('knob', 1);
  release();
  await change;
  assert.equal(f.brightnessByFilter.MO32U2.value, 26);
  await f.commitBrightness('MO32U2');
  assert.deepEqual(f.writes, [{ value: 26, hdr: false }]);
});

test('failed picture changes recover brightness and release the transition', async t => {
  const f = fixture(t, { intercept(call) {
    if (call.script === 'PictureModeControl.ps1' && call.action === 'set') {
      queueMicrotask(() => call.callback(null, '{"ok":false,"error":"profile unavailable"}', ''));
      return true;
    }
  } });
  await f.refreshBrightness('key');
  f.ensurePictureState('MO32U2').pendingValue = 1;
  await f.commitPictureMode('MO32U2');
  assert.equal(f.brightnessByFilter.MO32U2.value, 70);
  assert.equal(f.brightnessByFilter.MO32U2.loading, false);
  assert.equal(f.ensurePictureState('MO32U2').committing, false);
  f.adjustBrightness('knob', 1);
  assert.equal(f.brightnessByFilter.MO32U2.value, 71);
});

test('unchanged monitor polls do not rewrite the UI cache and changed state is published atomically', async t => {
  const f = fixture(t);
  await f.refreshBrightness('key');
  f.flushStateCacheFile();
  assert.equal(f.cacheWrites.length, 2);
  assert.equal(f.cacheWrites[0].type, 'write');
  assert.ok(f.cacheWrites[0].file.endsWith('.json.tmp'));
  assert.equal(f.cacheWrites[1].type, 'rename');
  assert.ok(f.cacheWrites[1].to.endsWith('ui-state-cache.json'));
  await f.refreshBrightness('key');
  f.flushStateCacheFile();
  assert.equal(f.cacheWrites.length, 2);
  f.hardware.sdr = 71;
  await f.refreshBrightness('key');
  f.flushStateCacheFile();
  assert.equal(f.cacheWrites.length, 4);
});

test('legacy nits cache and HDR bounds are not reused as monitor percentages', async t => {
  const f = fixture(t, { hdr: true, cache: { brightness: { MO32U2: {
    value: 210, hdrEnabled: true, unit: 'nits', lastSentValue: 10
  } } } });
  assert.equal(f.brightnessByFilter.MO32U2, undefined);
  f.plugin.brightness.data.key = { stepHdr: 10, hdrMin: 80, hdrMax: 480 };
  const settings = f.brightnessSettings('key');
  assert.equal(settings.stepHdr, 1);
  assert.equal(settings.controlVersion, 2);
  assert.equal(settings.hdrMin, undefined);
  await f.refreshBrightness('key');
  assert.equal(f.brightnessByFilter.MO32U2.value, 10);
  assert.equal(f.messages.filter(m => m.type === 'title' && m.context === 'knob').at(-1).title, 'HDR 10%');
  assert.equal(f.writes.length, 0);
});

test('HDR button immediately refreshes the neighboring key and knob in both directions', async t => {
  const f = fixture(t);
  await f.refreshBrightness('key');
  await f.plugin.hdr.keyUp({ context: 'hdr', payload: {} });
  assert.equal(f.brightnessByFilter.MO32U2.value, 10);
  assert.equal(f.messages.filter(m => m.type === 'title' && m.context === 'knob').at(-1).title, 'HDR 10%');
  const keyImage = f.messages.filter(m => m.type === 'image' && m.context === 'key').at(-1).image;
  assert.ok(keyImage.includes('>HDR</text>'));
  assert.ok(keyImage.includes('>10%</text>'));
  await f.plugin.hdr.keyUp({ context: 'hdr', payload: {} });
  assert.equal(f.messages.filter(m => m.type === 'title' && m.context === 'knob').at(-1).title, 'SDR 70%');
  assert.equal(f.writes.length, 0);
});

test('HDR change cancels the old pending value and applies queued turns to the new baseline', async t => {
  let releaseHdr;
  const f = fixture(t, { intercept(call, execute) {
    if (call.script === 'HdrControl.ps1' && call.action === 'toggle') { releaseHdr = execute; return true; }
  } });
  await f.refreshBrightness('key');
  f.adjustBrightness('knob', 1); // Pending SDR 71% must not become HDR 71%.
  const change = f.plugin.hdr.keyUp({ context: 'hdr', payload: {} });
  await tick();
  f.adjustBrightness('knob', 2);
  releaseHdr();
  await change;
  assert.equal(f.writes.length, 0);
  assert.equal(f.brightnessByFilter.MO32U2.value, 12);
  await f.commitBrightness('MO32U2');
  assert.deepEqual(f.writes, [{ value: 12, hdr: true }]);
});

test('a brightness read started before HDR changes cannot overwrite the new mode', async t => {
  let releaseRead, interceptRead = false;
  const f = fixture(t, { intercept(call) {
    if (interceptRead && call.script === 'BrightnessControl.ps1' && call.action === 'status') {
      interceptRead = false;
      releaseRead = () => call.callback(null, '{"ok":true,"display":{"hdrEnabled":false,"brightnessPercent":70}}', '');
      return true;
    }
  } });
  await f.refreshBrightness('key');
  interceptRead = true;
  const oldRead = f.refreshBrightness('key');
  await tick();
  const change = f.plugin.hdr.keyUp({ context: 'hdr', payload: {} });
  releaseRead();
  await Promise.all([oldRead, change]);
  assert.equal(f.brightnessByFilter.MO32U2.hdrEnabled, true);
  assert.equal(f.brightnessByFilter.MO32U2.value, 10);
});

test('HDR changes outside the plugin also refresh the neighboring brightness control', async t => {
  const f = fixture(t);
  await f.refreshBrightness('key');
  f.hdrByFilter.MO32U2 = { enabled: false, label: 'HDR OFF' };
  f.hardware.hdr = true;
  await f.refreshHdr('hdr');
  assert.equal(f.messages.filter(m => m.type === 'title' && m.context === 'knob').at(-1).title, 'HDR 10%');
});

test('missing hardware brightness is reported as unavailable instead of using Windows nits', async t => {
  const f = fixture(t, { hdr: true, intercept(call) {
    if (call.script === 'BrightnessControl.ps1') {
      queueMicrotask(() => call.callback(null, '{"ok":true,"display":{"hdrEnabled":true,"brightnessPercent":null,"sdrWhiteNits":210}}', ''));
      return true;
    }
  } });
  await f.refreshBrightness('key');
  assert.equal(f.brightnessByFilter.MO32U2, undefined);
  assert.ok(f.messages.some(m => m.type === 'inspector' && m.payload.ok === false));
  assert.equal(f.writes.length, 0);
});

test('two quick HDR presses leave brightness synchronized with the final mode', async t => {
  const f = fixture(t);
  await f.refreshBrightness('key');
  await Promise.all([
    f.plugin.hdr.keyUp({ context: 'hdr', payload: {} }),
    f.plugin.hdr.keyUp({ context: 'hdr', payload: {} })
  ]);
  assert.equal(f.hardware.hdr, false);
  assert.equal(f.brightnessByFilter.MO32U2.hdrEnabled, false);
  assert.equal(f.messages.filter(m => m.type === 'title' && m.context === 'knob').at(-1).title, 'SDR 70%');
});

test('a failed first brightness read unlocks the baseline for the next attempt', async t => {
  let fail = true;
  const f = fixture(t, { intercept(call) {
    if (fail && call.script === 'BrightnessControl.ps1') {
      fail = false;
      queueMicrotask(() => call.callback(null, '{"ok":false,"error":"DDC temporarily unavailable"}', ''));
      return true;
    }
  } });
  f.adjustBrightness('knob', 1);
  await tick();
  assert.equal(f.brightnessByFilter.MO32U2.loading, false);
  f.adjustBrightness('knob', 1);
  await tick();
  assert.equal(f.brightnessByFilter.MO32U2.loading, false);
  assert.ok(Number.isFinite(f.brightnessByFilter.MO32U2.value));
});

test('pressing the brightness knob toggles HDR while rotation changes only brightness', async t => {
  const f = fixture(t);
  await f.refreshBrightness('key');
  await f.plugin.brightness.dialDown({ context: 'knob' });
  assert.equal(f.hardware.hdr, true);
  assert.equal(f.brightnessByFilter.MO32U2.value, 10);
  f.plugin.brightness.dialRotate({ context: 'knob', payload: { ticks: 1 } });
  await f.commitBrightness('MO32U2');
  assert.equal(f.hardware.hdr, true);
  assert.deepEqual(f.writes, [{ value: 11, hdr: true }]);
  await f.plugin.brightness.keyUp({ context: 'key' });
  assert.equal(f.hardware.hdr, false);
});
