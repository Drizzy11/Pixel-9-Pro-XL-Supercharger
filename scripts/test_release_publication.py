import textwrap
import unittest
from shell_harness import ROOT, run_shell


def publication_script():
    text = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
    step = text.split("      - name: Publish or update GitHub release\n", 1)[1]
    return textwrap.dedent(step.split("        run: |\n", 1)[1])


FIXTURE = r'''
RUNNER_TEMP="$PWD/runtime"
TAG_NAME=v2.6.8-beta.1
ASSET_BASENAME=Pixel-9-Series-Supercharger-v2.6.8-beta.1
RELEASE_TITLE='Test prerelease'
PRERELEASE=true
mkdir -p "$RUNNER_TEMP/supercharger-release" published
for name in "$ASSET_BASENAME.zip" "$ASSET_BASENAME.zip.sha256" update.json release-manifest.json; do
  printf '%s\n' "$name contents" > "$RUNNER_TEMP/supercharger-release/$name"
  cp "$RUNNER_TEMP/supercharger-release/$name" "published/$name"
done
echo notes > "$RUNNER_TEMP/supercharger-release/release-notes.md"
gh() {
  echo "$*" >> calls
  case "$1 $2" in
    'release view')
      case "$MODE" in
        draft) echo true ;;
        missing) echo 'release not found' >&2; return 1 ;;
        error) echo 'API rate limit exceeded' >&2; return 1 ;;
        *) echo false ;;
      esac ;;
    'release download')
      while [ "$1" != --dir ]; do shift; done
      shift
      mkdir -p "$1"
      cp published/* "$1/" ;;
    'release upload'|'release edit'|'release create') echo "$*" >> mutations ;;
    *) echo 'Unexpected GitHub command' >&2; return 99 ;;
  esac
}
'''


class ReleasePublicationTests(unittest.TestCase):
    def test_every_version_suffix_stays_out_of_the_stable_channel(self):
        text = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        step = text.split("      - name: Resolve release metadata\n", 1)[1].split("      - uses:", 1)[0]
        script = textwrap.dedent(step.split("        run: |\n", 1)[1])
        for suffix, expected in (("", "false"), ("-beta.1", "true"), ("-preview.1", "true")):
            with self.subTest(suffix=suffix):
                fixture = f"GITHUB_REF_NAME=v2.6.8{suffix}\nGITHUB_OUTPUT=outputs\nprintf 'version=%s\\n' \"$GITHUB_REF_NAME\" > module.prop\n"
                result = run_shell(fixture + script + f"\ngrep -q '^is_prerelease={expected}$' outputs\n")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def check(self, mode, assertion, mutate=""):
        script = FIXTURE + f"\nMODE={mode}\n" + mutate
        # Run the actual workflow block in a subshell because its successful
        # published-release path deliberately exits before any mutation.
        script += "\n(\n" + publication_script() + "\n)\npublication_rc=$?\n" + assertion
        result = run_shell(script)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_matching_published_release_is_verified_without_mutation(self):
        self.check("published", r'''
[ "$publication_rc" = 0 ] || exit 1
[ ! -e mutations ] || exit 2
grep -q 'release download' calls || exit 3
''')

    def test_changed_published_assets_are_rejected_without_overwrite(self):
        self.check("published", r'''
[ "$publication_rc" != 0 ] || exit 1
[ ! -e mutations ] || exit 2
''', '\necho different > "published/$ASSET_BASENAME.zip"\n')

    def test_existing_draft_keeps_its_draft_state(self):
        self.check("draft", r'''
[ "$publication_rc" = 0 ] || exit 1
grep -q 'release upload' mutations || exit 2
grep -q 'release edit.* --draft ' mutations || exit 3
grep -q -- '--prerelease --latest=false' mutations || exit 4
''')

    def test_missing_release_is_created_as_prerelease_not_latest(self):
        self.check("missing", r'''
[ "$publication_rc" = 0 ] || exit 1
grep -q 'release create' mutations || exit 2
grep -q -- '--verify-tag' mutations || exit 3
grep -q -- '--prerelease --latest=false' mutations || exit 4
''')

    def test_api_error_is_not_treated_as_a_missing_release(self):
        self.check("error", r'''
[ "$publication_rc" != 0 ] || exit 1
[ ! -e mutations ] || exit 2
[ "$(wc -l < calls | tr -d ' ')" = 1 ] || exit 3
''')


if __name__ == "__main__":
    unittest.main()
