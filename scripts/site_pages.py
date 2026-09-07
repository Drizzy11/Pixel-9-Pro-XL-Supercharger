"""Bilingual static page templates for the project website."""
from html import escape as e
import json
import re

BASE_URL = 'https://drizzy07x.github.io/Supercharger_Pixel_9_Series/'
REPO = 'https://github.com/Drizzy07x/Supercharger_Pixel_9_Series'


def frame(title, content, lang='en', page='guide.html', description=''):
    es = lang == 'es'
    t = lambda en, spanish: spanish if es else en
    assets = '../' if es else './'
    language = f'../{page}' if es else f'./es/{page}'
    canonical = BASE_URL + ('es/' if es else '') + page
    return f'''<!doctype html>
<html lang="{lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="theme-color" content="#090c12"><title>{e(title)} — Supercharger</title>
<meta name="description" content="{e(description or title, quote=True)}">
<link rel="canonical" href="{canonical}"><link rel="alternate" hreflang="en" href="{BASE_URL}{page}"><link rel="alternate" hreflang="es" href="{BASE_URL}es/{page}">
<link rel="icon" href="{assets}assets/icon.png"><link rel="stylesheet" href="{assets}styles.css"><link rel="stylesheet" href="{assets}pages.css">
<script type="module" src="{assets}site.mjs"></script></head><body>
<a class="skip-link" href="#main">{t('Skip to content','Ir al contenido')}</a>
<header class="header wrap"><a class="brand" href="./index.html"><img src="{assets}assets/icon.png" width="34" height="34" alt="">Supercharger</a>
<nav aria-label="{t('Main navigation','Navegación principal')}"><a href="./guide.html">{t('Guide','Guía')}</a><a href="./tools.html">{t('Tools','Herramientas')}</a><a href="./releases.html">{t('Versions','Versiones')}</a><a href="{REPO}">GitHub</a><a class="language-link" href="{language}" lang="{t('es','en')}" hreflang="{t('es','en')}">{t('Español','English')}</a></nav></header>
<main id="main" class="wrap subpage"><div class="page-heading"><h1>{e(title)}</h1><p>{e(description)}</p></div>{content}</main>
<p id="copy-status" class="copy-status" role="status" aria-live="polite"></p>
<footer class="footer wrap"><a class="brand" href="./index.html">Supercharger</a><nav aria-label="{t('Project resources','Recursos del proyecto')}"><a href="./guide.html">{t('Documentation','Documentación')}</a><a href="./tools.html#report">{t('Report an issue','Informar de un problema')}</a><a href="{REPO}/blob/main/LICENSE">{t('MIT license','Licencia MIT')}</a></nav></footer></body></html>'''


