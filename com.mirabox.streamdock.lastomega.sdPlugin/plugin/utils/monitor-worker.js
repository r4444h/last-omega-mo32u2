const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

class MonitorWorker {
  constructor({ directory = path.resolve(__dirname, '..'), spawnProcess = spawn,
    ensureScript, onEvent = () => {}, timeout = 15000 } = {}) {
    Object.assign(this, { directory, spawnProcess, onEvent, timeout });
    this.ensureScript = ensureScript || (() => this.checkScript());
    this.queue = [];
    this.reads = new Map();
    this.sequence = 0;
    this.buffer = '';
    this.closed = false;
  }

  checkScript() {
    if (!fs.existsSync(path.join(this.directory, 'MonitorControl.ps1'))) throw new Error('MonitorControl.ps1 missing. Reinstall the plugin package.');
  }

  async start() {
    if (this.child) return;
    await this.ensureScript();
    if (this.closed) throw new Error('Monitor worker closed');
    const child = this.spawnProcess('powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive',
      '-ExecutionPolicy', 'RemoteSigned',
      '-File', path.join(this.directory, 'MonitorControl.ps1')], {
      cwd: this.directory, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe']
    });
    this.child = child;
    this.buffer = '';
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', data => { if (this.child === child) this.receive(data); });
    let stderr = '';
    child.stderr.on('data', data => { stderr = (stderr + data.toString()).slice(-4096); });
    child.stdin.on?.('error', error => { if (this.child === child) this.fail(error); });
    child.on('error', error => { if (this.child === child) this.fail(error); });
    child.on('exit', () => {
      if (this.child === child) this.fail(new Error('Monitor worker exited' + (stderr ? ': ' + stderr.trim() : '')));
    });
  }

  request(kind, options = {}) {
    if (this.closed) return Promise.reject(new Error('Monitor worker closed'));
    const action = options.action || 'status';
    const read = action === 'status' || action === 'list';
    const key = read ? JSON.stringify([kind, action, options.nameFilter || 'MO32U2']) : null;
    if (key && this.reads.has(key)) return this.reads.get(key);
    const job = { kind, options, key, priority: read ? 1 : 0, id: ++this.sequence };
    const result = new Promise((resolve, reject) => Object.assign(job, { resolve, reject }));
    if (key) this.reads.set(key, result);
    this.queue.push(job);
    this.pump();
    return result;
  }

  async pump() {
    if (this.active || !this.queue.length || this.closed) return;
    // A write does not wait behind queued background status reads.
    const index = this.queue.findIndex(job => job.priority === 0);
    const job = this.queue.splice(index < 0 ? 0 : index, 1)[0];
    this.active = job;
    try {
      await this.start();
      if (this.active !== job) return;
      job.timer = setTimeout(() => this.fail(new Error('Monitor command timed out')), this.timeout);
      this.child.stdin.write(JSON.stringify({ ...job.options, kind: job.kind, id: job.id }) + '\n');
    } catch (error) { this.fail(error); }
  }

  receive(data) {
    this.buffer += data;
    if (this.buffer.length > 1024 * 1024) { this.fail(new Error('Invalid monitor worker response')); return; }
    let end;
    while ((end = this.buffer.indexOf('\n')) >= 0) {
      const line = this.buffer.slice(0, end).trim();
      this.buffer = this.buffer.slice(end + 1);
      if (!line) continue;
      let message;
      try { message = JSON.parse(line); }
      catch (_) { this.fail(new Error('Invalid monitor worker JSON')); return; }
      if (message.event) {
        // The display driver can invalidate its process-local DDC connection
        // after a mode/topology change. Reconnect after any current reply.
        if (message.event === 'displayChanged') {
          this.recycleAfterReply = true;
          if (!this.active) this.recycle();
        }
        this.onEvent(message.event);
        continue;
      }
      const job = this.active;
      if (!job || message.id !== job.id) continue;
      clearTimeout(job.timer);
      this.active = null;
      if (job.key) this.reads.delete(job.key);
      if (this.recycleAfterReply || (job.kind === 'hdr' && !['status', 'list'].includes(job.options.action || 'status'))) this.recycle();
      if (message.result?.ok) job.resolve(message.result);
      else job.reject(new Error(message.result?.error || 'Monitor command failed'));
      this.pump();
    }
  }

  recycle() {
    const child = this.child;
    this.child = null;
    this.recycleAfterReply = false;
    if (child) { child.stdin.destroy(); child.kill(); }
  }

  fail(error) {
    const child = this.child;
    this.child = null;
    const jobs = [...(this.active ? [this.active] : []), ...this.queue];
    this.active = null;
    this.queue = [];
    this.reads.clear();
    for (const job of jobs) { clearTimeout(job.timer); job.reject(error); }
    if (child) { child.stdin.destroy(); child.kill(); }
  }

  close() { this.closed = true; this.fail(new Error('Monitor worker closed')); }
}

module.exports = { MonitorWorker };
