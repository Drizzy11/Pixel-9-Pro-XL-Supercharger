import test from 'node:test';
import assert from 'node:assert/strict';

class FakeClassList {
  constructor(names = []) { this.names = new Set(names); }
  add(...names) { names.forEach(name => this.names.add(name)); }
  remove(...names) { names.forEach(name => this.names.delete(name)); }
  toggle(name, force) {
    const enabled = force === undefined ? !this.names.has(name) : Boolean(force);
    enabled ? this.names.add(name) : this.names.delete(name);
    return enabled;
  }
  contains(name) { return this.names.has(name); }
}

class FakeElement {
  constructor({ id = '', classes = [], dataset = {}, value = '' } = {}) {
    this.id = id;
    this.dataset = dataset;
    this.value = value;
    this.textContent = '';
    this.disabled = false;
    this.children = [];
    this.listeners = new Map();
    this.classList = new FakeClassList(classes);
    this.className = classes.join(' ');
    this.style = {};
    this._innerHTML = '';
  }
  set innerHTML(value) { this._innerHTML = String(value); this.children = []; }
  get innerHTML() { return this._innerHTML; }
  appendChild(child) { this.children.push(child); return child; }
  removeChild(child) { this.children = this.children.filter(item => item !== child); }
  setAttribute() {}
  select() {}
  addEventListener(type, handler) {
    if (!this.listeners.has(type)) this.listeners.set(type, []);
    this.listeners.get(type).push(handler);
  }
  async dispatch(type) {
    for (const handler of this.listeners.get(type) || []) await handler({ currentTarget: this });
  }
}

const ids = [
  'statusValue', 'statusSub', 'profileValue', 'versionValue', 'deviceValue', 'deviceSub',
  'addonValue', 'addonSub', 'thermalStateValue', 'thermalProfileValue', 'thermalRebootValue',
  'thermalMessage', 'healthPill', 'rootPill', 'tempPill', 'updaterPill', 'kernelValue',
  'buildValue', 'storageValue', 'networkValue', 'swapValue', 'updatedValue',
  'profileActiveSmooth', 'profileGaming', 'setActiveSmoothBtn', 'setGamingBtn',
  'thermalEnableBtn', 'thermalDisableBtn', 'thermalBalancedBtn', 'thermalGamingBtn',
  'thermalChargeCoolBtn', 'logBox', 'snapshotBox', 'appSelect', 'appSearch',
  'optimizationBox', 'maintenanceBox', 'profileBox', 'thermalBox', 'copyLogBtn',
  'maintenanceAllBtn', 'refreshAppsBtn', 'optimizeAllBtn', 'optimizeSystemBtn',
  'dexoptJobBtn', 'optimizeSelectedBtn', 'loadSnapshotBtn', 'copySnapshotBtn',
  'overview', 'profiles', 'maintenance', 'logs', 'support', 'recompileSelectedBtn'
];

const elements = new Map(ids.map(id => [id, new FakeElement({ id })]));
const actionIds = [
  'setActiveSmoothBtn', 'setGamingBtn', 'thermalEnableBtn', 'thermalDisableBtn',
  'thermalBalancedBtn', 'thermalGamingBtn', 'thermalChargeCoolBtn', 'copyLogBtn',
  'maintenanceAllBtn', 'refreshAppsBtn', 'optimizeAllBtn', 'optimizeSystemBtn',
  'dexoptJobBtn', 'optimizeSelectedBtn', 'loadSnapshotBtn', 'copySnapshotBtn', 'recompileSelectedBtn'
];
for (const id of actionIds) elements.get(id).classList.add('action');

const tabs = ['overview', 'profiles', 'maintenance', 'logs', 'support'].map((name, index) =>
  new FakeElement({ classes: index ? ['tab'] : ['tab', 'active'], dataset: { tab: name } })
);
const sections = ['overview', 'profiles', 'maintenance', 'logs', 'support'].map((id, index) => {
  const el = elements.get(id);
  el.classList.add('section');
  if (!index) el.classList.add('active');
  return el;
});
const logButtons = ['debug.log', 'debug.previous.log', 'maintenance.log'].map((name, index) =>
  new FakeElement({ classes: index ? ['logBtn'] : ['logBtn', 'active'], dataset: { log: name } })
);