def guide(snapshot, lang):
    t = lambda en, es: es if lang == 'es' else en
    filename = f"Pixel-9-Series-Supercharger-{snapshot['latest']['tag_name']}.zip"
    sections = []
    def section(id, title, html):
        sections.append((id, title, f'<section id="{id}" class="guide-section"><h2>{title}</h2>{html}</section>'))
    section('requirements', t('Before you begin','Antes de empezar'), t(
        '<p>You need a Pixel 9, Pixel 9 Pro, Pixel 9 Pro XL, or Pixel 9 Pro Fold with Android 16 QPR3+ or Android 17, an unlocked bootloader, and Magisk, KernelSU, or APatch. Magisk must be 30.7 or newer. The dashboard needs module WebUI support.</p>',
        '<p>Necesitas un Pixel 9, Pixel 9 Pro, Pixel 9 Pro XL o Pixel 9 Pro Fold con Android 16 QPR3+ o Android 17, el bootloader desbloqueado y Magisk, KernelSU o APatch. Magisk debe ser 30.7 o posterior. El panel requiere compatibilidad con WebUI de módulos.</p>') + f'<p><a href="./tools.html#requirements">{t("Check your declared requirements","Comprobar tus requisitos")}</a></p>')
    section('install', t('Install the module','Instalar el módulo'), t(
        '<p>Download the module ZIP from the latest release. GitHub’s source-code archive is not the installable module.</p><h3>Magisk</h3><ol><li>Open Magisk and go to Modules.</li><li>Choose Install from storage and select the module ZIP.</li><li>Read the installation result and reboot if installation succeeds.</li></ol><h3>KernelSU / APatch</h3><ol><li>Open your root manager and go to Modules.</li><li>Choose Install and select the module ZIP.</li><li>Read the installation result and reboot if installation succeeds.</li></ol><p>If the installer rejects the device, stop and check the reported codename. After rebooting, open Supercharger’s WebUI from your manager or a compatible companion app.</p>',
        '<p>Descarga el ZIP del módulo desde la última versión. El archivo de código fuente de GitHub no es el módulo instalable.</p><h3>Magisk</h3><ol><li>Abre Magisk y entra en Modules (Módulos).</li><li>Elige Install from storage (Instalar desde almacenamiento) y selecciona el ZIP del módulo.</li><li>Lee el resultado de la instalación y reinicia si finalizó correctamente.</li></ol><h3>KernelSU / APatch</h3><ol><li>Abre el gestor de root y entra en Modules (Módulos).</li><li>Elige Install (Instalar) y selecciona el ZIP del módulo.</li><li>Lee el resultado y reinicia si la instalación finalizó correctamente.</li></ol><p>Si el instalador rechaza el dispositivo, detente y revisa el nombre en clave indicado. Después del reinicio, abre el WebUI de Supercharger desde el gestor o una aplicación complementaria compatible.</p>') + f'<p><a class="button primary" href="./index.html#install">{t("Download the module","Descargar el módulo")}</a></p>')
    commands = [('powershell', 'Windows PowerShell', f'Get-FileHash -Algorithm SHA256 .\\{filename}'), ('linux', 'Linux', f'sha256sum -c {filename}.sha256')]
    html = t('<p>Save the ZIP and its matching SHA-256 file in the same folder. Run the appropriate command from that folder. In PowerShell, compare the returned hash with the hash in the SHA-256 file; Linux reports OK when it matches.</p>', '<p>Guarda el ZIP y su archivo SHA-256 en la misma carpeta. Ejecuta el comando correspondiente desde esa carpeta. En PowerShell, compara el hash obtenido con el del archivo SHA-256; Linux indica OK cuando coinciden.</p>')
    for id, title, command in commands:
        html += f'<h3>{title}</h3><div class="command"><pre><code id="{id}">{e(command)}</code></pre><button type="button" data-copy="{id}" aria-label="{t("Copy command for","Copiar comando para")} {title}">{t("Copy","Copiar")}</button></div>'
    html += f'<p><a href="./tools.html#verify">{t("Or verify the ZIP locally in your browser","También puedes verificar el ZIP localmente en el navegador")}</a></p>'
    section('verify', t('Verify the download','Verificar la descarga'), html)
    section('profiles', t('Profiles and Thermal Control','Perfiles y Thermal Control'), t(
        '<p><strong>Active Smooth</strong> is the default daily profile. <strong>Performance / Gaming</strong> is experimental and uses additional GPU tuning where the kernel supports it. Reboot after switching before judging behavior.</p><p>Thermal Control starts off. Confirm a normal boot before enabling it from Profiles, then reboot again. On KernelSU / APatch 3.x, overlays need a metamodule such as meta-overlayfs or meta-magicmount. Supercharger does not install it.</p><p>Balanced pairs with Active Smooth; Gaming pairs with Performance / Gaming. Charge Cool is a manual thermal-only choice. Changing or disabling thermal profiles also requires a reboot.</p>',
        '<p><strong>Active Smooth</strong> es el perfil predeterminado para uso diario. <strong>Performance / Gaming</strong> es experimental y añade ajustes de GPU cuando el kernel los admite. Reinicia después de cambiar de perfil antes de evaluar su comportamiento.</p><p>Thermal Control comienza desactivado. Confirma un arranque normal antes de activarlo desde Profiles y vuelve a reiniciar. En KernelSU / APatch 3.x, los montajes requieren un metamódulo como meta-overlayfs o meta-magicmount. Supercharger no lo instala.</p><p>Balanced se asocia con Active Smooth; Gaming con Performance / Gaming. Charge Cool es una elección térmica manual. Cambiar o desactivar los perfiles térmicos también requiere reiniciar.</p>'))
    section('updates', t('Update or uninstall','Actualizar o desinstalar'), t(
        '<p>Install a newer module ZIP over the existing version and reboot. Selected performance and thermal profiles are preserved. The module also publishes an update feed for compatible managers.</p><p>To uninstall, remove Supercharger from the root manager and reboot. Uninstall removes Supercharger’s persistent state and stops its dashboard updater.</p>',
        '<p>Instala el ZIP de una versión más reciente sobre la existente y reinicia. Se conservan los perfiles de rendimiento y térmicos seleccionados. El módulo también publica un canal de actualizaciones para gestores compatibles.</p><p>Para desinstalar, elimina Supercharger desde el gestor de root y reinicia. La desinstalación elimina su estado persistente y detiene el actualizador del panel.</p>'))
    section('troubleshooting', t('Troubleshooting and support','Solución de problemas y soporte'), t(
        '<h3>The WebUI does not open</h3><p>Confirm that the manager or companion app supports module WebUIs, then reopen the module page.</p><h3>A setting is skipped</h3><p>The kernel may reject a node. Supercharger logs it and leaves the setting unchanged. Check the surrounding log lines before reporting it.</p><h3>Problems after enabling Thermal Control</h3><p>Disable Thermal Control and reboot. If you cannot reach the dashboard, use your root manager’s documented safe mode or recovery process to disable or remove the module.</p><h3>Prepare a support snapshot</h3><ol><li>Open Maintenance and run maintenance.</li><li>Open Support, then load and copy the regenerated snapshot.</li><li>Review the contents before attaching them to a GitHub report.</li></ol><p>The boot report is debug.log; debug.previous.log contains the previous boot report. Dashboard actions are recorded in maintenance.log. These are under /data/adb/modules/p9pxl_supercharger/.</p>',
        '<h3>El WebUI no se abre</h3><p>Confirma que el gestor o la aplicación complementaria admite WebUI de módulos y vuelve a abrir la página del módulo.</p><h3>Se omite un ajuste</h3><p>El kernel puede rechazar un nodo. Supercharger lo registra y deja el ajuste sin modificar. Revisa las líneas cercanas del registro antes de informarlo.</p><h3>Problemas después de activar Thermal Control</h3><p>Desactiva Thermal Control y reinicia. Si no puedes abrir el panel, utiliza el modo seguro o el proceso de recuperación documentado por tu gestor de root para desactivar o eliminar el módulo.</p><h3>Preparar un diagnóstico de soporte</h3><ol><li>Abre Maintenance y ejecuta el mantenimiento.</li><li>Abre Support y carga y copia el diagnóstico regenerado.</li><li>Revisa su contenido antes de adjuntarlo a un informe de GitHub.</li></ol><p>debug.log contiene el informe del arranque y debug.previous.log el del arranque anterior. Las acciones del panel se registran en maintenance.log. Están en /data/adb/modules/p9pxl_supercharger/.</p>') + f'<p><a href="./tools.html#report">{t("Prepare a bug report","Preparar un informe de error")}</a> · <a href="{REPO}/security/policy">{t("Report security issues privately","Informar de problemas de seguridad en privado")}</a></p>')
    sidebar = '<aside class="guide-nav"><nav aria-label="'+t('Guide topics','Temas de la guía')+'">'+''.join(f'<a href="#{id}">{title}</a>' for id,title,_ in sections)+'</nav></aside>'
    content = '<div class="guide-layout">'+sidebar+'<div class="prose">'+''.join(html for _,_,html in sections)+'</div></div>'
    return frame(t('Make yourself at home.','Todo listo para empezar.'), content, lang, 'guide.html', t('A practical guide to installing, using, and troubleshooting Supercharger.', 'Una guía práctica para instalar, usar y resolver problemas con Supercharger.'))


