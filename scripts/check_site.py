#!/usr/bin/env python3
"""Run the website's offline tests and validate all generated local links."""
from html.parser import HTMLParser
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

ROOT=Path(__file__).resolve().parents[1]
SITE=ROOT/'site'


class Document(HTMLParser):
    def __init__(self):
        super().__init__();self.ids=[];self.refs=[];self.base=None;self.language=None
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if tag=='html':self.language=a.get('lang')
        if tag=='base':self.base=a.get('href')
        if 'id' in a:self.ids.append(a['id'])
        for key in ('src','href'):
            if key in a and tag!='base':self.refs.append(a[key])
        self.refs.extend(value.strip().split()[0] for value in a.get('srcset','').split(',') if value.strip())
        if tag=='img' and 'alt' not in a: raise ValueError('Image missing alt attribute')


def validate_site():
    docs={}
    for path in SITE.rglob('*.html'):
        doc=Document();doc.feed(path.read_text(encoding='utf-8'))
        if doc.language not in ('en','es'):raise ValueError(f'Missing page language: {path}')
        if len(doc.ids)!=len(set(doc.ids)):raise ValueError(f'Duplicate IDs: {path}')
        docs[path.resolve()]=doc
    for page,doc in docs.items():
        for ref in doc.refs:
            url=urlsplit(ref)
            if url.scheme or url.netloc:continue
            if doc.base or url.path.startswith('/Supercharger_Pixel_9_Series/'):
                relative=url.path.removeprefix('/Supercharger_Pixel_9_Series/').lstrip('/')
                target=(SITE/relative).resolve() if relative else page
            else:target=(page.parent/unquote(url.path)).resolve() if url.path else page
            if target.is_dir():target/= 'index.html'
            if not target.is_relative_to(SITE.resolve()) or not target.is_file():raise ValueError(f'Broken local reference in {page.name}: {ref}')
            if url.fragment and target in docs and unquote(url.fragment) not in docs[target].ids:raise ValueError(f'Broken fragment: {ref} in {page}')
    for path in SITE.rglob('*.css'):
        for ref in re.findall(r'url\([\'"]?([^\)\'\"]+)',path.read_text()):
            if not urlsplit(ref).scheme and not (path.parent/ref).is_file():raise ValueError(f'Broken CSS asset: {ref}')
    print(f'Validated {len(docs)} pages, local assets, fragments, and languages.')


def main():
    validate_site()
    for path in sorted(SITE.glob('*.js'))+sorted(SITE.glob('*.mjs')):
        subprocess.run(['node','--check',str(path)],cwd=ROOT,check=True)
    subprocess.run(['node','--test','scripts/site_regression.test.mjs','scripts/site_tools.test.mjs'],cwd=ROOT,check=True)
    subprocess.run([sys.executable,'-m','unittest','discover','-s','scripts','-p','test_site_*.py'],cwd=ROOT,check=True)


if __name__=='__main__':main()
