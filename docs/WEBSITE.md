# Project website

`site/` is a standalone English/Spanish project website for GitHub Pages. It uses plain
HTML, CSS, and JavaScript, with no package manager, backend, analytics,
remote fonts, or Android bridge. Publishing refreshes the static release metadata
with Python; serving the page does not call the GitHub API. The release packaging
allowlist excludes the website.

## Preview

From the repository root, with Python 3 installed:

```sh
python3 scripts/serve_site.py
```

On Windows, use `python` if that is your Python 3 executable. Open
<http://127.0.0.1:8765>. Ctrl+C stops the server. Use `--port 8766` if needed.
The helper binds only to localhost and explicitly serves WebP as `image/webp`;
Windows MIME registration can otherwise force full-image links to download.

## Publish with GitHub Pages

1. Commit the website and `.github/workflows/pages.yml`, then merge into `main`.
2. In the repository's **Settings > Pages > Build and deployment**, choose
   **GitHub Actions** as the source.
3. In **Actions > Project website**, select **Run workflow** on `main`.
4. Open the URL reported by the successful `github-pages` deployment.

Subsequent changes to `site/`, the release renderer/tests, or the workflow on
`main` deploy automatically. Manual GitHub release events and successful runs of
`Supercharger Auto-Release Engine` also refresh the website. The latter uses
`workflow_run`, since releases created with `GITHUB_TOKEN` do not start ordinary
release-event workflows. Each run checks out `main`, not release-tag source or
artifacts supplied by another workflow.
The workflow uploads only `site/`, with Pages/OIDC permissions limited to the
deployment job. Manual runs from other branches do not deploy.

Before upload, `scripts/update_site_release.py` retrieves the latest stable
release from this repository and replaces only the marked release block in
`site/index.html`. It validates tag, publication state, asset names, sizes and URLs.
A missing ZIP/checksum or API error fails the deployment and leaves the current
published site intact. There is no API credential in the website. The committed
HTML snapshot also works locally and without JavaScript.
The renderer stages changes beside the destination and atomically replaces it,
preserving its file permissions. Partial writes and replacement failures keep
the previous local page intact and clean up the temporary file.

Refresh that snapshot locally with:

```sh
python3 scripts/update_site_release.py
```

`--metadata /path/to/release.json` accepts saved GitHub release API JSON for an
offline refresh. Forks must also change the `REPO` constant in this script.

## Complete bilingual build

For normal development, use the committed public snapshot:

```sh
python3 scripts/build_site.py
python3 scripts/check_site.py
```

For publishing or refreshing release information:

```sh
python3 scripts/build_site.py --refresh
```

The complete build is the publishing entry point. It updates English and Spanish
landing pages, guide, tools, published version history, the bilingual 404 page,
robots.txt and sitemap.xml. It fetches the matching SHA-256 file and stores a
minimal public snapshot at `site/data/releases.json`. Draft releases are filtered
before serialization. Published original release notes retain their English
source wording and are explicitly labelled; the guide, tools and site UI are
available in both languages.

`site/index.html` is the English landing-page source. Translate its visible text
in `scripts/site_translations.es.json`; missing translations fail the build.
Other page templates live in `scripts/site_pages.py`. Do not hand-edit generated
`site/es/*.html`, `guide.html`, `tools.html`, `releases.html` or `404.html`.

Both `.github/workflows/website-check.yml` and the Pages workflow run the standalone
website checks. Pull requests build from the committed snapshot without needing
network credentials; deployment refreshes the public snapshot before checking
and uploading. Only `site/` is uploaded.

## Browser tools

- The requirements checker reviews declared answers against the documented Pixel
  models, Android targets and root/WebUI requirements. It does not inspect a phone
  or guarantee boot behavior. Thermal overlay requirements are conditional.
- The ZIP verifier hashes the selected file locally with Web Crypto and compares
  it with the pinned release checksum. It accepts ZIPs up to 128 MiB; the API reads
  the file into memory. HTTPS (or localhost) is required. Switching files invalidates
  an earlier result. A hash match proves integrity, not hardware compatibility.
- The report builder creates an English technical draft and a prefilled link to
  the existing GitHub issue form. It never submits an issue. Long reports retain
  their full copyable draft and fall back to a short form link. No form state is
  stored by the application. Forms stay disabled until their handlers load, so
  unavailable JavaScript cannot accidentally submit report contents in a GET URL.
- Guide and landing-page verification commands use the actual release filename
  and offer clipboard buttons with manual-selection fallback.

The 404 page uses the project base path so links work even under nested missing
URLs. The preview server supports that prefix and returns the branded page with
HTTP 404. It explicitly serves JavaScript modules, fonts and WebP MIME types.

Expected URL for this repository:
<https://drizzy07x.github.io/Supercharger_Pixel_9_Series/>. This is the configured
destination, not a claim that a deployment has already succeeded.

