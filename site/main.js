// Progressive enhancement: every preview stays readable when JavaScript is off.
const controls = document.querySelector('.preview-controls');
const gallery = document.querySelector('.preview-gallery');
const tabs = Array.from(controls.querySelectorAll('[role="tab"]'));
const panels = tabs.map(tab => document.getElementById(tab.getAttribute('aria-controls')));

function selectPreview(index, focus = false) {
  tabs.forEach((tab, i) => {
    const selected = i === index;
    tab.setAttribute('aria-selected', String(selected));
    tab.tabIndex = selected ? 0 : -1;
    panels[i].hidden = !selected;
  });
  if (focus) tabs[index].focus();
}

tabs.forEach((tab, index) => {
  panels[index].setAttribute('role', 'tabpanel');
  panels[index].setAttribute('aria-labelledby', tab.id);
  panels[index].tabIndex = 0;
  tab.addEventListener('click', () => selectPreview(index));
  tab.addEventListener('keydown', event => {
    let next;
    if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
    if (event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
    if (event.key === 'Home') next = 0;
    if (event.key === 'End') next = tabs.length - 1;
    if (next !== undefined) {
      event.preventDefault();
      selectPreview(next, true);
    }
  });
});
selectPreview(0);
gallery.classList.add('enhanced');
controls.hidden = false;

// Native dialog provides modal focus containment and Escape handling. Without
// dialog support (or JavaScript), preview links still open the original image.
const viewer = document.querySelector('.image-viewer');
const viewerImage = document.getElementById('viewer-image');
const zoom = document.getElementById('viewer-zoom');
const canvas = document.querySelector('.viewer-canvas');
const spanish = document.documentElement?.lang === 'es';
const actualSizeLabel = spanish ? 'Tamaño real' : 'Actual size';
const fitLabel = spanish ? 'Ajustar al ancho' : 'Fit to width';
let previewOpener;

if (typeof viewer.showModal === 'function') {
  document.querySelectorAll('.preview-frame').forEach(link => {
    link.addEventListener('click', event => {
      if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey || event.button !== 0) return;
      event.preventDefault();
      previewOpener = link;
      const source = link.querySelector('img');
      viewerImage.src = link.href;
      viewerImage.alt = source.alt;
      document.getElementById('viewer-title').textContent = link.getAttribute('aria-label').replace(/^(Enlarge |Ampliar )/, '');
      zoom.setAttribute('aria-pressed', 'false');
      zoom.textContent = actualSizeLabel;
      canvas.classList.remove('actual-size');
      document.body.classList.add('viewer-open');
      viewer.showModal();
      canvas.scrollTo(0, 0);
    });
  });
  zoom.addEventListener('click', () => {
    const expanded = canvas.classList.toggle('actual-size');
    zoom.setAttribute('aria-pressed', String(expanded));
    zoom.textContent = expanded ? fitLabel : actualSizeLabel;
    canvas.scrollTo(0, 0);
  });
  viewer.addEventListener('keydown', event => {
    if (event.key !== 'Tab') return;
    const first = viewer.querySelector('.viewer-close');
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      canvas.focus();
    } else if (!event.shiftKey && document.activeElement === canvas) {
      event.preventDefault();
      first.focus();
    }
  });
  viewer.addEventListener('close', () => {
    document.body.classList.remove('viewer-open');
    viewerImage.removeAttribute('src');
    previewOpener?.focus({ preventScroll: true });
  });
}

function openVerificationAnswer(focus = false) {
  const answer = document.getElementById('verify-download');
  answer.open = true;
  answer.scrollIntoView({ block: 'start' });
  if (focus) answer.querySelector('summary').focus({ preventScroll: true });
}

function revealLinkedAnswer() {
  if (location.hash === '#verify-download') openVerificationAnswer();
}
window.addEventListener('hashchange', revealLinkedAnswer);
revealLinkedAnswer();
document.querySelectorAll('a[href="#verify-download"]').forEach(link => {
  link.addEventListener('click', event => {
    if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey || event.button !== 0) return;
    event.preventDefault();
    // A repeated fragment does not fire hashchange. Explicit navigation also
    // moves focus to the revealed answer instead of leaving it at the old link.
    if (location.hash !== '#verify-download') location.hash = '#verify-download';
    openVerificationAnswer(true);
  });
});

// Content stays visible without animation support, JavaScript, or motion.
if ('IntersectionObserver' in window && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('reveal-enter');
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.12 });
  document.querySelectorAll('.features article, .profile-columns article, .compatibility-grid, .install-grid')
    .forEach(element => observer.observe(element));
}