def tools(snapshot, lang):
    t = lambda en, es: es if lang == 'es' else en
    def select(name, title, choices, required=True):
        options = '<option value="">'+t('Select…','Selecciona…')+'</option>' if required else ''
        options += ''.join(f'<option value="{e(value)}">{e(label)}</option>' for value,label in choices)
        return f'<label>{title}<select name="{name}" {"required" if required else ""}>{options}</select></label>'
    def field(name,title,limit=120):
        return f'<label>{title}<input name="{name}" maxlength="{limit}" required></label>'
    devices=[('tokay','Pixel 9'),('caiman','Pixel 9 Pro'),('komodo','Pixel 9 Pro XL'),('comet','Pixel 9 Pro Fold')]
    yesno=[('yes',t('Yes','Sí')),('no','No'),('unknown',t('Not sure','No lo sé'))]
    form=select('device',t('Device','Dispositivo'),devices+[('other',t('Another device','Otro dispositivo'))])
    form+=select('android','Android',[('16-qpr3','Android 16 QPR3+'),('17','Android 17'),('other',t('Another version','Otra versión')),('unknown',t('Not sure','No lo sé'))])
    form+=select('root',t('Root manager','Gestor de root'),[('magisk','Magisk'),('kernelsu','KernelSU'),('apatch','APatch'),('none',t('No root','Sin root'))])
    form+=f'<label>{t("Manager version (for example, 30.7)","Versión del gestor (por ejemplo, 30.7)")}<input name="version" maxlength="30" inputmode="decimal"></label>'
    form+=select('bootloader',t('Bootloader unlocked?','¿Bootloader desbloqueado?'),yesno)
    form+=select('webui',t('Module WebUI support?','¿Compatibilidad con WebUI de módulos?'),yesno)
    form+=select('thermal','Thermal Control',[('off',t('Keep it off (default)','Mantener desactivado (predeterminado)')),('on',t('I want to enable it','Quiero activarlo'))])
    form+=select('overlay',t('Overlay metamodule installed?','¿Metamódulo de montaje instalado?'),[yesno[2],yesno[0],yesno[1]],False)
    content=f'<nav class="tool-nav" aria-label="{t("Tools","Herramientas")}"><a href="#requirements">{t("Requirements","Requisitos")}</a><a href="#verify">{t("Verify ZIP","Verificar ZIP")}</a><a href="#report">{t("Report builder","Preparar informe")}</a></nav>'
    content+=f'<section id="requirements" class="tool-section"><h2>{t("Check your setup.","Comprueba tu configuración.")}</h2><p>{t("Review the declared requirements before installing. This form cannot inspect your phone.","Revisa los requisitos declarados antes de instalar. Este formulario no puede inspeccionar tu teléfono.")}</p><form id="requirements-form"><fieldset class="field-grid" data-enhanced disabled>{form}<button class="button primary" type="submit">{t("Check requirements","Comprobar requisitos")}</button></fieldset></form><div id="requirements-result" class="result" tabindex="-1" role="status" hidden></div></section>'
    tag=snapshot['latest']['tag_name']; filename=f'Pixel-9-Series-Supercharger-{tag}.zip'
    metadata=json.dumps({'tag':tag,'sha256':snapshot['sha256'],'filename':filename}).replace('<','\\u003c')
    content+=f'<section id="verify" class="tool-section"><h2>{t("Know what you downloaded.","Verifica lo que descargaste.")}</h2><p>{t("Compare your ZIP with the published checksum for","Compara tu ZIP con el checksum publicado de")} <strong>{tag}</strong>. {t("The file is processed locally in this browser. Maximum: 128 MiB.","El archivo se procesa localmente en este navegador. Máximo: 128 MiB.")}</p><p><code class="hash-value">{snapshot["sha256"]}</code></p><form id="zip-form"><fieldset data-enhanced disabled><label for="zip-file">{t("Module ZIP","ZIP del módulo")}</label><input type="file" id="zip-file" accept=".zip,application/zip" required><button class="button primary" type="submit">{t("Verify ZIP","Verificar ZIP")}</button></fieldset></form><div id="zip-result" class="result" role="status" aria-live="polite" hidden></div><p><a href="./guide.html#verify">{t("Manual verification commands","Comandos de verificación manual")}</a> · <a href="./index.html#install">{t("Official download","Descarga oficial")}</a></p><script type="application/json" id="release-data">{metadata}</script></section>'
    form=field('title',t('Short issue title','Título breve del problema'))+field('version',t('Installed module version','Versión instalada del módulo'))
    form+=select('device',t('Device','Dispositivo'),devices)+field('build',t('Full Android build','Compilación completa de Android'))+field('root',t('Root manager and version','Gestor de root y versión'))
    form+=select('profile',t('Active profile','Perfil activo'),[('Active Smooth','Active Smooth'),('Performance / Gaming','Performance / Gaming')])
    form+=select('thermal',t('Thermal Control state','Estado de Thermal Control'),[('Off (default)',t('Off (default)','Desactivado (predeterminado)')),('On - Balanced',t('On - Balanced','Activado - Balanced')),('On - Gaming',t('On - Gaming','Activado - Gaming')),('On - Charge Cool',t('On - Charge Cool','Activado - Charge Cool'))])
    form+=f'<label class="full-field">{t("What happened, and what did you expect?","¿Qué ocurrió y qué esperabas?")}<textarea name="description" maxlength="2400" rows="5" required></textarea></label><label class="full-field">{t("Steps to reproduce","Pasos para reproducirlo")}<textarea name="steps" maxlength="1800" rows="4" required></textarea></label>'
    content+=f'<section id="report" class="tool-section"><h2>{t("A useful report starts here.","Un buen informe empieza aquí.")}</h2><p>{t("Prepare a draft for the project’s GitHub issue form. The technical report is generated in English. Review it before opening GitHub.","Prepara un borrador para el formulario de incidencias del proyecto. El informe técnico se genera en inglés. Revísalo antes de abrir GitHub.")}</p><form id="report-form"><fieldset class="field-grid" data-enhanced disabled>{form}<button class="button primary" type="submit">{t("Generate draft","Generar borrador")}</button></fieldset></form><div id="report-output" hidden><label for="report-draft">{t("Review your draft","Revisa tu borrador")}</label><textarea id="report-draft" rows="15" readonly></textarea><p id="report-prefill"></p><div class="actions"><button class="button secondary" type="button" data-copy="report-draft">{t("Copy draft","Copiar borrador")}</button><a id="report-github" class="button primary" target="_blank" rel="noopener noreferrer" href="{REPO}/issues/new?template=bug_report.yml">{t("Open GitHub form","Abrir formulario de GitHub")}</a></div><p><a href="./guide.html#troubleshooting">{t("How to collect a support snapshot","Cómo recopilar un diagnóstico de soporte")}</a></p></div></section>'
    content = f'<p id="tools-loading">{t("Interactive tools require JavaScript. If controls stay disabled, use the guide.","Las herramientas interactivas requieren JavaScript. Si los controles siguen desactivados, utiliza la guía.")} <a href="./guide.html">{t("Open guide","Abrir guía")}</a></p>' + content
    return frame(t('A little help, right here.','Una ayuda, aquí mismo.'),content,lang,'tools.html',t('Check requirements, verify a download, and prepare a clear bug report.','Comprueba requisitos, verifica una descarga y prepara un informe claro.'))


