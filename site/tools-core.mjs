export const DEVICES = { tokay: 'Pixel 9 (tokay)', caiman: 'Pixel 9 Pro (caiman)', komodo: 'Pixel 9 Pro XL (komodo)', comet: 'Pixel 9 Pro Fold (comet)' };
export const REPOSITORY = 'https://github.com/Drizzy07x/Supercharger_Pixel_9_Series';
export const MAX_ZIP_BYTES = 128 * 1024 * 1024;

export function compareVersion(value, minimum) {
  if (!/^\d+\.\d+(?:\.\d+)?$/.test(value.trim())) return null;
  const a = value.trim().split('.').map(Number), b = minimum.split('.').map(Number);
  if (a.some(part => !Number.isSafeInteger(part))) return null;
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    if ((a[i] ?? 0) !== (b[i] ?? 0)) return (a[i] ?? 0) > (b[i] ?? 0) ? 1 : -1;
  }
  return 0;
}

export function checkRequirements(input) {
  const blocked = [], review = [];
  if (!Object.hasOwn(DEVICES, input.device)) (input.device === 'other' ? blocked : review).push('device');
  if (!['16-qpr3', '17'].includes(input.android)) (input.android === 'other' ? blocked : review).push('android');
  if (!['magisk', 'kernelsu', 'apatch'].includes(input.root)) (input.root === 'none' ? blocked : review).push('root');
  if (input.bootloader !== 'yes') (input.bootloader === 'no' ? blocked : review).push('bootloader');
  if (input.webui !== 'yes') (input.webui === 'no' ? blocked : review).push('webui');
  if (input.root === 'magisk') {
    const comparison = compareVersion(input.version ?? '', '30.7');
    if (comparison === null) review.push('magiskVersion');
    else if (comparison < 0) blocked.push('magiskVersion');
  }
  if (input.thermal === 'on' && ['kernelsu', 'apatch'].includes(input.root)) {
    const version = compareVersion(input.version ?? '', '3.0');
    if (version === null) review.push('managerVersion');
    if ((version === null || version >= 0) && input.overlay !== 'yes') review.push('overlay');
  }
  if (!['off', 'on'].includes(input.thermal)) review.push('thermal');
  return { status: blocked.length ? 'blocked' : review.length ? 'review' : 'ready', codes: [...new Set([...blocked, ...review])] };
}

export async function hashZip(file, cryptoProvider = globalThis.crypto) {
  if (!file || !/\.zip$/i.test(file.name)) throw new Error('zipType');
  if (!Number.isSafeInteger(file.size) || file.size <= 0 || file.size > MAX_ZIP_BYTES) throw new Error('zipSize');
  if (!cryptoProvider?.subtle) throw new Error('cryptoUnavailable');
  const digest = await cryptoProvider.subtle.digest('SHA-256', await file.arrayBuffer());
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
}

export function matchesRelease(hash, release) {
  if (!/^[a-f0-9]{64}$/i.test(hash) || !/^[a-f0-9]{64}$/i.test(release?.sha256 ?? '')) throw new Error('metadata');
  return hash.toLowerCase() === release.sha256.toLowerCase();
}

export function buildIssueDraft(input) {
  const line = value => String(value ?? '').replace(/[\r\n\x00-\x1f]/g, ' ').trim();
  const title = `[Bug]: ${line(input.title).slice(0, 110)}`;
  const fields = {
    module_version: line(input.version), device: DEVICES[input.device] ?? line(input.device),
    build: line(input.build), root: line(input.root), profile: line(input.profile), thermal: line(input.thermal),
    what_happened: String(input.description ?? '').trim(), steps: String(input.steps ?? '').trim(),
  };
  const markdown = `${title}\n\n## Environment\n- Module: ${fields.module_version}\n- Device: ${fields.device}\n- Android build: ${fields.build}\n- Root: ${fields.root}\n- Profile: ${fields.profile}\n- Thermal Control: ${fields.thermal}\n\n## What happened / expected behavior\n${fields.what_happened}\n\n## Steps to reproduce\n${fields.steps}\n\n## Support snapshot\nAttach the reviewed support snapshot in GitHub.\n`;
  const params = new URLSearchParams({ template: 'bug_report.yml', title, ...fields });
  let url = `${REPOSITORY}/issues/new?${params}`;
  const prefilled = url.length <= 7000;
  if (!prefilled) url = `${REPOSITORY}/issues/new?${new URLSearchParams({ template: 'bug_report.yml', title })}`;
  return { markdown, url, prefilled };
}
