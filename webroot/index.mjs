import { exec, toast, fullScreen, enableEdgeToEdge } from './kernelsu.js';

const MODDIR = '/data/adb/modules/p9pxl_supercharger';
const CTL = `${MODDIR}/bin/supercharger_ctl.sh`;
const $ = (s) => document.querySelector(s);
const $$ = (s) => [...document.querySelectorAll(s)];
let status = {};
let currentLog = 'debug.log';
let logRequest = 0;
let appEntries = [];
let commandBusy = false;
let commandPending = false;
let taskBusy = false;
let statusReady = false;
let appSelectionAvailable = false;
const taskPollers = {
  app: {timer:null, inFlight:false, generation:0},
  maintenance: {timer:null, inFlight:false, generation:0}
};
let statusRefresh = null;
let visibilityGeneration = 0;
let appListRequest = null;
let appListLoaded = false;
let appListFetchedAt = 0;
let appListIdentity = '';
let appListGeneration = 0;
const APP_LIST_TTL_MS = 60000;
const TASK_POLL_MS = 1800;
const STATUS_ACTION_IDS = [
  '#maintenanceAllBtn', '#refreshAppsBtn', '#optimizeAllBtn', '#optimizeSystemBtn',
  '#dexoptJobBtn', '#optimizeSelectedBtn', '#recompileSelectedBtn', '#setActiveSmoothBtn', '#setGamingBtn',
  '#thermalEnableBtn', '#thermalDisableBtn', '#thermalBalancedBtn',
  '#thermalGamingBtn', '#thermalChargeCoolBtn'
];

try { fullScreen(false); enableEdgeToEdge(false); } catch (_) {}

async function sh(cmd){
  const res = await exec(cmd);
  if(res.errno !== 0) throw new Error((res.stderr || res.stdout || `errno=${res.errno}`).trim());
  return res.stdout || '';
}