def release_notes(text):
    # Preserve source wording while displaying a deliberately small Markdown
    # subset. All source text is escaped; raw HTML never becomes markup.
    lines=[]; listing=False; code=False
    def plain(value):
        value=re.sub(r'\[([^\]]+)\]\([^)]*\)',r'\1',value)
        return e(value.replace('**','').replace('`',''))
    for line in text.splitlines():
        if line.startswith('```'):
            if listing: lines.append('</ul>'); listing=False
            lines.append('</code></pre>' if code else '<pre><code>'); code=not code; continue
        if code: lines.append(e(line)+'\n'); continue
        if re.match(r'^\s*[-*] ',line):
            if not listing: lines.append('<ul>'); listing=True
            lines.append('<li>'+plain(re.sub(r'^\s*[-*] ','',line))+'</li>'); continue
        if listing: lines.append('</ul>'); listing=False
        if not line.strip(): continue
        heading=re.match(r'^#{1,6}\s+(.+)',line)
        lines.append('<h3>'+plain(heading[1])+'</h3>' if heading else '<p>'+plain(line)+'</p>')
    if listing: lines.append('</ul>')
    if code: lines.append('</code></pre>')
    return ''.join(lines)


def releases(snapshot,lang):
    t=lambda en,es: es if lang=='es' else en
    summaries={
      'v2.6.7':t('Package metadata, manager previews, and installation documentation. No tuning changes.','Metadatos del paquete, vistas previas para gestores y documentación de instalación. Sin cambios de ajustes.'),
      'v2.6.6':t('Task recovery, profile persistence, thermal selection, and atomic status files.','Recuperación de tareas, persistencia de perfiles, selección térmica y archivos de estado atómicos.'),
      'v2.6.5':t('WebUI reliability, state handling, and release consistency checks.','Fiabilidad del WebUI, gestión del estado y comprobaciones de coherencia de versiones.'),
      'v2.6.4':t('Integrated opt-in Thermal Control, profile alignment, and expanded GPU support.','Thermal Control integrado y opcional, coordinación de perfiles y soporte de GPU ampliado.')}
    content=''
    for record in snapshot['history']:
        label=t('Experimental prerelease','Preversión experimental') if record['prerelease'] else t('Stable release','Versión estable')
        content+=f'<article class="release-card" id="{e(record["tag"])}"><div class="release-heading"><h2>{e(record["tag"])}</h2><span>{label} · <time>{record["date"]}</time></span></div>'
        if record['tag'] in summaries: content+='<p>'+summaries[record['tag']]+'</p>'
        if record['notes']:
            content+=f'<details><summary>{t("Read original release notes (English)","Leer notas originales (inglés)")}</summary><div class="release-source prose" lang="en">{release_notes(record["notes"])}</div></details>'
        content+=f'<a href="{e(record["url"],quote=True)}">{t("Release and assets on GitHub","Versión y archivos en GitHub")}</a></article>'
    return frame(t('Every release, in view.','Cada versión, a la vista.'),content,lang,'releases.html',t('Published release history. Original notes retain the project’s wording; drafts are excluded.','Historial de versiones publicadas. Las notas originales conservan el texto del proyecto; se excluyen los borradores.'))


def not_found():
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>Page not found — Supercharger</title><base href="/Supercharger_Pixel_9_Series/"><link rel="stylesheet" href="styles.css"><link rel="stylesheet" href="pages.css"></head><body><main class="wrap not-found"><a class="brand" href="index.html">Supercharger</a><p class="feature-number">404</p><h1>This page took a detour.</h1><p>The address may be outdated. Your next step is right here.</p><div class="actions"><a class="button primary" href="index.html">Home</a><a class="button secondary" href="guide.html">Documentation</a><a class="button secondary" href="index.html#install">Download</a></div><div lang="es"><h2>Esta página no está disponible.</h2><p>La dirección puede haber cambiado.</p><a class="language-link" href="es/index.html">Ir a la web en español</a></div></main></body></html>'''
