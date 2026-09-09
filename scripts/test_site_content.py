"""Public website metadata, translations, and source-content boundaries."""
from pathlib import Path
from html.parser import HTMLParser
import unittest

from build_site import SpanishIndex
from site_data import parse_checksum, public_history
from site_pages import release_notes


class SiteContentTests(unittest.TestCase):
    def test_interactive_forms_cannot_submit_before_javascript_is_ready(self):
        root=Path(__file__).resolve().parents[1]
        for lang in ('', 'es/'):
            class Guard(HTMLParser):
                def __init__(self): super().__init__(); self.disabled=[]; self.submits=[]
                def handle_starttag(self,tag,attrs):
                    a=dict(attrs)
                    if tag=='fieldset': self.disabled.append('disabled' in a)
                    if tag=='button' and a.get('type')=='submit': self.submits.append(any(self.disabled))
                def handle_endtag(self,tag):
                    if tag=='fieldset': self.disabled.pop()
            parser=Guard();parser.feed((root/'site'/lang/'tools.html').read_text(encoding='utf-8'))
            self.assertEqual(parser.submits,[True,True,True])

    def test_checksum_must_identify_the_selected_release_zip(self):
        filename='Pixel-9-Series-Supercharger-v2.6.7.zip'
        self.assertEqual(parse_checksum('A'*64+'  '+filename+'\n',filename),'a'*64)
        for text in ('a'*63+' '+filename, 'a'*64+' other.zip', 'a'*64+' '+filename+'\n'+'b'*64+' '+filename):
            with self.assertRaises(ValueError): parse_checksum(text,filename)

    def test_drafts_are_excluded_before_any_private_fields_are_serialized(self):
        draft={'draft':True,'published_at':None,'tag_name':'v9.9.9-secret','body':'PRIVATE DRAFT'}
        public={'draft':False,'published_at':'2026-07-30T22:23:12Z','tag_name':'v2.6.7','html_url':'https://github.com/Drizzy07x/Supercharger_Pixel_9_Series/releases/tag/v2.6.7','body':'Public notes','prerelease':False}
        result=public_history([draft,public])
        self.assertEqual(len(result),1)
        self.assertNotIn('PRIVATE',str(result))

    def test_release_history_rejects_external_links(self):
        with self.assertRaises(ValueError):
            public_history([{'draft':False,'published_at':'2026-07-30T22:23:12Z','tag_name':'v2.6.7','html_url':'https://example.com'}])

    def test_release_notes_escape_html_and_do_not_create_script_links(self):
        html=release_notes('# Changes\n- <script>alert(1)</script>\n[link](javascript:alert(1))')
        self.assertNotIn('<script>',html)
        self.assertNotIn('href=',html)
        self.assertIn('&lt;script&gt;',html)

    def test_spanish_pages_keep_assets_relative_to_the_project_and_commands_unchanged(self):
        parser=SpanishIndex({'Hello':'Hola'})
        parser.feed('<html lang="en"><a href="./guide.html">Hello</a><img src="./assets/a.webp"><code>Get-FileHash file.zip</code></html>')
        html=''.join(parser.output)
        self.assertIn('lang="es"',html)
        self.assertIn('src="../assets/a.webp"',html)
        self.assertIn('href="./guide.html"',html)
        self.assertIn('Get-FileHash file.zip',html)
        self.assertIn('Hola',html)
        self.assertFalse(parser.missing)

    def test_unknown_english_copy_is_reported_for_translation(self):
        parser=SpanishIndex({});parser.feed('<p>Untranslated content</p>')
        self.assertEqual(parser.missing,{'Untranslated content'})


if __name__=='__main__': unittest.main()
