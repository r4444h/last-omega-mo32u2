const { EventEmitter } = require('node:events');
const path = require('node:path');
const { MonitorWorker } = require('../com.mirabox.streamdock.lastomega.sdPlugin/plugin/utils/monitor-worker');

// Adapt native RPC requests to the existing deterministic hardware fixtures.
module.exports = function workerBridge(executeFile) {
  return class FixtureWorker extends MonitorWorker {
    constructor(options = {}) {
      super({ ...options, ensureScript: async () => {}, spawnProcess() {
        const child = new EventEmitter();
        child.stdout = new EventEmitter(); child.stdout.setEncoding = () => {};
        child.stderr = new EventEmitter();
        child.stdin = {
          destroy() {},
          write(line) {
            const request = JSON.parse(line);
            const names = { hdr: 'Hdr', brightness: 'Brightness', crosshair: 'Crosshair',
              pictureMode: 'PictureMode', refreshRate: 'RefreshRate' };
            const args = ['-File', path.join('plugin', names[request.kind] + 'Control.ps1'), '-Action', request.action || 'status'];
            for (const [key, flag] of Object.entries({ nameFilter: 'NameFilter', style: 'Style', value: 'Value', delta: 'Delta' })) {
              if (request[key] != null) args.push('-' + flag, String(request[key]));
            }
            if (typeof request.expectedHdrEnabled === 'boolean') args.push('-ExpectedHdr', request.expectedHdrEnabled ? 'on' : 'off');
            executeFile('native-fixture', args, {}, (error, stdout, stderr) => {
              let result;
              try { result = JSON.parse(String(stdout || '').trim().split(/\r?\n/).at(-1)); }
              catch (_) { result = { ok: false, error: stderr || error?.message || 'Invalid fixture response' }; }
              child.stdout.emit('data', JSON.stringify({ id: request.id, result }) + '\n');
            });
          }
        };
        child.kill = () => queueMicrotask(() => child.emit('exit', 0));
        return child;
      } });
    }
  };
};