globalThis.window = globalThis;
const documentListeners = new Map();
globalThis.document = {
  hidden: false,
  addEventListener(type, handler) { documentListeners.set(type, handler); },
  querySelector(selector) { return selector.startsWith('#') ? elements.get(selector.slice(1)) || null : null; },
  querySelectorAll(selector) {
    if (selector === '.tab') return tabs;
    if (selector === '.section') return sections;
    if (selector === '.logBtn') return logButtons;
    if (selector === 'button.action, button.safe, button.warnBtn') return actionIds.map(id => elements.get(id));
    return [];
  },
  createElement() { return new FakeElement(); },
  body: new FakeElement(),
  execCommand() { return true; }
};
Object.defineProperty(globalThis, 'navigator', { value: {}, configurable: true });

let nextInterval = 1;
const activeIntervals = new Set();
const intervalCallbacks = new Map();
globalThis.setInterval = callback => { const id = nextInterval++; activeIntervals.add(id); intervalCallbacks.set(id, callback); return id; };
globalThis.clearInterval = id => { activeIntervals.delete(id); intervalCallbacks.delete(id); };

let failAppList = false;
let failStatus = false;
let deferStatus = false;
let failMaintSync = false;
let deferLogs = false;
let statusExtra = '';
let appOptState = 'done';
let appOptLabel = 'Optimizing com.example.app';
let deferProgress = false;
let failProgress = false;
let failStart = false;
let failProfile = false;
let appListText = 'user|com.example.app\n';
let deferApps = false;
const pendingAppCallbacks = [];
const pendingProgressCallbacks = [];
const pendingStatusCallbacks = [];
const pendingLogCallbacks = [];
const execLog = [];
const statusText = [
  'HEALTH=pass', 'VERSION=v2.6.5', 'MODEL=Pixel 9 Pro', 'DEVICE=caiman',
  'ANDROID_RELEASE=16', 'ANDROID_SDK=36', 'ROOT_ENV=KernelSU',
  'SELECTED_PROFILE=active_smooth', 'THERMAL_CONTROL_AVAILABLE=1',
  'THERMAL_CONTROL_MERGED=1', 'THERMAL_CONTROL_ENABLED=0',
  'DASHBOARD_UPDATER_STATE=running', 'BLOCK_AUDITED_LIST=sda sdb sdc sdd'
].join('\n');

