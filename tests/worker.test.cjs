const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const { MonitorWorker } = require('../com.mirabox.streamdock.lastomega.sdPlugin/plugin/utils/monitor-worker');
const { SharedPolling } = require('../com.mirabox.streamdock.lastomega.sdPlugin/plugin/utils/shared-polling');
const tick = () => new Promise(setImmediate);

test('a missing helper reports an install error without starting a process', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'lastomega-missing-worker-'));
  t.after(() => fs.rmdirSync(directory));
  let spawns = 0;
  const worker = new MonitorWorker({ directory, spawnProcess() { spawns++; } });
  t.after(() => worker.close());
  await assert.rejects(worker.request('hdr'), /MonitorControl.ps1 missing/);
  assert.equal(spawns, 0);
});

function client(t, options = {}) {
  const children = [], sent = [];
  const worker = new MonitorWorker({ ensureScript: async () => {}, ...options, spawnProcess(executable, args) {
    assert.equal(executable, 'powershell.exe');
    assert.equal(args[args.indexOf('-ExecutionPolicy') + 1], 'RemoteSigned');
    assert.equal(args.includes('Bypass'), false);
    assert.ok(args.at(-1).endsWith('MonitorControl.ps1'));
    const child = new EventEmitter();
    child.stdout = new EventEmitter(); child.stdout.setEncoding = () => {};
    child.stderr = new EventEmitter(); child.stdin = new EventEmitter();
    child.stdin.write = text => sent.push({ child, request: JSON.parse(text) });
    child.stdin.destroy = () => {};
    child.kill = () => { child.killed = true; };
    children.push(child);
    return child;
  } });
  t.after(() => worker.close());
  const answer = (index, result = { ok: true }) => {
    const { child, request } = sent[index];
    child.stdout.emit('data', JSON.stringify({ id: request.id, result }) + '\n');
  };
  return { worker, children, sent, answer };
}

test('duplicate status requests share one native read and one persistent process', async t => {
  const f = client(t);
  const first = f.worker.request('brightness', { action: 'status' });
  const duplicate = f.worker.request('brightness', { action: 'status' });
  assert.equal(first, duplicate);
  await tick();
  assert.equal(f.sent.length, 1);
  f.answer(0, { ok: true, value: 30 });
  assert.equal((await first).value, 30);
  const next = f.worker.request('hdr', { action: 'status' });
  await tick(); f.answer(1); await next;
  assert.equal(f.children.length, 1);
});

test('interactive changes pass queued background reads without parallel native calls', async t => {
  const f = client(t);
  const first = f.worker.request('brightness', { action: 'status' });
  const background = f.worker.request('hdr', { action: 'status' });
  const press = f.worker.request('hdr', { action: 'toggle' });
  await tick(); assert.equal(f.sent.length, 1);
  f.answer(0); await first; await tick();
  assert.equal(f.sent[1].request.action, 'toggle');
  f.answer(1); await press; await tick();
  assert.equal(f.sent[2].request.action, 'status');
  f.answer(2); await background;
});

test('fragmented JSON and unsolicited display events do not lose command replies', async t => {
  const events = [];
  const f = client(t, { onEvent: event => events.push(event) });
  const pending = f.worker.request('hdr'); await tick();
  const response = JSON.stringify({ id: f.sent[0].request.id, result: { ok: true, value: 1 } }) + '\n';
  f.children[0].stdout.emit('data', '{"event":"displayChanged"}\n' + response.slice(0, 7));
  f.children[0].stdout.emit('data', response.slice(7));
  assert.equal((await pending).value, 1);
  assert.deepEqual(events, ['displayChanged']);
});

test('worker exit rejects queued work and the next request starts one clean replacement', async t => {
  const f = client(t);
  const first = f.worker.request('brightness');
  const second = f.worker.request('hdr');
  const rejected = Promise.all([assert.rejects(first, /exited/), assert.rejects(second, /exited/)]);
  await tick(); f.children[0].emit('exit', 1); await rejected;
  const next = f.worker.request('hdr'); await tick();
  assert.equal(f.children.length, 2);
  f.answer(1); await next;
});

test('HDR changes reconnect the driver before queued brightness reads without losing work', async t => {
  const f = client(t);
  const change = f.worker.request('hdr', { action: 'toggle' });
  const brightness = f.worker.request('brightness');
  await tick();
  f.answer(0); await change; await tick();
  assert.equal(f.children[0].killed, true);
  assert.equal(f.children.length, 2);
  assert.equal(f.sent[1].request.kind, 'brightness');
  f.answer(1); await brightness;
});

test('an external display event reconnects only after the in-flight reply', async t => {
  const f = client(t);
  const first = f.worker.request('brightness');
  const next = f.worker.request('hdr');
  await tick();
  f.children[0].stdout.emit('data', '{"event":"displayChanged"}\n');
  assert.equal(f.children[0].killed, undefined);
  f.answer(0); await first; await tick();
  assert.equal(f.children[0].killed, true);
  assert.equal(f.children.length, 2);
  f.answer(1); await next;
});

test('a hung native call times out without leaving the queue stuck', async t => {
  const f = client(t, { timeout: 20 });
  await assert.rejects(f.worker.request('brightness'), /timed out/);
  assert.equal(f.children[0].killed, true);
  const next = f.worker.request('hdr'); await tick(); f.answer(1); await next;
});

function clock() {
  const active = new Set();
  return { active, setTimer(fn, delay) { const timer = { fn, delay }; active.add(timer); return timer; },
    clearTimer(timer) { active.delete(timer); }, async fire() {
      const timer = active.values().next().value;
      assert.ok(timer); active.delete(timer); await timer.fn();
    } };
}

test('two visible controls share one poll and removing the last control stops it', async () => {
  const time = clock(); const scheduler = new SharedPolling(time); let calls = 0;
  scheduler.subscribe('brightness:MO32U2', 'key', 15000, async () => { calls++; return {}; });
  scheduler.subscribe('brightness:MO32U2', 'knob', 15000, async () => { calls++; return {}; });
  assert.equal(time.active.size, 1);
  await time.fire(); assert.equal(calls, 1);
  scheduler.unsubscribe('key'); assert.equal(time.active.size, 1);
  scheduler.unsubscribe('knob'); assert.equal(time.active.size, 0);
});

test('polls never overlap and failed monitor reads use bounded backoff', async () => {
  const time = clock(); const scheduler = new SharedPolling(time); let release;
  scheduler.subscribe('brightness:MO32U2', 'key', 15000, () => new Promise(resolve => { release = resolve; }));
  const running = time.fire();
  assert.equal(time.active.size, 0);
  release(null); await running;
  assert.equal([...time.active][0].delay, 30000);
  scheduler.unsubscribe('key');
});
