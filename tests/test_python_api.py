import importlib.util
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest

spec = importlib.util.spec_from_file_location('index', Path(__file__).parents[1] / 'scripts/python_api_index.py')
index = importlib.util.module_from_spec(spec)
spec.loader.exec_module(index)

class IndexTests(unittest.TestCase):
    def test_static_index(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'a.pyi').write_text('''raise RuntimeError("never execute")
__all__ = ["f", "C"]
@overload
def f(x: list[str], /, *, key: Callable = ...) -> Iterator[T]: ...
@overload
def f(x, *args, **kwargs): ...
class C:
    def __new__(cls, iterable: Iterable[T]) -> Self: ...
    async def method(self, key: str) -> list[str]: ...
if sys.version_info >= (3, 12):
    def conditional() -> str: ...
else:
    def conditional() -> bytes: ...
''')
            (root / '__init__.pyi').write_text('from .a import *')
            (root / 'broken.pyi').write_text('def !!!!')
            entries, errors = index.build(root, 'pkg')
            self.assertEqual(len(errors), 1)
            self.assertEqual(len([e for e in entries if e['name'] == 'pkg.a.f']), 2)
            self.assertTrue(any(e['name'] == 'pkg.f' for e in entries))
            self.assertTrue(any(e['name'] == 'pkg.a.C' and 'iterable' in e['signature'] for e in entries))
            method = next(e for e in entries if e['name'] == 'pkg.a.C.method')
            self.assertIn('list[str]', method['signature'])
            self.assertTrue(any(e['guard'].startswith('not') for e in entries))
            self.assertTrue(any('x,' in e['signature'] for e in entries))

    def test_installed_packages_without_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pkg = root / 'demo'
            pkg.mkdir()
            marker = root / 'executed'
            (pkg / '__init__.py').write_text('from .core import process, Thing\n')
            (pkg / 'core.py').write_text(f'open({str(marker)!r}, "w").write("bad")\n'
                'def process(value: str, key=None) -> list[str]:\n    """Process a string."""\n    return []\n'
                'class Thing:\n    def run(self, key: str) -> int: ...\n')
            (root / 'standalone.py').write_text('def plain(value): ...\n')
            (pkg / 'typed.py').write_text('def prefer(wrong): ...\n')
            (pkg / 'typed.pyi').write_text('def prefer(right: int) -> str: ...\n')
            (pkg / 'tests').mkdir()
            (pkg / 'tests' / 'test_bad.py').write_text('this is not Python!')
            rows, errors = index.catalogue(None, [str(root)], {'demo'})
            self.assertFalse(errors)
            self.assertFalse(marker.exists())
            names = {e['name']: e for e in rows}
            self.assertIn('demo.process', names)
            self.assertIn('demo.Thing.run', names)
            self.assertEqual(names['demo.process']['doc'], 'Process a string.')
            self.assertIn('right: int', names['demo.typed.prefer']['signature'])
            self.assertNotIn('standalone.plain', names)
            rows, _ = index.catalogue(None, [str(root)], {'standalone'})
            self.assertTrue(any(e['name'] == 'standalone.plain' for e in rows))
            stub = root / 'demo-stubs'
            stub.mkdir()
            (stub / '__init__.pyi').write_text('def process(stub: bool) -> int: ...\n')
            rows, _ = index.catalogue(None, [str(root)], {'demo'})
            self.assertTrue(any(e['name'] == 'demo.process' and 'stub: bool' in e['signature'] for e in rows))
            self.assertEqual(index.inventory([str(root)]), ['demo', 'standalone'])

    def test_package_root_precedence_and_namespaces(self):
        with tempfile.TemporaryDirectory() as directory:
            first, second = (Path(directory) / n for n in ('first', 'second'))
            for root in (first, second):
                (root / 'demo').mkdir(parents=True)
                (root / 'ns').mkdir()
            (first / 'demo/__init__.py').write_text('def current(): ...\n')
            (second / 'demo/__init__.py').write_text('def obsolete(): ...\n')
            (second / 'demo/obsolete.py').write_text('def old(): ...\n')
            (first / 'ns/one.py').write_text('def one(): ...\n')
            (second / 'ns/two.py').write_text('def two(): ...\n')
            rows, _ = index.catalogue(None, [str(first), str(second)], {'demo', 'ns'})
            names = {e['name'] for e in rows}
            self.assertIn('demo.current', names)
            self.assertNotIn('demo.obsolete', names)
            self.assertIn('ns.one.one', names)
            self.assertIn('ns.two.two', names)

    def test_venv_discovery(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            site = root / 'lib/python3.12/site-packages'
            site.mkdir(parents=True)
            (root / 'pyvenv.cfg').write_text('include-system-site-packages = false\n')
            self.assertEqual(index.environment_roots(root), [str(site)])

    def test_failed_build_preserves_previous_index(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'index.json'
            output.write_text('previous index')
            result = subprocess.run([sys.executable, '-I', '-S', str(Path(__file__).parents[1] / 'scripts/python_api_index.py'), '--root', directory, '--output', str(output)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_text(), 'previous index')

if __name__ == '__main__':
    unittest.main()