globalThis.ksu = {
  fullScreen() {}, enableEdgeToEdge() {}, toast() {},
  exec(command, _options, callbackName) {
    execLog.push(command);
    if (command.includes('app-opt-progress') && deferProgress) { pendingProgressCallbacks.push(callbackName); return; }
    if (command.includes('list-apps') && deferApps) { pendingAppCallbacks.push(callbackName); return; }
    if (command.includes('status-quiet') && deferStatus) {
      pendingStatusCallbacks.push(callbackName);
      return;
    }
    const logFile = command.match(/^cat '[^']*\/([^'\/]+)'/);
    let errno = 0;
    let stdout = '';
    let stderr = '';
    if (command.includes('status-quiet') && failStatus) { errno = 1; stderr = 'module status unavailable'; }
    else if (command.includes('status-quiet')) stdout = statusExtra ? `${statusText}\n${statusExtra}` : statusText;
    else if (command.includes('maintenance-progress') && failMaintSync) { errno = 1; stderr = 'maintenance state unavailable'; }
    else if (command.includes('maintenance-progress')) stdout = 'STATE=idle\n\n__SUPERCHARGER_LOG__\nFinished';
    else if (command.includes('app-opt-progress') && failProgress) stdout = 'malformed progress';
    else if (command.includes('app-opt-progress')) stdout = `STATE=${appOptState}\nLABEL=${appOptLabel}\n\n__SUPERCHARGER_LOG__\nFinished`;
    else if (command.includes('thermal-detect')) stdout = '';
    else if (command.includes('list-apps') && failAppList) { errno = 1; stderr = 'package manager unavailable'; }
    else if (command.includes('list-apps')) stdout = appListText;
    else if (command.includes('optimize-apps-async') && failStart) { errno = 1; stderr = 'already running'; }
    else if (command.includes('optimize-apps-async')) stdout = 'Started';
    else if (command.includes('set-profile') && failProfile) {
      statusExtra = 'SELECTED_PROFILE=performance_gaming\nPROFILE_LABEL=Performance / Gaming';
      errno = 1; stderr = 'Profile saved locally, but persistence failed';
    }
    else if (logFile) stdout = `${logFile[1]} contents`;
    if (logFile && deferLogs) { pendingLogCallbacks.push({ callbackName, stdout }); return; }
    queueMicrotask(() => globalThis[callbackName](errno, stdout, stderr));
  }
};

await import('../webroot/index.mjs?regression-test');
await new Promise(resolve => setTimeout(resolve, 0));

test('a task that is already complete does not leave a polling interval active', async () => {
  activeIntervals.clear();
  await elements.get('optimizeAllBtn').dispatch('click');
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(activeIntervals.size, 0, 'completed task left a polling interval active');
});

test('app-list failure replaces loading state and prevents selected-app optimization', async () => {
  failAppList = true;
  await tabs.find(tab => tab.dataset.tab === 'maintenance').dispatch('click');
  const select = elements.get('appSelect');
  assert.equal(select.children.length, 1, 'selector should contain an error option');
  assert.equal(select.children[0].textContent, 'App list unavailable');
  assert.equal(elements.get('optimizeSelectedBtn').disabled, true);
  assert.match(elements.get('optimizationBox').textContent, /package manager unavailable/);
});

test('selected-app optimization is enabled only when the filtered list has options', async () => {
  failAppList = false;
  await tabs.find(tab => tab.dataset.tab === 'maintenance').dispatch('click');
  assert.equal(elements.get('optimizeSelectedBtn').disabled, false, 'available app should enable optimization');
  elements.get('appSearch').value = 'does.not.exist';
  await elements.get('appSearch').dispatch('input');
  assert.equal(elements.get('optimizeSelectedBtn').disabled, true, 'empty filter result should disable optimization');
  await elements.get('optimizeAllBtn').dispatch('click');
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(elements.get('optimizeSelectedBtn').disabled, true, 'busy-to-idle transition should preserve empty selection state');
});

test('a re-tap during the completion refresh cannot start a second job or strand the controls', async () => {
  activeIntervals.clear();
  execLog.length = 0;
  deferStatus = true;
  await elements.get('optimizeAllBtn').dispatch('click');
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(pendingStatusCallbacks.length, 1, 'the completion refresh should still be in flight');
  assert.equal(elements.get('optimizeAllBtn').disabled, true, 'actions must stay busy until the completion refresh finishes');
  await elements.get('optimizeAllBtn').dispatch('click');
  await new Promise(resolve => setTimeout(resolve, 0));
  deferStatus = false;
  for (const callbackName of pendingStatusCallbacks.splice(0)) globalThis[callbackName](0, statusText, '');
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(execLog.filter(command => command.includes('optimize-apps-async')).length, 1, 're-tap started a second background job');
  assert.equal(elements.get('optimizeAllBtn').disabled, false, 'controls stayed disabled after the task finished');
  assert.equal(activeIntervals.size, 0, 'the finished task left a polling interval active');
});

test('out-of-order log responses keep the highlighted tab and the rendered log together', async () => {
  deferLogs = true;
  const first = logButtons[0].dispatch('click');
  const second = logButtons[2].dispatch('click');
  deferLogs = false;
  for (const pending of pendingLogCallbacks.splice(0).reverse()) globalThis[pending.callbackName](0, pending.stdout, '');
  await Promise.all([first, second]);
  assert.equal(logButtons[2].classList.contains('active'), true, 'the last requested log should stay highlighted');
  assert.equal(logButtons[0].classList.contains('active'), false, 'only the last requested log should be highlighted');
  assert.equal(elements.get('logBox').textContent, 'maintenance.log contents', 'a stale log response overwrote the current log');
});

test('a second copy click inside the feedback window restores the real button label', async () => {
  const button = elements.get('copyLogBtn');
  button.textContent = 'Copy';
  await button.dispatch('click');
  assert.equal(button.textContent, 'Copied');
  await button.dispatch('click');
  await new Promise(resolve => setTimeout(resolve, 1500));
  assert.equal(button.textContent, 'Copy', 'the copy button kept a temporary label permanently');
});

test('an interrupted task renders as finished and stops polling', async () => {
  activeIntervals.clear();
  appOptState = 'interrupted';
  await elements.get('optimizeAllBtn').dispatch('click');
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.match(elements.get('optimizationBox').textContent, /^Optimizing com\.example\.app\nStatus: Interrupted\n/);
  assert.equal(activeIntervals.size, 0, 'an interrupted task kept polling');
  assert.equal(elements.get('optimizeAllBtn').disabled, false, 'an interrupted task left the controls disabled');
  appOptState = 'done';
});

test('app inventory is cached, explicitly refreshed, and invalidated after failure', async () => {
  elements.get('appSearch').value = '';
  execLog.length = 0;
  const maintenance = tabs.find(tab => tab.dataset.tab === 'maintenance');
  await maintenance.dispatch('click');
  await maintenance.dispatch('click');
  assert.equal(execLog.filter(c => c.includes('list-apps')).length, 0);
  appListText = 'user|com.example.new\n';
  await elements.get('refreshAppsBtn').dispatch('click');
  assert.equal(elements.get('appSelect').value, 'com.example.new');
  assert.equal(execLog.filter(c => c.includes('list-apps')).length, 1);
  failAppList = true;
  await elements.get('refreshAppsBtn').dispatch('click');
  assert.equal(elements.get('optimizeSelectedBtn').disabled, true);
  assert.equal(elements.get('recompileSelectedBtn').disabled, true);
  failAppList = false;
  appListText = 'user|com.example.app\n';
  await maintenance.dispatch('click');
  assert.equal(execLog.filter(c => c.includes('list-apps')).length, 3);
  assert.equal(elements.get('appSelect').value, 'com.example.app');
});

test('app cache expires and overlapping refresh requests share one bridge call', async () => {
  const originalNow = Date.now;
  const later = originalNow() + 61000;
  execLog.length = 0;
  try {
    Date.now = () => later;
    await tabs.find(tab => tab.dataset.tab === 'maintenance').dispatch('click');
    assert.equal(execLog.filter(c => c.includes('list-apps')).length, 1);
  } finally { Date.now = originalNow; }
  deferApps = true;
  const first = elements.get('refreshAppsBtn').dispatch('click');
  const second = elements.get('refreshAppsBtn').dispatch('click');
  assert.equal(pendingAppCallbacks.length, 1);
  assert.equal(elements.get('recompileSelectedBtn').disabled, true);
  deferApps = false;
  for(const callback of pendingAppCallbacks.splice(0)) globalThis[callback](0, appListText, '');
  await Promise.all([first, second]);
  assert.equal(execLog.filter(c => c.includes('list-apps')).length, 2);
});

test('hidden-page polling stops, ignores late responses, and renders completion on return', async () => {
  execLog.length = 0;
  appOptState = 'running';
  statusExtra = 'APP_OPT_TASK_STATE=running\nAPP_OPT_TASK_LABEL=Optimizing com.example.app';
  await elements.get('optimizeAllBtn').dispatch('click');
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(execLog.filter(c => c.includes('app-opt-progress')).length, 1);
  assert.equal(execLog.filter(c => c.includes('app-opt-status') || c.includes('app-opt-log')).length, 0);
  const poll = [...intervalCallbacks.values()][0];
  deferProgress = true;
  const pending = poll();
  const callsBeforeHide = execLog.length;
  const displayed = elements.get('optimizationBox').textContent;
  document.hidden = true;
  await documentListeners.get('visibilitychange')();
  await poll();
  assert.equal(activeIntervals.size, 0);
  assert.equal(execLog.length, callsBeforeHide);
  deferProgress = false;
  for(const callback of pendingProgressCallbacks.splice(0)) globalThis[callback](0, 'STATE=running\nLABEL=stale\n\n__SUPERCHARGER_LOG__\nstale', '');
  await pending;
  assert.equal(elements.get('optimizationBox').textContent, displayed);
  appOptState = 'done';
  statusExtra = 'APP_OPT_TASK_STATE=done';
  document.hidden = false;
  await documentListeners.get('visibilitychange')();
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.match(elements.get('optimizationBox').textContent, /Status: Complete/);
  assert.equal(activeIntervals.size, 0);
  assert.equal(elements.get('optimizeAllBtn').disabled, false);
  statusExtra = '';
});

test('an inventory response from before visibility invalidation cannot repopulate the cache', async () => {
  deferApps = true;
  const original = elements.get('refreshAppsBtn').dispatch('click');
  document.hidden = true;
  await documentListeners.get('visibilitychange')();
  document.hidden = false;
  const resumed = documentListeners.get('visibilitychange')();
  await new Promise(resolve => setTimeout(resolve, 0));
  deferApps = false;
  appListText = 'user|com.example.fresh\n';
  for(const callback of pendingAppCallbacks.splice(0)) globalThis[callback](0, 'user|com.example.stale\n', '');
  await Promise.all([original, resumed]);
  assert.equal(elements.get('appSelect').value, 'com.example.fresh');
  appListText = 'user|com.example.app\n';
  await elements.get('refreshAppsBtn').dispatch('click');
});

test('full status refresh no longer repeats the two task-state bridge calls', async () => {
  execLog.length = 0;
  await elements.get('optimizeAllBtn').dispatch('click');
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(execLog.filter(c => c.includes('status-quiet')).length, 1);
  assert.equal(execLog.filter(c => c.includes('maintenance-status') || c.includes('app-opt-status')).length, 0);
});

test('malformed progress is an error rather than a completed task', async () => {
  failProgress = true;
  await elements.get('optimizeAllBtn').dispatch('click');
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.match(elements.get('optimizationBox').textContent, /Invalid task progress response/);
  assert.equal(activeIntervals.size, 1);
  assert.equal(elements.get('optimizeAllBtn').disabled, true);
  const before = execLog.filter(c => c.includes('optimize-apps-async')).length;
  await elements.get('optimizeAllBtn').dispatch('click');
  assert.equal(execLog.filter(c => c.includes('optimize-apps-async')).length, before);
  failProgress = false;
  await [...intervalCallbacks.values()][0]();
  assert.equal(activeIntervals.size, 0);
  assert.equal(elements.get('optimizeAllBtn').disabled, false);
});

test('a rejected launch reconciles an existing worker before enabling controls', async () => {
  failStart = true;
  appOptState = 'running';
  statusExtra = 'APP_OPT_TASK_STATE=running';
  await elements.get('optimizeAllBtn').dispatch('click');
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(elements.get('optimizeAllBtn').disabled, true);
  assert.equal(activeIntervals.size, 1);
  failStart = false;
  appOptState = 'done';
  statusExtra = 'APP_OPT_TASK_STATE=done';
  await [...intervalCallbacks.values()][0]();
  assert.equal(elements.get('optimizeAllBtn').disabled, false);
  assert.equal(activeIntervals.size, 0);
  statusExtra = '';
});

test('forced recompilation uses its explicit selected-app action', async () => {
  execLog.length = 0;
  await elements.get('recompileSelectedBtn').dispatch('click');
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(execLog.filter(c => c.includes("optimize-app-force-async 'com.example.app'")).length, 1);
  assert.equal(execLog.filter(c => c.includes('optimize-apps-async')).length, 0);
});

test('a partial profile failure refreshes the selected profile and retains its error', async () => {
  failProfile = true;
  await elements.get('setGamingBtn').dispatch('click');
  assert.match(elements.get('profileBox').textContent, /persistence failed/);
  assert.equal(elements.get('profileValue').textContent, 'Performance / Gaming');
  assert.equal(elements.get('setGamingBtn').disabled, true);
  assert.equal(elements.get('setActiveSmoothBtn').disabled, false);
  failProfile = false;
  statusExtra = '';
  document.hidden = true;
  await documentListeners.get('visibilitychange')();
  document.hidden = false;
  await documentListeners.get('visibilitychange')();
});

test('an unreadable running task retries without allowing conflicting actions', async () => {
  activeIntervals.clear();
  failMaintSync = true;
  statusExtra = 'MAINTENANCE_TASK_STATE=running';
  for (const id of actionIds) elements.get(id).disabled = false;
  await import('../webroot/index.mjs?task-sync-failure-test');
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.notEqual(elements.get('statusValue').textContent, 'Unavailable', 'refreshStatus threw on an unreadable task state');
  assert.equal(elements.get('statusSub').textContent, 'One-tap maintenance');
  assert.equal(elements.get('optimizeAllBtn').disabled, true);
  assert.equal(activeIntervals.size, 1);
  failMaintSync = false;
  statusExtra = '';
  await [...intervalCallbacks.values()][0]();
  assert.equal(activeIntervals.size, 0);
  assert.equal(elements.get('optimizeAllBtn').disabled, false);
});

test('state-dependent actions stay disabled while initial status is pending', async () => {
  deferStatus = true;
  for (const id of actionIds) elements.get(id).disabled = false;
  await import('../webroot/index.mjs?status-pending-test');
  assert.equal(elements.get('setGamingBtn').disabled, true);
  assert.equal(elements.get('thermalEnableBtn').disabled, true);
  assert.equal(elements.get('optimizeAllBtn').disabled, true);
  deferStatus = false;
  for (const callbackName of pendingStatusCallbacks.splice(0)) {
    globalThis[callbackName](0, statusText, '');
  }
  await new Promise(resolve => setTimeout(resolve, 0));
});

test('initial status failure disables actions that depend on module state', async () => {
  failStatus = true;
  for (const id of actionIds) elements.get(id).disabled = false;
  await import('../webroot/index.mjs?status-failure-test');
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(elements.get('statusValue').textContent, 'Unavailable');
  assert.equal(elements.get('setGamingBtn').disabled, true);
  assert.equal(elements.get('thermalEnableBtn').disabled, true);
  assert.equal(elements.get('optimizeAllBtn').disabled, true);
});
