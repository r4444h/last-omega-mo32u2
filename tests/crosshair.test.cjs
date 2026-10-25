const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const pluginDir = path.resolve(__dirname, '../com.mirabox.streamdock.lastomega.sdPlugin/plugin');
const source = fs.readFileSync(path.join(pluginDir, 'index.js'), 'utf8');

function loadPlugin(execFile) {
  const messages = [];
  class Plugins {
    setTitle(context, title) { messages.push({ type: 'title', context, title }); }
    setImage(context, image) { messages.push({ type: 'image', context, image }); }
    setState(context, state) { messages.push({ type: 'state', context, state }); }
    sendToPropertyInspector(payload) { messages.push({ type: 'inspector', payload }); }
  }
  class Actions {
    constructor(options) { this.data = {}; Object.assign(this, options); }
  }
  const context = vm.createContext({
    __dirname: pluginDir,
    require(name) {
      if (name === 'child_process') return { execFile };
      if (name === 'fs') return { readFileSync: () => '{}', writeFileSync: () => {} };
      if (name === 'path') return path;
      if (name === './utils/plugin') return { Plugins, Actions, log: { error() {} } };
      throw new Error(`Unexpected dependency: ${name}`);
    },
    setTimeout, clearTimeout, setInterval, clearInterval
  });
  vm.runInContext(`${source}\nglobalThis.aim = { runCrosshair, refreshCrosshair, plugin };`, context);
  return { ...context.aim, messages };
}

test('AIM button accepts a verified DDC result with no USB HID and displays both states', async () => {
  let enabled = false;
  const calls = [];
  const { plugin, messages } = loadPlugin((exe, args, options, callback) => {
    calls.push({ exe, args });
    enabled = !enabled;
    callback(null, JSON.stringify({ ok: true, enabled, style: enabled ? 1 : 0, devices: 0, method: 'ddc-ef' }), '');
  });
  const event = { context: 'aim-key', payload: { settings: { mode: 'toggle', style: 1 } } };
  await plugin.crosshair.keyUp(event);
  await plugin.crosshair.keyUp(event);
  assert.deepEqual(messages.filter(m => m.type === 'state').map(m => m.state), [1, 0]);
  const images = messages.filter(m => m.type === 'image').map(m => decodeURIComponent(m.image));
  assert.ok(images[0].includes('AIM ON'));
  assert.ok(images[1].includes('AIM OFF'));
  assert.equal(calls.length, 2);
  assert.equal(calls[0].args[calls[0].args.indexOf('-Action') + 1], 'toggle');
});

test('overlapping AIM commands execute in order and the queue recovers after a failure', async () => {
  const pending = [];
  const { runCrosshair } = loadPlugin((exe, args, options, callback) => pending.push(callback));
  const first = runCrosshair({ action: 'toggle', style: 1 });
  const failure = assert.rejects(first, /DDC unavailable/);
  const second = runCrosshair({ action: 'toggle', style: 1 });
  await new Promise(setImmediate);
  assert.equal(pending.length, 1);
  pending[0](new Error('process failed'), '{"ok":false,"error":"DDC unavailable"}', '');
  await failure;
  await new Promise(setImmediate);
  assert.equal(pending.length, 2);
  pending[1](null, '{"ok":true,"enabled":true,"style":1}', '');
  assert.equal((await second).enabled, true);
});

test('PowerShell JSON error reaches the AIM inspector and no successful state is painted', async () => {
  const { plugin, messages } = loadPlugin((exe, args, options, callback) => {
    callback(new Error('exit code 1'), '{"ok":false,"error":"MO32U2 DDC display not found"}', '');
  });
  await plugin.crosshair.keyUp({ context: 'aim-key', payload: {} });
  const failure = messages.find(m => m.type === 'inspector').payload;
  assert.equal(failure.ok, false);
  assert.equal(failure.error, 'MO32U2 DDC display not found');
  assert.equal(messages.filter(m => m.type === 'state').length, 0);
  assert.ok(decodeURIComponent(messages.find(m => m.type === 'image').image).includes('AIM ERR'));
});

test('an unsuccessful JSON status is rejected even if the helper exits with code zero', async () => {
  const { runCrosshair } = loadPlugin((exe, args, options, callback) => {
    callback(null, '{"ok":false,"error":"AIM read failed"}', '');
  });
  await assert.rejects(runCrosshair({ action: 'status' }), /AIM read failed/);
});

test('refresh uses the monitor state and exposes the lack of USB without showing an error', async () => {
  const { refreshCrosshair, messages } = loadPlugin((exe, args, options, callback) => {
    callback(null, '{"ok":true,"enabled":true,"style":3,"devices":0,"source":"monitor"}', '');
  });
  const result = await refreshCrosshair('aim-key');
  assert.equal(result.style, 3);
  assert.equal(result.source, 'monitor');
  const status = messages.find(m => m.type === 'inspector').payload;
  assert.equal(status.ok, true);
  assert.equal(status.enabled, true);
  assert.equal(status.devices, 0);
});
