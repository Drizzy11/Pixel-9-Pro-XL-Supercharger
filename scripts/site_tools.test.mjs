import assert from 'node:assert/strict';
import test from 'node:test';
import { webcrypto } from 'node:crypto';
import { DEVICES, MAX_ZIP_BYTES, compareVersion, checkRequirements, hashZip, matchesRelease, buildIssueDraft } from '../site/tools-core.mjs';

const ready = { device: 'tokay', android: '16-qpr3', root: 'magisk', version: '30.7', bootloader: 'yes', webui: 'yes', thermal: 'off', overlay: 'unknown' };
test('all four supported Pixel models match declared requirements', () => {
  for (const device of Object.keys(DEVICES)) assert.equal(checkRequirements({ ...ready, device }).status, 'ready');
  assert.equal(checkRequirements({ ...ready, android: '17' }).status, 'ready');
});
test('missing or uncertain answers never become a compatibility approval', () => {
  assert.equal(checkRequirements({}).status, 'review');
  for (const key of ['device', 'android', 'root', 'bootloader', 'webui', 'thermal']) {
    assert.notEqual(checkRequirements({ ...ready, [key]: 'unknown' }).status, 'ready', key);
  }
});
test('unsupported devices, Android versions, missing root, and locked bootloaders are blocked', () => {
  for (const changes of [{ device: 'other' }, { android: 'other' }, { root: 'none' }, { bootloader: 'no' }, { webui: 'no' }, { version: '30.6' }]) {
    assert.equal(checkRequirements({ ...ready, ...changes }).status, 'blocked');
  }
});
test('Magisk versions use numeric components and ambiguous versions require review', () => {
  assert.equal(compareVersion('30.10', '30.7'), 1);
  assert.equal(compareVersion('30.7.0', '30.7'), 0);
  for (const version of ['', '30700', '30.7-beta', 'NaN']) assert.equal(checkRequirements({ ...ready, version }).status, 'review');
});
test('metamodules are conditional on requested Thermal Control and manager version', () => {
  for (const root of ['kernelsu', 'apatch']) {
    const base = { ...ready, root, version: '3.0', overlay: 'no' };
    assert.equal(checkRequirements(base).status, 'ready');
    assert.equal(checkRequirements({ ...base, thermal: 'on' }).status, 'review');
    assert.equal(checkRequirements({ ...base, thermal: 'on', overlay: 'yes' }).status, 'ready');
    assert.equal(checkRequirements({ ...base, thermal: 'on', version: '' }).status, 'review');
    assert.equal(checkRequirements({ ...base, thermal: 'on', version: '2.0' }).status, 'ready');
  }
});
test('ZIP verification computes the standard SHA-256 digest locally', async () => {
  const file = { name: 'sample.zip', size: 3, arrayBuffer: async () => new TextEncoder().encode('abc').buffer };
  assert.equal(await hashZip(file, webcrypto), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
});
test('invalid or oversized files are rejected before reading them', async () => {
  for (const [name, size, message] of [['sample.txt', 3, 'zipType'], ['sample.zip', 0, 'zipSize'], ['sample.zip', MAX_ZIP_BYTES + 1, 'zipSize']]) {
    let read = false;
    await assert.rejects(hashZip({ name, size, arrayBuffer: async () => { read = true; } }, webcrypto), new RegExp(message));
    assert.equal(read, false);
  }
});
test('unsupported Web Crypto has a manual-verification fallback error', async () => {
  await assert.rejects(hashZip({ name: 'sample.zip', size: 3 }, {}), /cryptoUnavailable/);
});
test('digest comparison distinguishes mismatch from invalid metadata', () => {
  assert.equal(matchesRelease('A'.repeat(64), { sha256: 'a'.repeat(64) }), true);
  assert.equal(matchesRelease('b'.repeat(64), { sha256: 'a'.repeat(64) }), false);
  assert.throws(() => matchesRelease('a'.repeat(64), {}), /metadata/);
});
test('issue drafts use the existing GitHub issue form and preserve user text', () => {
  const draft = buildIssueDraft({ title: 'WebUI & profiles', version: 'v2.6.7', device: 'comet', build: 'Build123', root: 'Magisk 30.7', profile: 'Active Smooth', thermal: 'Off (default)', description: '<script>alert(1)</script> + detalles', steps: '1. Reboot\n2. Open WebUI' });
  const url = new URL(draft.url);
  assert.equal(url.origin, 'https://github.com');
  assert.equal(url.pathname, '/Drizzy07x/Supercharger_Pixel_9_Series/issues/new');
  assert.equal(url.searchParams.get('template'), 'bug_report.yml');
  assert.equal(url.searchParams.get('device'), 'Pixel 9 Pro Fold (comet)');
  assert.equal(url.searchParams.get('what_happened'), '<script>alert(1)</script> + detalles');
  assert.match(draft.markdown, /1\. Reboot\n2\. Open WebUI/);
  assert.equal(draft.prefilled, true);
});
test('long reports retain their full draft while avoiding an oversized GitHub URL', () => {
  const description = '漢'.repeat(2400);
  const draft = buildIssueDraft({ title: 'Long report', description });
  assert.equal(draft.prefilled, false);
  assert.ok(draft.url.length < 7000);
  assert.ok(draft.markdown.includes(description));
});
