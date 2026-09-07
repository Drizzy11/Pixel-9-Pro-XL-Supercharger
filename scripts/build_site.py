#!/usr/bin/env python3
"""Build bilingual website pages from the committed public release snapshot.

Use --refresh during publishing to fetch current GitHub data and its checksum.
"""
import argparse
from html import escape
from html.parser import HTMLParser
import json
from pathlib import Path
import re

from site_data import fetch_snapshot
from site_pages import BASE_URL, guide, tools, releases, not_found
from update_site_release import render_release, update_page, write_atomic

ROOT = Path(__file__).resolve().parents[1]


class SpanishIndex(HTMLParser):
    def __init__(self, translations):
        super().__init__(convert_charrefs=True)
        self.translations = translations
        self.output = []
        self.skip = False
        self.language_link = False
        self.missing = set()

    def translate(self, text):
        stripped = text.strip()
        if not stripped:
            return text
        if stripped in self.translations:
            translated = self.translations[stripped]
        elif re.fullmatch(r'v[0-9.]+ · Stable', stripped):
            translated = stripped.replace('Stable', 'Estable')
        elif re.fullmatch(r'Download v[0-9.]+ ZIP', stripped):
            translated = stripped.replace('Download', 'Descargar')
        elif re.fullmatch(r'[0-9\s·./-]+(?:KiB)?', stripped):
            translated = stripped
        else:
            self.missing.add(stripped)
            translated = stripped
        return text.replace(stripped, translated, 1)

    def handle_decl(self, decl): self.output.append(f'<!{decl}>')
    def handle_comment(self, data): self.output.append(f'<!--{data}-->')
    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        self.language_link = tag == 'a' and 'language-link' in values.get('class', '')
        if tag in ('script', 'style', 'code', 'time'): self.skip = True
        result = []
        for key, value in attrs:
            if value is None:
                result.append(key); continue
            if tag == 'html' and key == 'lang': value = 'es'
            elif self.language_link and key == 'href': value = '../index.html'
            elif self.language_link and key in ('lang', 'hreflang'): value = 'en'
            elif key in ('src', 'href') and value.startswith(('./assets/', './styles.css', './pages.css', './main.js', './site.mjs')): value = '../' + value[2:]
            elif key == 'srcset': value = value.replace('./assets/', '../assets/')
            elif key == 'href' and values.get('rel') == 'canonical': value = BASE_URL + 'es/'
            elif key == 'content' and values.get('property') == 'og:url': value = BASE_URL + 'es/'
            elif key in ('alt', 'aria-label', 'title') and value: value = self.translate(value)
            elif key == 'content' and (values.get('name') == 'description' or values.get('property') in ('og:title', 'og:description')): value = self.translate(value)
            result.append(f'{key}="{escape(value, quote=True)}"')
        self.output.append('<' + tag + (' ' + ' '.join(result) if result else '') + '>')
    def handle_endtag(self, tag):
        self.output.append(f'</{tag}>')
        if tag in ('script', 'style', 'code', 'time'): self.skip = False
        if tag == 'a': self.language_link = False
    def handle_data(self, data):
        if self.language_link and data.strip() == 'Español': data = data.replace('Español', 'English')
        elif not self.skip: data = self.translate(data)
        self.output.append(data if self.skip and data else escape(data, quote=False))


def build(refresh=False):
    site = ROOT / 'site'
    cache = site / 'data/releases.json'
    snapshot = fetch_snapshot() if refresh else json.loads(cache.read_text(encoding='utf-8'))
    render_release(snapshot['latest'])
    if not re.fullmatch(r'[a-f0-9]{64}', snapshot['sha256']): raise ValueError('Invalid cached checksum')
    if any(not record.get('date') or not record['url'].startswith('https://github.com/Drizzy07x/Supercharger_Pixel_9_Series/releases/tag/') for record in snapshot['history']): raise ValueError('Invalid public history')
    update_page(site / 'index.html', snapshot['latest'])
    page = (site / 'index.html').read_text(encoding='utf-8')
    filename = f"Pixel-9-Series-Supercharger-{snapshot['latest']['tag_name']}.zip"
    page = re.sub(r'Pixel-9-Series-Supercharger-(?:VERSION|v[0-9.]+)\.zip', filename, page)
    translations = json.loads((ROOT / 'scripts/site_translations.es.json').read_text(encoding='utf-8'))
    translator = SpanishIndex(translations)
    translator.feed(page)
    if translator.missing:
        raise ValueError('Missing Spanish translations:\n' + '\n'.join(sorted(translator.missing)))
    outputs = {site / 'index.html': page, site / 'es/index.html': ''.join(translator.output), site / '404.html': not_found()}
    for lang in ('en','es'):
        folder = site / 'es' if lang == 'es' else site
        outputs[folder / 'guide.html'] = guide(snapshot, lang)
        outputs[folder / 'tools.html'] = tools(snapshot, lang)
        outputs[folder / 'releases.html'] = releases(snapshot, lang)
    for path, content in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        write_atomic(path, content.rstrip()+'\n')
    cache.parent.mkdir(parents=True, exist_ok=True)
    write_atomic(cache, json.dumps(snapshot, ensure_ascii=False, indent=2)+'\n')
    urls=[BASE_URL + ('es/' if lang=='es' else '') + name for lang in ('en','es') for name in ('','guide.html','tools.html','releases.html')]
    sitemap='<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'+''.join(f'<url><loc>{url}</loc></url>' for url in urls)+'</urlset>\n'
    write_atomic(site/'sitemap.xml', sitemap)
    write_atomic(site/'robots.txt', f'User-agent: *\nAllow: /\nSitemap: {BASE_URL}sitemap.xml\n')
    print(f'Built English/Spanish pages, 404, and {len(snapshot["history"])} public releases.')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh',action='store_true')
    build(parser.parse_args().refresh)
