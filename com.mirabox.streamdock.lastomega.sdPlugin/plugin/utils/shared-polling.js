class SharedPolling {
  constructor({ setTimer = setTimeout, clearTimer = clearTimeout } = {}) {
    this.setTimer = setTimer;
    this.clearTimer = clearTimer;
    this.groups = new Map();
  }

  subscribe(key, context, interval, read) {
    this.unsubscribe(context);
    let group = this.groups.get(key);
    if (!group) {
      group = { contexts: new Map(), failures: 0, running: false, timer: null };
      this.groups.set(key, group);
    }
    group.contexts.set(context, { interval, read });
    if (!group.running) this.schedule(key, group);
  }

  schedule(key, group) {
    this.clearTimer(group.timer);
    if (!group.contexts.size) return;
    const interval = Math.min(...[...group.contexts.values()].map(value => value.interval));
    const delay = Math.min(120000, interval * 2 ** Math.min(group.failures, 4));
    group.timer = this.setTimer(async () => {
      if (this.groups.get(key) !== group) return;
      group.running = true;
      const selected = group.contexts.values().next().value;
      try { group.failures = (await selected.read()) == null ? group.failures + 1 : 0; }
      catch (_) { group.failures++; }
      finally {
        group.running = false;
        if (this.groups.get(key) === group) this.schedule(key, group);
      }
    }, delay);
    group.timer?.unref?.();
  }

  unsubscribe(context) {
    for (const [key, group] of this.groups) {
      if (!group.contexts.delete(context)) continue;
      if (!group.contexts.size) { this.clearTimer(group.timer); this.groups.delete(key); }
      else if (!group.running) this.schedule(key, group);
    }
  }
}

module.exports = { SharedPolling };