The workflow follows GitHub's
[custom Pages workflow documentation](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

## Editing and verification

- `index.html`: content, compatibility, links, accessible preview panels, metadata.
- `styles.css`: responsive layout, shared tokens, focus and reduced-motion styles.
- `main.js`: progressive preview tabs, native image dialog with zoom and focus
  restoration, and deep links that open the checksum FAQ answer.
- `assets/`: branding and optimized WebP variants of the illustration/screenshots.
- `scripts/prepare_site_images.py`: reproducible asset generation from
  `docs/branding/lightning-premium.png` and `docs/images/webui-*.png`. Run with Python and
  Pillow with WebP support after changing a source image; it is not needed for
  ordinary preview or deployment. Full screenshot variants use lossless WebP.

Keep navigation and asset paths relative so project subpaths work. If publishing
a fork or custom domain, update the repository links, canonical URL, and Open
Graph URLs in `index.html`.

Verify desktop and narrow mobile layouts, all three preview tabs, arrow-key and
Home/End navigation, skip link, in-page anchors, and the GitHub release links.
The preview viewport and caption reservation keep the following content stable
when switching tabs. Preview frames crop tall screenshots; opening a preview
shows the full image. Check Actual size/Fit to width, image scrolling, Escape,
Close preview, background scroll locking, and focus restoration to the opener.
For the checksum help, close its answer and activate **How to verify** again
without changing the fragment. The answer must reopen and receive keyboard focus.
With JavaScript disabled, all figures and native FAQ disclosures remain usable;
preview links open the full images directly. The download block links to the
version-specific module ZIP, matching checksum, release notes and latest assets.

Run `node --check site/main.js`, `node --test scripts/site_regression.test.mjs`,
and the normal repository checks from `CONTRIBUTING.md`. The shared check command
includes the public website's syntax and event-handler regressions. Do not
execute Android entry scripts to test the website.
The shared Python suite includes `scripts/test_site_release.py`, covering stable
release selection, invalid links, incomplete assets and preservation of previous
HTML on validation, partial-write and replacement failures. The Pages workflow
runs these offline tests plus website JavaScript syntax and interaction checks
before refreshing release data or uploading an artifact.

## Visual assets

The header and footer reuse `docs/branding/icon.png`. Dashboard figures reuse the
existing source-rendered previews, including their sample values. They are
illustrations of the interface, not live telemetry or performance evidence.

The source `docs/branding/lightning.png` was created with the built-in Image Gen
tool. Its WebP versions are derived using Pillow. Final generation prompt:

> Extract and recreate only the large 3D lightning bolt hero sculpture from the
> design reference as a standalone production web image. Preserve the dark navy
> satin metal front, thin periwinkle beveled edge, orientation, soft ground shadow,
> and shape. Center the complete bolt with margin on a cool light #f6f8fb seamless
> studio background. No text, logo tile, header, UI, or other objects.

The page uses the existing project logo and actual repository preview images in
place of the generated concept's approximations. Installation helper text and a
thermal requirements link are intentional additions for accurate instructions.

### Original design comparison

The concept and browser renders were inspected together with `view_image`.
Verification used the Codex in-app browser at 1435 × 1096 and mobile widths of
390 and 320 pixels, including mouse and keyboard tab selection, section anchors,
and navigation to the actual latest GitHub release. No Playwright fallback was
needed. Browser console checks reported no errors or warnings.

| Area | Comparison and final decision |
| --- | --- |
| Copy | Hero, navigation, feature titles, and CTAs match the concept; no added hero labels. |
| Palette | Cool light background, navy text, and blue accents retained. |
| Typography | System Segoe UI/Arial implements the hierarchy without remote font requests. |
| Illustration | Navy lightning and blue bevel retained; an edge mask removed the visible image boundary. |
| Layout | Split hero, three open feature columns, compatibility table, dark installation band retained. |
| Product imagery | Actual repository screenshots replace the invented concept dashboard; full aspect ratios improve readability. |
| Brand and guidance | Existing project icon replaces the concept icon; installation helper text and thermal documentation link are intentional additions. |
| Mobile | Single-column layout, wrapping actions, all navigation visible, no horizontal overflow at tested widths. |

The initial undersized dashboard preview was enlarged. These intentional asset,
font, and instruction differences preserve the design direction while keeping
the published product information accurate.

### Follow-up usability improvements

The authorized follow-up keeps the palette, typography and existing page identity.
It shortens the hero, reserves a stable gallery size, adds image enlargement,
serves responsive WebP assets, and adds a generated release snapshot, readable
profile comparison and installation FAQ. These supersede the original oversized
preview and generic release CTA described in the first design comparison.

### Premium visual direction

The subsequent requested restyle supersedes the original light palette. Current
tokens are graphite `#090c12`, soft white `#f1f3f7`, slate text `#9da8b8` and ice
blue `#a9c8fa`. Manrope is served locally from `assets/fonts/manrope-variable.ttf`
with `font-display: swap`. Its original SIL Open Font License is included beside
the font as `OFL.txt`; source: [Google Fonts Manrope](https://github.com/google/fonts/tree/main/ofl/manrope).
There are no runtime Google Fonts requests.

The page uses medium-weight display typography, thin separators, numbered feature
columns, rounded preview tabs and quiet bordered surfaces. The installation panel
has a restrained graphite-blue gradient. Hover and entrance transitions respect
`prefers-reduced-motion`; the content stays visible without animation support.
The native zoom dialog and FAQ retain keyboard operation and focus restoration.

The current sculpture source is `docs/branding/lightning-premium.png`, generated
with built-in Image Gen. Asset prompt: recreate only the premium lightning bolt
from the concept, preserving its upright silhouette, brushed dark titanium front,
polished silver bevel and fine ice-blue edge light, centered on a seamless dark
graphite studio background with a subtle pool of light; no text or UI. WebP
derivatives at 400, 800 and 1200 pixels are generated by the existing image script.
The earlier light illustration remains in `docs/branding/` as a source reference.

Design comparison notes for this restyle:

| Element | Implementation decision |
| --- | --- |
| Hero copy | Existing headline, description, navigation and CTA labels preserved; no new hero claims. |
| Palette and image | Graphite and ice-blue system, new titanium asset, edge mask without a color tint. |
| Typography | Locally served variable Manrope, medium headings and deliberate control sizes. |
| Section structure | Feature strip, centered dashboard introduction, profiles, compatibility, download and FAQ retained. |
| Controls | Pill tabs, outlined installation numbers, SVG plus/minus disclosures, subtle hover states. |
| Intentional differences | Existing project logo and real WebUI previews replace generated approximations; factual profile and release wording remains authoritative. |
