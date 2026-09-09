import { checkRequirements, hashZip, matchesRelease, buildIssueDraft } from './tools-core.mjs';

const es = document.documentElement.lang === 'es';
const t = (en, spanish) => es ? spanish : en;
const copyTimers = new WeakMap();
const copyRequests = new WeakMap();
let statusTimer;
document.querySelectorAll('[data-copy]').forEach(button => {
  const label = button.textContent;
  button.addEventListener('click', async () => {
    const request = (copyRequests.get(button) ?? 0) + 1;
    copyRequests.set(button, request);
    const source = document.getElementById(button.dataset.copy);
    const text = 'value' in source ? source.value : source.textContent;
    const status = document.getElementById('copy-status');
    clearTimeout(copyTimers.get(button));
    try {
      await navigator.clipboard.writeText(text);
      if (copyRequests.get(button) !== request) return;
      button.textContent = t('Copied', 'Copiado');
      status.textContent = t('Copied to clipboard.', 'Copiado al portapapeles.');
    } catch {
      if (copyRequests.get(button) !== request) return;
      if ('select' in source) source.select();
      else {
        const range = document.createRange(); range.selectNodeContents(source);
        const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
      }
      status.textContent = t('Select and copy the highlighted text manually.', 'Copia manualmente el texto seleccionado.');
    }
    clearTimeout(copyTimers.get(button));
    copyTimers.set(button, setTimeout(() => { button.textContent = label; }, 2000));
    clearTimeout(statusTimer);
    statusTimer = setTimeout(() => { status.textContent = ''; }, 6000);
  });
});

const requirements = document.getElementById('requirements-form');
if (requirements) {
  const messages = {
    device: t('Choose one of the four supported Pixel 9 models.', 'Elige uno de los cuatro modelos Pixel 9 compatibles.'),
    android: t('Android 16 QPR3+ or Android 17 is required.', 'Se requiere Android 16 QPR3+ o Android 17.'),
    root: t('Magisk, KernelSU, or APatch must be installed.', 'Debes tener instalado Magisk, KernelSU o APatch.'),
    bootloader: t('Confirm that the bootloader is unlocked.', 'Confirma que el bootloader está desbloqueado.'),
    webui: t('A manager or companion app with module WebUI support is required.', 'Necesitas un gestor o una aplicación complementaria compatible con WebUI.'),
    magiskVersion: t('Confirm Magisk 30.7 or newer using a version such as 30.7.', 'Confirma Magisk 30.7 o posterior con un número de versión como 30.7.'),
    managerVersion: t('Confirm your root manager version to check overlay requirements.', 'Confirma la versión del gestor de root para revisar los requisitos de montaje.'),
    overlay: t('Thermal Control on KernelSU / APatch 3.x needs an overlay-capable metamodule. It is optional when Thermal Control stays off.', 'Thermal Control en KernelSU / APatch 3.x requiere un metamódulo de montaje. Es opcional si Thermal Control permanece desactivado.'),
    thermal: t('Choose whether you intend to use Thermal Control.', 'Elige si quieres utilizar Thermal Control.'),
  };
  const result = document.getElementById('requirements-result');
  requirements.addEventListener('submit', event => {
    event.preventDefault();
    const outcome = checkRequirements(Object.fromEntries(new FormData(requirements)));
    result.replaceChildren();
    const title = document.createElement('strong');
    title.textContent = outcome.status === 'ready' ? t('Declared requirements match.', 'Los datos cumplen los requisitos declarados.') : outcome.status === 'blocked' ? t('Requirements are not met.', 'No se cumplen los requisitos.') : t('Some requirements need confirmation.', 'Hay requisitos pendientes de confirmar.');
    result.append(title);
    if (outcome.codes.length) {
      const list = document.createElement('ul');
      outcome.codes.forEach(code => { const item = document.createElement('li'); item.textContent = messages[code]; list.append(item); });
      result.append(list);
    }
    const note = document.createElement('p');
    note.textContent = t('This checks your answers, not your phone. It does not verify the build, root state, or boot behavior.', 'Se revisan tus respuestas, no el teléfono. No se verifica la compilación, el estado de root ni el arranque.');
    result.append(note); result.hidden = false; result.dataset.state = outcome.status; result.focus();
  });
  requirements.addEventListener('change', () => { result.hidden = true; });
}

