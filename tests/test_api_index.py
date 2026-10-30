import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

script = Path(__file__).parents[1] / 'scripts/api_index.py'
spec = importlib.util.spec_from_file_location('api_index', script)
index = importlib.util.module_from_spec(spec)
spec.loader.exec_module(index)


class ApiIndexTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('ctags'), 'Universal Ctags required')
    def test_static_declarations(self):
        examples = {
            'typescript': ('api.d.ts', 'interface Box {\n map(value: string): number;\n}\n'),
            'c': ('api.h', 'int compute(const char *text, int count);\n'),
            'cpp': ('api.hpp', 'namespace example {\nclass Box {\npublic:\n int compute(int count);\n};\n}\n'),
            'rust': ('api.rs', 'pub fn compute(value: &str) -> usize { value.len() }\n'),
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for language, (name, text) in examples.items():
                with self.subTest(language=language):
                    path = root / name
                    path.write_text(text)
                    entries = index.tags(root, language, [path])
                    functions = [e for e in entries if 'compute' in e['name'] or 'map' in e['name']]
                    self.assertTrue(functions)
                    self.assertTrue(all(e['source'] == str(path) for e in functions))
                    self.assertTrue(any('count' in e['signature'] or 'value' in e['signature'] or 'text' in e['signature'] for e in functions))
            (root / 'tests').mkdir()
            (root / 'tests' / 'hidden.rs').write_text('fn hidden() {}')
            self.assertNotIn(root / 'tests' / 'hidden.rs', list(index.source_files(root, 'rust')))

    def test_include_cycles_and_ts_references(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'a.h').write_text('#include "b.h"\nint one(void);')
            (root / 'b.h').write_text('#include "a.h"\nint two(void);')
            self.assertEqual(len(index.includes(root / 'a.h', [root])), 2)
            (root / 'lib.a.d.ts').write_text('/// <reference lib="b" />')
            (root / 'lib.b.d.ts').write_text('declare function b(): string;')
            self.assertEqual(len(index.includes(root / 'lib.a.d.ts', [root])), 2)

    def test_published_declarations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'dist').mkdir()
            declaration = root / 'dist/index.d.ts'
            declaration.write_text('declare function published(): string;')
            self.assertNotIn(declaration, list(index.source_files(root, 'typescript')))
            self.assertIn(declaration, list(index.source_files(root, 'typescript', installed=True)))

    def test_rustdoc(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'std'
            (root / 'vec').mkdir(parents=True)
            path = root / 'vec/struct.Vec.html'
            path.write_text('<pre class="rust item-decl"><code>pub struct Vec&lt;T&gt;</code></pre>'
                            '<section id="method.push"><h4 class="code-header">pub fn push(&amp;mut self, value: T)</h4></section>')
            entries = index.rustdoc(root, 'vec')
            method = next(e for e in entries if e['name'] == 'std::vec::Vec::push')
            self.assertIn('&mut self', method['signature'])
            self.assertTrue(method['url'].endswith('#method.push'))

    def test_whole_standard_library_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'stdio.h').write_text('int printf(const char *format, ...);')
            (root / 'string.h').write_text('void *memcpy(void *dst, const void *src, int n);')
            (root / 'unrelated.h').write_text('int unrelated(void);')
            files = index.standard_headers(root, 'c')
            self.assertIn(root / 'stdio.h', files)
            self.assertIn(root / 'string.h', files)
            self.assertNotIn(root / 'unrelated.h', files)
            (root / 'vector').write_text('#include "detail/vector.h"')
            (root / 'detail').mkdir()
            (root / 'detail/vector.h').write_text('class vector {};')
            self.assertIn(root / 'detail/vector.h', index.standard_headers(root, 'cpp'))
            docs = root / 'std'
            for module, symbol in [('vec', 'push'), ('iter', 'map')]:
                (docs / module).mkdir(parents=True)
                (docs / module / 'struct.Api.html').write_text('<section id="method.' + symbol + '"><h4 class="code-header">pub fn ' + symbol + '(&amp;self)</h4></section>')
            names = {e['name'] for e in index.rustdoc(docs, '', whole=True)}
            self.assertIn('std::vec::Api::push', names)
            self.assertIn('std::iter::Api::map', names)

    def test_failed_build_keeps_index(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'index.json'
            output.write_text('previous')
            result = subprocess.run([sys.executable, '-I', '-S', str(script), '--language', 'c', '--root', directory + '/missing', '--output', str(output)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_text(), 'previous')