function parseEnv(text){
  const out = {};
  for(const rawLine of String(text || '').split(/\r?\n/)){
    const line = rawLine.trim();
    if(!line || line.startsWith('#')) continue;

    const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if(!m) continue;

    let value = m[2].trim();
    if(value.length >= 2){
      const first = value[0];
      const last = value[value.length - 1];
      if((first === '"' || first === "'") && first === last){
        value = value.slice(1, -1);
        if(first === "'") value = value.replace(/'\\''/g, "'");
        if(first === '"') value = value.replace(/\\"/g, '"').replace(/\\\\/g, '\\');
      }
    }

    out[m[1]] = value;
  }
  return out;
}

function setText(id, value){ const el = $(id); if(el) el.textContent = value || '—'; }
function setPill(id, text, kind){ const el = $(id); if(!el) return; el.textContent = text || '—'; el.className = `pill ${kind || ''}`.trim(); }
function isRunning(value){ return String(value || '').toLowerCase() === 'running'; }
function updateStatusActionButtons(){
  STATUS_ACTION_IDS.forEach(id => { const btn = $(id); if(btn) btn.disabled = commandBusy || !statusReady; });
}
function updateOptimizeSelectedButton(){
  ['#optimizeSelectedBtn', '#recompileSelectedBtn'].forEach(id => {
    const btn = $(id);
    if(btn) btn.disabled = commandBusy || !statusReady || !appSelectionAvailable;
  });
}
function setActionsBusy(busy){
  taskBusy = busy;
  commandBusy = taskBusy || commandPending;
  $$('button.action, button.safe, button.warnBtn').forEach(btn => { btn.disabled = commandBusy; });
  updateStatusActionButtons();
  updateProfileButtons();
  updateThermalButtons();
  updateOptimizeSelectedButton();
}
function setCommandPending(pending){
  // Status/visibility refreshes cannot release a command that still owns a write.
  commandPending = pending;
  setActionsBusy(taskBusy);
}
function showHeaderTask(label){ setText('#statusValue', 'Running'); setText('#statusSub', label || 'Background task in progress'); }

function titleCase(value){
  return String(value || '').replace(/[_-]+/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
}

function stateLabel(value){
  const state = String(value || '').trim().toLowerCase();
  if(!state || state === 'idle') return 'Idle';
  if(state === 'running') return 'Running';
  if(state === 'done') return 'Complete';
  if(state === 'failed') return 'Needs review';
  if(state === 'interrupted') return 'Interrupted';
  if(state === 'stale') return 'Stale';
  if(state === 'pass') return 'Pass';
  if(state === 'warn') return 'Warning';
  return titleCase(state);
}

function appTypeLabel(type){
  const value = String(type || '').trim().toLowerCase();
  if(value === 'user') return 'User';
  if(value === 'system') return 'System';
  return 'App';
}

function thermalLabel(profile){
  switch(String(profile || '').trim()){
    case 'balanced': return 'Balanced Thermal';
    case 'gaming': return 'Gaming Thermal';
    case 'charge_cool': return 'Charge Cool Thermal';
    default: return titleCase(profile || 'Thermal profile');
  }
}

function addonLabel(s){
  if(String(s.THERMAL_CONTROL_MERGED || '0') === '1') return 'Integrated';
  return String(s.THERMAL_ADDON_INSTALLED || '0') === '1' ? 'External add-on' : 'Unavailable';
}
function addonSub(s){
  if(String(s.THERMAL_CONTROL_MERGED || '0') === '1'){
    const mode = thermalEnabled() ? 'On' : 'Off';
    const profile = s.THERMAL_CONTROL_LABEL || thermalProfile();
    return `${mode} · ${profile}`;
  }
  const installed = String(s.THERMAL_ADDON_INSTALLED || '0') === '1';
  const target = s.THERMAL_PROFILE_REQUEST ? ` · Target: ${titleCase(s.THERMAL_PROFILE_REQUEST)}` : '';
  return installed ? `${s.THERMAL_ADDON_VERSION || 'Installed'}${target}` : `Not available${target}`;
}

async function resolveThermalAddon(){
  if(String(status.THERMAL_ADDON_INSTALLED || '0') === '1') return;
  try {
    const out = await sh(`sh '${CTL}' thermal-detect 2>/dev/null || true`);
    const detected = String(out || '').match(/Detected:\s*([01])\|([^\n]+)/i);
    if(detected && detected[1] === '1'){
      status.THERMAL_ADDON_INSTALLED = '1';
      status.THERMAL_ADDON_VERSION = detected[2].trim() || 'installed';
      return;
    }

    const registry = parseEnv(out);
    if(String(registry.THERMAL_CONTROL_INSTALLED || '0') === '1' || registry.THERMAL_CONTROL_VERSION){
      status.THERMAL_ADDON_INSTALLED = '1';
      const state = registry.THERMAL_CONTROL_STATE && registry.THERMAL_CONTROL_STATE !== 'active' ? ` (${registry.THERMAL_CONTROL_STATE})` : '';
      status.THERMAL_ADDON_VERSION = `${registry.THERMAL_CONTROL_VERSION || 'installed'}${state}`;
    }
  } catch (_) {}
}

function normalizeUpdaterState(raw){
  let state = String(raw || 'unknown');
  if(state.includes('|')) state = state.split('|').pop() || state;
  return state === 'none' ? 'stopped' : state;
}

function isMissingStorageValue(value){
  const v = String(value || '').trim().toLowerCase();
  return !v || v === '—' || v === 'none' || v === 'unknown' || v === 'not reported';
}

function extractStorageDevices(text){
  const found = [];
  const seen = new Set();
  for(const token of String(text || '').split(/[^A-Za-z0-9._-]+/).filter(Boolean)){
    if(/^(sd[a-z][a-z]?|mmcblk[0-9]+|nvme[0-9]+n[0-9]+)$/.test(token) && !seen.has(token)){
      seen.add(token);
      found.push(token);
    }
  }
  return found.join(', ');
}

function pixelStorageDefault(){
  const deviceText = [status.DEVICE, status.DEVICE_CODENAME, status.CODENAME, status.MODEL].map(v => String(v || '').toLowerCase()).join(' ');
  return /\b(komodo|caiman|tokay|comet)\b/.test(deviceText) || deviceText.includes('pixel 9') ? 'sda, sdb, sdc, sdd' : '';
}

function cleanStorageValue(value){
  const parsed = extractStorageDevices(value);
  if(parsed) return parsed;
  return isMissingStorageValue(value) ? (pixelStorageDefault() || 'Not reported') : String(value).trim();
}

async function resolveStorageValue(){
  const existing = cleanStorageValue(status.BLOCK_AUDITED_LIST);
  if(!isMissingStorageValue(existing)) return existing;

  const commands = [
    `sh '${CTL}' storage 2>/dev/null || true`,
    `grep -ihE 'Physical Block Devices|Audited Block Devices|Physical block devices detected|Block Verify|Block IO Stats' '${MODDIR}/support_snapshot.txt' '${MODDIR}/debug.log' '${MODDIR}/debug.previous.log' 2>/dev/null | tail -n 120 || true`
  ];

  for(const cmd of commands){
    try {
      const out = (await sh(cmd)).trim();
      const parsed = extractStorageDevices(out);
      if(parsed) return parsed;
    } catch (_) {}
  }

  return pixelStorageDefault() || 'Not reported';
}

function renderProfileCards(){
  const selected = status.SELECTED_PROFILE || 'active_smooth';
  $('#profileActiveSmooth')?.classList.toggle('active', selected === 'active_smooth');
  $('#profileGaming')?.classList.toggle('active', selected === 'performance_gaming');
  updateProfileButtons();
}

function updateProfileButtons(){
  const selected = status.SELECTED_PROFILE || 'active_smooth';
  const a = $('#setActiveSmoothBtn');
  const g = $('#setGamingBtn');
  if(a) a.disabled = commandBusy || !statusReady || selected === 'active_smooth';
  if(g) g.disabled = commandBusy || !statusReady || selected === 'performance_gaming';
}

function thermalEnabled(){ return String(status.THERMAL_CONTROL_ENABLED || '0') === '1'; }
function thermalAvailable(){ return String(status.THERMAL_CONTROL_AVAILABLE || '0') === '1'; }
function thermalProfile(){ return status.THERMAL_CONTROL_PROFILE || status.THERMAL_PROFILE_REQUEST || 'balanced'; }

function updateThermalButtons(){
  const available = thermalAvailable();
  const enabled = thermalEnabled();
  const profile = thermalProfile();
  const enable = $('#thermalEnableBtn');
  const disable = $('#thermalDisableBtn');
  const balanced = $('#thermalBalancedBtn');
  const gaming = $('#thermalGamingBtn');
  const charge = $('#thermalChargeCoolBtn');

  if(enable) enable.disabled = commandBusy || !statusReady || !available || enabled;
  if(disable) disable.disabled = commandBusy || !statusReady || !available || !enabled;
  if(balanced) balanced.disabled = commandBusy || !statusReady || !available || (enabled && profile === 'balanced');
  if(gaming) gaming.disabled = commandBusy || !statusReady || !available || (enabled && profile === 'gaming');
  if(charge) charge.disabled = commandBusy || !statusReady || !available || (enabled && profile === 'charge_cool');
}

function renderStatus(){
  const health = (status.HEALTH || 'unknown').toLowerCase();
  const healthKind = health === 'pass' ? 'good' : (health === 'warn' ? 'warn' : 'bad');
  const updater = normalizeUpdaterState(status.DASHBOARD_UPDATER_STATE || status.DASHBOARD_UPDATER_PID);
  const updaterKind = updater === 'running' ? 'good' : (updater === 'stale' ? 'warn' : '');
  const taskState = String(status.TASK_STATE || 'idle').toLowerCase();

  if(taskState === 'running'){
    setText('#statusValue', 'Running');
    setText('#statusSub', status.TASK_LABEL || 'Background task in progress');
  } else {
    setText('#statusValue', health === 'pass' ? 'Ready' : 'Review logs');
    setText('#statusSub', health === 'pass' ? 'No background tasks are running' : 'Latest audit needs attention');
  }

  setText('#profileValue', status.PROFILE_LABEL || status.PROFILE_MODE || '—');
  setText('#versionValue', `${status.VERSION || '—'} · ${status.PERFORMANCE_ENGINE_STATE || 'stable'}`);
  setText('#deviceValue', `${status.MODEL || 'Unknown'} (${status.DEVICE || 'unknown'})`);
  setText('#deviceSub', `Android ${status.ANDROID_RELEASE || '—'} / SDK ${status.ANDROID_SDK || '—'} · ${status.ROOT_ENV || 'Root unknown'}`);
  setText('#addonValue', addonLabel(status));
  setText('#addonSub', addonSub(status));
  setText('#thermalStateValue', thermalEnabled() ? 'On' : 'Off');
  setText('#thermalProfileValue', status.THERMAL_CONTROL_LABEL || thermalProfile());
  setText('#thermalRebootValue', String(status.THERMAL_CONTROL_REBOOT_REQUIRED || '0') === '1' ? 'Required' : 'Not required');
  setText('#thermalMessage', status.THERMAL_CONTROL_MESSAGE || 'Off by default for a safe first boot. Enable it after the phone boots normally.');
  setPill('#healthPill', `Health: ${stateLabel(status.HEALTH || 'unknown')}`, healthKind);
  setPill('#rootPill', `Root: ${status.ROOT_ENV || 'Unknown'}`, '');
  setPill('#tempPill', `Temp: ${status.BATTERY_TEMP || 'Unknown'}`, '');
  setPill('#updaterPill', `Updater: ${stateLabel(updater)}`, updaterKind);
  setText('#kernelValue', status.KERNEL_RELEASE || '—');
  setText('#buildValue', status.BUILD_ID || '—');
  setText('#storageValue', cleanStorageValue(status.BLOCK_AUDITED_LIST));
  setText('#networkValue', status.NETWORK_CAPABILITY_SUMMARY || '—');
  setText('#swapValue', String(status.SWAP_ACTIVE || '0') === '1' ? `Active · page-cluster ${status.PAGE_CLUSTER_STATUS || '—'}` : 'Inactive');
  setText('#updatedValue', status.LAST_UPDATED || '—');
  renderProfileCards();
  updateThermalButtons();
}

function anyTaskRunning(){
  return isRunning(status.MAINTENANCE_TASK_STATE) || isRunning(status.APP_OPT_TASK_STATE);
}

function invalidateAppList(){
  appListLoaded = false;
  appListGeneration++;
}

async function refreshStatus(){
  if(statusRefresh) return statusRefresh;
  const generation = visibilityGeneration;
  statusRefresh = (async () => {
    status = parseEnv(await sh(`sh '${CTL}' status-quiet`));
    const identity = [status.BOOT_ID, status.VERSION, status.BUILD_INCREMENTAL].join('|');
    if(identity !== appListIdentity){ invalidateAppList(); appListIdentity = identity; }
    status.BLOCK_AUDITED_LIST = await resolveStorageValue();
    await resolveThermalAddon();
    if(!document.hidden && generation === visibilityGeneration) renderStatus();
    return status;
  })();
  try { return await statusRefresh; }
  finally { statusRefresh = null; }
}

async function loadLog(name=currentLog){
  const request = ++logRequest;
  currentLog = name;
  $$('.logBtn').forEach(b => b.classList.toggle('active', b.dataset.log === name));
  $('#logBox').textContent = 'Loading log…';
  try {
    const out = await sh(`cat '${MODDIR}/${name}' 2>/dev/null || echo 'No ${name} found.'`);
    if(request !== logRequest) return;
    $('#logBox').textContent = out.trim() || `${name} is empty.`;
  } catch(e){
    if(request !== logRequest) return;
    $('#logBox').textContent = `Could not read ${name}:\n${e.message}`;
  }
}

async function loadSnapshot(){
  $('#snapshotBox').textContent = 'Loading snapshot…';
  try {
    const out = await sh(`cat '${MODDIR}/support_snapshot.txt' 2>/dev/null || echo 'No support snapshot found.'`);
    $('#snapshotBox').textContent = out.trim() || 'No support snapshot is available yet.';
  } catch(e){
    $('#snapshotBox').textContent = `Could not load support snapshot:\n${e.message}`;
  }
}

async function copyText(text, button){
  let copied = false;
  try {
    if(navigator.clipboard?.writeText){
      await navigator.clipboard.writeText(text);
      copied = true;
    }
  } catch (_) {}

  if(!copied){
    try {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.setAttribute('readonly','');
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      copied = document.execCommand('copy');
      document.body.removeChild(ta);
    } catch (_) {}
  }

  if(button){
    // Only snapshot the label when no feedback is pending, so a second click cannot capture 'Copied' as the real one.
    if(button.copyTimer) clearTimeout(button.copyTimer);
    else button.copyLabel = button.textContent;
    button.textContent = copied ? 'Copied' : 'Copy failed';
    button.copyTimer = setTimeout(() => { button.textContent = button.copyLabel; button.copyTimer = null; }, 1400);
  }
  try { toast(copied ? 'Copied' : 'Copy failed'); } catch (_) {}
}

function shellQuote(value){ return "'" + String(value).replace(/'/g, "'\\''") + "'"; }

function parseAppLine(line){
  const raw = String(line || '').trim();
  if(!raw) return null;
  if(raw.includes('|')){
    const [type, ...rest] = raw.split('|');
    const pkg = rest.join('|').trim();
    return pkg ? {type:type.trim() || 'app', pkg} : null;
  }
  return {type:'app', pkg:raw};
}

function renderAppList(filter=''){
  const select = $('#appSelect');
  if(!select) return;

  const q = String(filter || '').trim().toLowerCase();
  const filtered = q ? appEntries.filter(entry => `${entry.type} ${entry.pkg}`.toLowerCase().includes(q)) : appEntries;
  const selected = select.value;
  select.innerHTML = '';
  appSelectionAvailable = filtered.length > 0;
  updateOptimizeSelectedButton();

  if(!filtered.length){
    const opt = document.createElement('option');
    opt.value = '';
    opt.textContent = appEntries.length ? 'No matching apps' : 'No apps available';
    select.appendChild(opt);
    select.value = '';
    return;
  }

  for(const entry of filtered){
    const opt = document.createElement('option');
    opt.value = entry.pkg;
    opt.textContent = `${appTypeLabel(entry.type)} · ${entry.pkg}`;
    select.appendChild(opt);
  }
  select.value = filtered.some(entry => entry.pkg === selected) ? selected : filtered[0].pkg;
}

function showAppSelectMessage(message){
  const select = $('#appSelect');
  if(!select) return;
  select.innerHTML = '';
  const opt = document.createElement('option');
  opt.value = '';
  opt.textContent = message;
  select.appendChild(opt);
  appSelectionAvailable = false;
  updateOptimizeSelectedButton();
  select.value = '';
}

async function loadAppList({force=false}={}){
  const generation = appListGeneration;
  if(appListRequest){
    await appListRequest;
    if(generation !== appListGeneration && !document.hidden) return loadAppList();
    return;
  }
  if(!force && appListLoaded && Date.now() - appListFetchedAt < APP_LIST_TTL_MS){
    renderAppList($('#appSearch')?.value || '');
    return;
  }
  showAppSelectMessage('Loading app list…');
  const refreshButton = $('#refreshAppsBtn');
  if(refreshButton) refreshButton.disabled = true;
  appListRequest = (async () => {
    try {
      const out = await sh(`sh '${CTL}' list-apps`);
      if(generation !== appListGeneration) return;
      appEntries = out.split(/\r?\n/).map(parseAppLine).filter(Boolean);
      appListLoaded = true;
      appListFetchedAt = Date.now();
      renderAppList($('#appSearch')?.value || '');
      if(!commandBusy){
        const userCount = appEntries.filter(x => x.type === 'user').length;
        const systemCount = appEntries.filter(x => x.type === 'system').length;
        $('#optimizationBox').textContent = appEntries.length ? `App list ready.\nUser apps: ${userCount}\nSafe system apps: ${systemCount}` : 'Android did not report any apps for optimization.';
      }
    } catch(e){
      if(generation !== appListGeneration) return;
      appListLoaded = false;
      appEntries = [];
      showAppSelectMessage('App list unavailable');
      if(!commandBusy) $('#optimizationBox').textContent = `Could not refresh app list:\n${e.message}`;
    } finally {
      if(refreshButton) refreshButton.disabled = commandBusy || !statusReady;
    }
  })();
  try { await appListRequest; }
  finally { appListRequest = null; }
  if(generation !== appListGeneration && !document.hidden) return loadAppList();
}

async function readTaskProgress(kind){
  const command = kind === 'app' ? 'app-opt-progress' : 'maintenance-progress';
  const out = (await sh(`sh '${CTL}' ${command}`)).replace(/\r\n/g, '\n');
  const separator = '\n__SUPERCHARGER_LOG__\n';
  const boundary = out.indexOf(separator);
  if(boundary < 0) throw new Error('Invalid task progress response');
  const state = parseEnv(out.slice(0, boundary));
  if(!['idle', 'running', 'done', 'failed', 'interrupted'].includes(state.STATE)) throw new Error('Task state unavailable');
  return {state, log:out.slice(boundary + separator.length)};
}

function stopTimer(kind){
  const poller = taskPollers[kind];
  if(poller.timer !== null) clearInterval(poller.timer);
  poller.timer = null;
  poller.generation++;
}

function startTaskPolling(kind, label){
  stopTimer(kind);
  const poller = taskPollers[kind];
  setActionsBusy(true);
  if(document.hidden){ poller.needsRefresh = true; return; }
  const box = kind === 'app' ? '#optimizationBox' : '#maintenanceBox';
  const field = kind === 'app' ? 'APP_OPT_TASK_STATE' : 'MAINTENANCE_TASK_STATE';
  let generation = poller.generation;
  showHeaderTask(label);
  const poll = async () => {
    if(document.hidden || poller.inFlight || generation !== poller.generation) return;
    poller.inFlight = true;
    try {
      const progress = await readTaskProgress(kind);
      if(document.hidden || generation !== poller.generation) return;
      const state = progress.state.STATE;
      const job = progress.state.LABEL || label;
      status[field] = state;
      $(box).textContent = `${job}\nStatus: ${stateLabel(state)}\n\n${progress.log.trim() || 'Waiting for live output…'}`;
      if(isRunning(state)){ showHeaderTask(job); return; }
      stopTimer(kind);
      generation = poller.generation;
      await refreshStatus();
      if(document.hidden || generation !== poller.generation) return;
      setActionsBusy(anyTaskRunning());
      resumeActiveTaskPolling();
    } catch(e){
      if(document.hidden || generation !== poller.generation) return;
      stopTimer(kind);
      setActionsBusy(false);
      $(box).textContent = `Could not read task progress:\n${e.message}`;
    } finally { poller.inFlight = false; }
  };
  poller.timer = setInterval(poll, TASK_POLL_MS);
  poll();
}

function startOptimizationPolling(label){ startTaskPolling('app', label); }
function startMaintenancePolling(label){ startTaskPolling('maintenance', label); }

async function runOptimization(label, startCmd){
  if(commandBusy) return;
  setCommandPending(true);
  showHeaderTask(label);
  $('#optimizationBox').textContent = 'Starting task…';
  try {
    const out = await sh(startCmd);
    $('#optimizationBox').textContent = out.trim() || 'Started. Watching progress…';
    startOptimizationPolling(label);
  } catch(e){
    setActionsBusy(false);
    await refreshStatus().catch(() => {});
    $('#optimizationBox').textContent = `Could not start optimization:\n${e.message}`;
  } finally {
    setCommandPending(false);
  }
}

async function runMaintenance(label, startCmd){
  if(commandBusy) return;
  setCommandPending(true);
  showHeaderTask(label);
  $('#maintenanceBox').textContent = 'Starting maintenance…';
  try {
    const out = await sh(startCmd);
    $('#maintenanceBox').textContent = out.trim() || 'Started. Watching progress…';
    startMaintenancePolling(label);
  } catch(e){
    setActionsBusy(false);
    await refreshStatus().catch(() => {});
    $('#maintenanceBox').textContent = `Could not start maintenance:\n${e.message}`;
  } finally {
    setCommandPending(false);
  }
}

async function setProfile(profile){
  if(commandBusy) return;
  setCommandPending(true);
  $('#profileBox').textContent = 'Saving profile selection…';
  try {
    const out = await sh(`sh '${CTL}' set-profile ${shellQuote(profile)}`);
    $('#profileBox').textContent = out.trim() || 'Profile saved. Restart before judging performance.';
    await refreshStatus();
  } catch(e){
    $('#profileBox').textContent = `Could not update profile:\n${e.message}`;
  } finally {
    setCommandPending(false);
  }
}

async function runThermal(command, label){
  if(commandBusy) return;
  setCommandPending(true);
  $('#thermalBox').textContent = `${label}…`;
  try {
    const out = await sh(`sh '${CTL}' ${command}`);
    $('#thermalBox').textContent = out.trim() || 'Thermal setting saved. Restart to apply it fully.';
    await refreshStatus();
  } catch(e){
    $('#thermalBox').textContent = `Could not update Thermal Control:\n${e.message}`;
  } finally {
    setCommandPending(false);
  }
}

function setThermalProfile(profile){
  const command = thermalEnabled() ? `thermal-set-profile ${shellQuote(profile)}` : `thermal-enable ${shellQuote(profile)}`;
  runThermal(command, `Applying ${thermalLabel(profile)}`);
}

function resumeActiveTaskPolling(){
  if(!document.hidden && !taskPollers.app.timer && isRunning(status.APP_OPT_TASK_STATE)) startOptimizationPolling(status.APP_OPT_TASK_LABEL || 'App optimization');
  if(!document.hidden && !taskPollers.maintenance.timer && isRunning(status.MAINTENANCE_TASK_STATE)) startMaintenancePolling(status.MAINTENANCE_TASK_LABEL || 'One-tap maintenance');
}

document.addEventListener('visibilitychange', async () => {
  const generation = ++visibilityGeneration;
  if(document.hidden){
    Object.values(taskPollers).forEach(p => { p.needsRefresh ||= p.timer !== null || p.inFlight; });
  }
  stopTimer('app');
  stopTimer('maintenance');
  if(document.hidden) return;
  invalidateAppList();
  try {
    if(statusRefresh) await statusRefresh.catch(() => {});
    if(document.hidden || generation !== visibilityGeneration) return;
    await refreshStatus();
    if(document.hidden || generation !== visibilityGeneration) return;
    statusReady = true;
    setActionsBusy(anyTaskRunning());
    for(const [kind, poller] of Object.entries(taskPollers)){
      if(poller.needsRefresh){
        poller.needsRefresh = false;
        startTaskPolling(kind, kind === 'app' ? 'App optimization' : 'One-tap maintenance');
      }
    }
    resumeActiveTaskPolling();
    if($('#maintenance')?.classList.contains('active')) await loadAppList();
  } catch(e){
    if(document.hidden || generation !== visibilityGeneration) return;
    statusReady = false;
    setActionsBusy(false);
    setText('#statusValue', 'Unavailable');
    setText('#statusSub', e.message);
  }
});

$$('.tab').forEach(btn => btn.addEventListener('click', async () => {
  $$('.tab').forEach(b => b.classList.remove('active'));
  $$('.section').forEach(s => s.classList.remove('active'));
  btn.classList.add('active');
  $(`#${btn.dataset.tab}`).classList.add('active');
  if(btn.dataset.tab === 'logs') await loadLog(currentLog);
  if(btn.dataset.tab === 'maintenance') await loadAppList();
}));

$$('.logBtn').forEach(btn => btn.addEventListener('click', () => loadLog(btn.dataset.log)));
$('#copyLogBtn')?.addEventListener('click', () => copyText($('#logBox').textContent || '', $('#copyLogBtn')));
$('#maintenanceAllBtn')?.addEventListener('click', () => runMaintenance('One-tap maintenance', `sh '${CTL}' maintenance-all-async`));
$('#refreshAppsBtn')?.addEventListener('click', () => loadAppList({force:true}));
$('#appSearch')?.addEventListener('input', () => renderAppList($('#appSearch').value));
$('#optimizeAllBtn')?.addEventListener('click', () => runOptimization('Optimizing app list', `sh '${CTL}' optimize-apps-async`));
$('#optimizeSystemBtn')?.addEventListener('click', () => runOptimization('Optimizing safe system apps', `sh '${CTL}' optimize-system-apps-async`));
$('#dexoptJobBtn')?.addEventListener('click', () => runOptimization('System dexopt', `sh '${CTL}' dexopt-job-async`));
$('#optimizeSelectedBtn')?.addEventListener('click', () => {
  const pkg = $('#appSelect').value;
  if(!pkg){ $('#optimizationBox').textContent = 'Choose an app first.'; return; }
  runOptimization(`Optimizing ${pkg}`, `sh '${CTL}' optimize-app-async ${shellQuote(pkg)}`);
});
$('#recompileSelectedBtn')?.addEventListener('click', () => {
  const pkg = $('#appSelect').value;
  if(!pkg) return;
  runOptimization(`Recompiling ${pkg}`, `sh '${CTL}' optimize-app-force-async ${shellQuote(pkg)}`);
});
$('#setActiveSmoothBtn')?.addEventListener('click', () => setProfile('active_smooth'));
$('#setGamingBtn')?.addEventListener('click', () => setProfile('performance_gaming'));
$('#thermalEnableBtn')?.addEventListener('click', () => runThermal('thermal-enable', 'Turning Thermal Control on'));
$('#thermalDisableBtn')?.addEventListener('click', () => runThermal('thermal-disable', 'Turning Thermal Control off'));
$('#thermalBalancedBtn')?.addEventListener('click', () => setThermalProfile('balanced'));
$('#thermalGamingBtn')?.addEventListener('click', () => setThermalProfile('gaming'));
$('#thermalChargeCoolBtn')?.addEventListener('click', () => setThermalProfile('charge_cool'));
$('#loadSnapshotBtn')?.addEventListener('click', loadSnapshot);
$('#copySnapshotBtn')?.addEventListener('click', () => copyText($('#snapshotBox').textContent || '', $('#copySnapshotBtn')));

setActionsBusy(false);
refreshStatus()
  .then(() => {
    statusReady = true;
    setActionsBusy(false);
    resumeActiveTaskPolling();
  })
  .catch(e => {
    statusReady = false;
    setActionsBusy(false);
    setText('#statusValue', 'Unavailable');
    setText('#statusSub', e.message || 'Could not read module status');
  });