const verifier = document.getElementById('zip-form');
if (verifier) {
  const metadata = JSON.parse(document.getElementById('release-data').textContent);
  const input = document.getElementById('zip-file');
  const result = document.getElementById('zip-result');
  const button = verifier.querySelector('button[type="submit"]');
  let revision = 0;
  input.addEventListener('change', () => { revision++; result.textContent = ''; result.hidden = true; button.disabled = false; });
  verifier.addEventListener('submit', async event => {
    event.preventDefault();
    const current = ++revision;
    result.hidden = false; result.dataset.state = 'review';
    result.textContent = t('Calculating SHA-256 locally…', 'Calculando SHA-256 localmente…');
    button.disabled = true;
    try {
      const hash = await hashZip(input.files[0]);
      if (current !== revision) return;
      const match = matchesRelease(hash, metadata);
      result.replaceChildren();
      const title = document.createElement('strong');
      title.textContent = match ? t(`Matches the published ${metadata.tag} checksum.`, `Coincide con el checksum publicado de ${metadata.tag}.`) : t(`Does not match ${metadata.tag}. Do not install it as this release.`, `No coincide con ${metadata.tag}. No lo instales como esta versión.`);
      const code = document.createElement('code'); code.className = 'hash-value'; code.textContent = hash;
      const note = document.createElement('p');
      note.textContent = t('A matching hash confirms file integrity, not device compatibility.', 'Un hash coincidente confirma la integridad del archivo, no la compatibilidad del dispositivo.');
      result.append(title, code, note); result.dataset.state = match ? 'ready' : 'blocked';
    } catch (error) {
      if (current !== revision) return;
      const errors = {
        zipType: t('Select a ZIP file.', 'Selecciona un archivo ZIP.'),
        zipSize: t('Select a non-empty ZIP up to 128 MiB.', 'Selecciona un ZIP no vacío de hasta 128 MiB.'),
        cryptoUnavailable: t('Hashing requires HTTPS and a browser with Web Crypto. Use the manual commands in the guide.', 'El cálculo requiere HTTPS y un navegador con Web Crypto. Usa los comandos manuales de la guía.'),
        metadata: t('The expected checksum is unavailable. Use the official SHA-256 file.', 'El checksum esperado no está disponible. Usa el archivo SHA-256 oficial.'),
      };
      result.textContent = errors[error.message] ?? t('The file could not be read. Select it again and retry.', 'No se pudo leer el archivo. Vuelve a seleccionarlo e inténtalo de nuevo.');
      result.dataset.state = 'blocked';
    } finally { if (current === revision) button.disabled = false; }
  });
}

const report = document.getElementById('report-form');
if (report) {
  const output = document.getElementById('report-output');
  report.addEventListener('input', () => { output.hidden = true; });
  report.addEventListener('submit', event => {
    event.preventDefault();
    const draft = buildIssueDraft(Object.fromEntries(new FormData(report)));
    document.getElementById('report-draft').value = draft.markdown;
    document.getElementById('report-github').href = draft.url;
    document.getElementById('report-prefill').textContent = draft.prefilled ? t('Review the draft. GitHub will ask you to confirm the remaining fields and attach a support snapshot.', 'Revisa el borrador. GitHub te pedirá confirmar los campos restantes y adjuntar un diagnóstico de soporte.') : t('This report is too long to prefill. Copy it and paste the details into the GitHub form.', 'El informe es demasiado largo para rellenarlo por URL. Cópialo y pega los detalles en el formulario de GitHub.');
    output.hidden = false; document.getElementById('report-draft').focus();
  });
}

// Forms remain disabled if the module fails to load or JavaScript is off, so
// their default GET submission cannot put a report into a URL accidentally.
document.querySelectorAll('fieldset[data-enhanced]').forEach(fieldset => { fieldset.disabled = false; });
document.getElementById('tools-loading')?.setAttribute('hidden', '');
