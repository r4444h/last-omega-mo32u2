const ws = require('ws');
const fs = require('fs');
const path = require('path');

const DEBUG_LOG = path.join(__dirname, '..', 'lastomega-debug.log');
const DEBUG_MAX = 48 * 1024;

function writeDebugLine(level, args) {
  try {
    const line =
      `${new Date().toISOString()} [${level}] ` +
      args
        .map((a) => {
          if (a instanceof Error) return a.stack || a.message;
          if (typeof a === 'string') return a;
          try {
            return JSON.stringify(a);
          } catch (_) {
            return String(a);
          }
        })
        .join(' ') +
      '\n';
    let prev = '';
    try {
      prev = fs.readFileSync(DEBUG_LOG, 'utf8');
    } catch (_) {}
    const next = (prev + line).slice(-DEBUG_MAX);
    fs.writeFileSync(DEBUG_LOG, next, 'utf8');
  } catch (_) {}
}

const DEBUG_ENABLED =
  process.env.LASTOMEGA_DEBUG === '1' || process.env.LASTOMEGA_DEBUG === 'true';

// Errors always go to console + small on-disk ring log (StreamDock hides console).
// Info/warn only when LASTOMEGA_DEBUG=1.
const log = {
  info: (...args) => {
    if (DEBUG_ENABLED) writeDebugLine('info', args);
  },
  warn: (...args) => {
    if (DEBUG_ENABLED) writeDebugLine('warn', args);
    try {
      console.error('[lastomega:warn]', ...args);
    } catch (_) {}
  },
  error: (...args) => {
    writeDebugLine('error', args);
    try {
      console.error('[lastomega]', ...args);
    } catch (_) {}
  }
};

if (DEBUG_ENABLED) writeDebugLine('info', ['plugin boot', DEBUG_LOG]);

process.on('uncaughtException', (error) => {
  log.error('Uncaught Exception:', error);
});
process.on('unhandledRejection', (reason) => {
  log.error('Unhandled Rejection:', reason);
});

class Plugins {
  static language = 'en';
  static globalSettings = {};
  getGlobalSettingsFlag = true;

  constructor() {
    if (Plugins.instance) {
      return Plugins.instance;
    }

    try {
      Plugins.language = JSON.parse(process.argv[9]).application.language;
    } catch (_) {
      Plugins.language = 'en';
    }

    this.ws = new ws('ws://127.0.0.1:' + process.argv[3]);
    this.ws.on('open', () =>
      this.ws.send(JSON.stringify({ uuid: process.argv[5], event: process.argv[7] }))
    );
    this.ws.on('close', process.exit);
    this.ws.on('message', (e) => {
      if (this.getGlobalSettingsFlag) {
        this.getGlobalSettingsFlag = false;
        this.getGlobalSettings();
      }
      const data = JSON.parse(e.toString());
      const action = data.action?.split('.').pop();
      this[action]?.[data.event]?.(data);
      if (data.event === 'didReceiveGlobalSettings') {
        Plugins.globalSettings = data.payload.settings;
      }
      this[data.event]?.(data);
    });
    Plugins.instance = this;
  }

  setGlobalSettings(payload) {
    Plugins.globalSettings = payload;
    this.ws.send(
      JSON.stringify({
        event: 'setGlobalSettings',
        context: process.argv[5],
        payload
      })
    );
  }

  getGlobalSettings() {
    this.ws.send(
      JSON.stringify({
        event: 'getGlobalSettings',
        context: process.argv[5]
      })
    );
  }

  setTitle(context, str, row = 0, num = 6) {
    let newStr = null;
    if (row && str) {
      let nowRow = 1;
      const strArr = String(str).split('');
      strArr.forEach((item, index) => {
        if (nowRow < row && index >= nowRow * num) {
          nowRow++;
          newStr += '\n';
        }
        if (nowRow <= row && index < nowRow * num) {
          newStr += item;
        }
      });
      if (strArr.length > row * num) {
        newStr = newStr.substring(0, newStr.length - 1);
        newStr += '..';
      }
    }
    this.ws.send(
      JSON.stringify({
        event: 'setTitle',
        context,
        payload: {
          target: 0,
          title: newStr || String(str)
        }
      })
    );
  }

  setImage(context, url) {
    this.ws.send(
      JSON.stringify({
        event: 'setImage',
        context,
        payload: {
          target: 0,
          image: url
        }
      })
    );
  }

  setState(context, state) {
    this.ws.send(
      JSON.stringify({
        event: 'setState',
        context,
        payload: { state }
      })
    );
  }

  setSettings(context, payload) {
    this.ws.send(
      JSON.stringify({
        event: 'setSettings',
        context,
        payload
      })
    );
  }

  showAlert(context) {
    this.ws.send(JSON.stringify({ event: 'showAlert', context }));
  }

  showOk(context) {
    this.ws.send(JSON.stringify({ event: 'showOk', context }));
  }

  sendToPropertyInspector(payload) {
    this.ws.send(
      JSON.stringify({
        action: Actions.currentAction,
        context: Actions.currentContext,
        payload,
        event: 'sendToPropertyInspector'
      })
    );
  }

  openUrl(url) {
    this.ws.send(
      JSON.stringify({
        event: 'openUrl',
        payload: { url }
      })
    );
  }
}

class Actions {
  constructor(data) {
    this.data = {};
    this.default = {};
    Object.assign(this, data);
  }

  static currentAction = null;
  static currentContext = null;
  static actions = {};

  propertyInspectorDidAppear(data) {
    Actions.currentAction = data.action;
    Actions.currentContext = data.context;
    this._propertyInspectorDidAppear?.(data);
  }

  willAppear(data) {
    Plugins.globalContext = data.context;
    Actions.actions[data.context] = data.action;
    const {
      context,
      payload: { settings }
    } = data;
    this.data[context] = Object.assign({ ...this.default }, settings);
    this._willAppear?.(data);
  }

  didReceiveSettings(data) {
    this.data[data.context] = Object.assign(
      { ...this.default },
      this.data[data.context] || {},
      data.payload.settings
    );
    this._didReceiveSettings?.(data);
  }

  willDisappear(data) {
    this._willDisappear?.(data);
    delete this.data[data.context];
  }
}

module.exports = {
  log,
  Plugins,
  Actions
};
