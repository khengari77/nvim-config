#!/usr/bin/env python3
"""Index Typeshed and installed Python APIs without importing package code."""
import argparse
import ast
import json
import os
from pathlib import Path
import sys
import sysconfig
import tempfile
import tokenize

SKIP = {'__pycache__', '.git', '.venv', 'venv', 'tests', 'test', 'testing',
        'benchmarks', 'examples', 'node_modules'}


def files(root, sources=False, modules=None):
    """Yield paths and importable module names; stubs override matching sources."""
    root = Path(root)
    for directory, dirs, names in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in SKIP and
                         (d.isidentifier() or d.endswith('-stubs')))
        if Path(directory) == root and modules is not None:
            dirs[:] = [d for d in dirs if d.removesuffix('-stubs') in modules]
        names = set(names)
        for name in sorted(names):
            path = Path(directory) / name
            if path.suffix != '.pyi' and not (sources and path.suffix == '.py'):
                continue
            if path.suffix == '.py' and path.with_suffix('.pyi').name in names:
                continue
            parts = list(path.relative_to(root).with_suffix('').parts)
            if modules is not None and parts[0].removesuffix('-stubs') not in modules:
                continue
            if parts[0].endswith('-stubs'):
                parts[0] = parts[0][:-6]
            if not all(p.isidentifier() for p in parts):
                continue
            package = parts[-1] == '__init__'
            if package:
                parts.pop()
            yield path, parts, package


def resolve_imports(entries, imports, exports):
    # Fixed-point iteration handles chained re-exports and cycles without imports.
    seen = {(e['name'], e['signature'], e['guard']) for e in entries}
    for _ in range(8):
        by_name = {}
        children = {}
        public = {}
        for entry in entries:
            name = entry['name']
            by_name.setdefault(name, []).append(entry)
            parent, _, symbol = name.rpartition('.')
            if not symbol.startswith('_'):
                public.setdefault(parent, set()).add(symbol)
            # Class aliases should expose methods as well as the constructor.
            if entry['kind'] == 'method':
                children.setdefault(parent, []).append(entry)
        additions = []
        for module, target, name, alias in imports:
            names = exports.get(target, public.get(target, set())) if name == '*' else {name}
            for symbol in sorted(names):
                original = target + '.' + symbol
                replacement = module + '.' + (symbol if alias == '*' else alias)
                for entry in by_name.get(original, []) + children.get(original, []):
                    new_name = replacement + entry['name'][len(original):]
                    key = (new_name, entry['signature'], entry['guard'])
                    if key not in seen:
                        seen.add(key)
                        additions.append(dict(entry, name=new_name))
        if not additions:
            break
        entries.extend(additions)
    return entries


def build(root, prefix='', sources=False, origin='stdlib', modules=None):
    entries, errors, exports, imports = [], [], {}, []
    selected = {}
    for path, parts, package in files(root, sources, modules):
        priority = (path.suffix == '.pyi', any(p.endswith('-stubs') for p in path.parts))
        key = tuple(parts)
        if key not in selected or priority > selected[key][0]:
            selected[key] = (priority, path, parts, package)
    for _, path, parts, package in selected.values():
        parts = ([prefix] if prefix else []) + parts
        module = '.'.join(parts)
        if not module:
            continue
        try:
            with tokenize.open(path) as handle:
                tree = ast.parse(handle.read(), filename=str(path))
        except (SyntaxError, UnicodeError, OSError, ValueError) as exc:
            errors.append(f'{path}: {exc}')
            continue

        def add(name, signature, node, guard, kind):
            entry = dict(name=name, signature=signature, source=str(path),
                         line=getattr(node, 'lineno', 1), guard=guard,
                         doc=(ast.get_docstring(node) or '')[:12000],
                         origin=origin, kind=kind)
            entries.append(entry)
            return entry

        add(module, 'module', tree, '', 'module')

        def visit(nodes, scope='', guard=''):
            for node in nodes:
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    signature = '(' + ast.unparse(node.args) + ')'
                    if node.returns:
                        signature += ' -> ' + ast.unparse(node.returns)
                    if isinstance(node, ast.AsyncFunctionDef):
                        signature = 'async ' + signature
                    entry = add(f'{module}.{scope}{node.name}', signature, node,
                                guard, 'method' if scope else 'function')
                    if scope and node.name in {'__new__', '__init__'}:
                        entries.append(dict(entry, name=f'{module}.{scope[:-1]}', kind='constructor'))
                elif isinstance(node, ast.ClassDef):
                    add(f'{module}.{scope}{node.name}', 'class ' + ', '.join(
                        ast.unparse(x) for x in node.bases), node, guard, 'class')
                    visit(node.body, scope + node.name + '.', guard)
                elif isinstance(node, ast.If):
                    condition = ast.unparse(node.test)
                    visit(node.body, scope, f'{guard}; {condition}'.strip('; '))
                    visit(node.orelse, scope, f'{guard}; not ({condition})'.strip('; '))
                elif isinstance(node, ast.Try):
                    visit(node.body, scope, guard)
                    for handler in node.handlers:
                        visit(handler.body, scope, guard)
                    visit(node.orelse, scope, guard)
                    visit(node.finalbody, scope, guard)
                elif isinstance(node, ast.Assign) and not scope:
                    if any(isinstance(t, ast.Name) and t.id == '__all__' for t in node.targets):
                        if isinstance(node.value, (ast.List, ast.Tuple)):
                            exports.setdefault(module, set()).update(
                                x.value for x in node.value.elts
                                if isinstance(x, ast.Constant) and isinstance(x.value, str))
                elif isinstance(node, ast.ImportFrom) and not scope:
                    base = parts if package else parts[:-1]
                    target = '.'.join(base[:len(base)-node.level+1] +
                                      ([node.module] if node.module else [])) if node.level else (node.module or '')
                    for alias in node.names:
                        if alias.name == '*' or alias.asname or path.suffix == '.py':
                            imports.append((module, target, alias.name, alias.asname or alias.name))
        visit(tree.body)
    return resolve_imports(entries, imports, exports), errors


def environment_roots(environment=None):
    """Discover directories without site initialization, .pth execution or imports."""
    executable_prefix = Path(sys.executable).parent.parent
    if not environment and (executable_prefix / 'pyvenv.cfg').is_file():
        environment = executable_prefix
    roots = []
    include_base = not environment
    if environment:
        environment = Path(environment)
        for lib in ('lib', 'lib64'):
            roots.extend(sorted((environment / lib).glob('python*/site-packages')))
        roots.append(environment / 'Lib/site-packages')
        cfg = environment / 'pyvenv.cfg'
        if cfg.is_file():
            include_base = any(line.strip().lower().replace(' ', '') ==
                               'include-system-site-packages=true'
                               for line in cfg.read_text().splitlines())
    if include_base:
        paths = sysconfig.get_paths()
        if not os.environ.get('PYTHONNOUSERSITE'):
            roots.append(Path(sysconfig.get_path('purelib', scheme='posix_user')))
        roots.extend(Path(paths[k]) for k in ('purelib', 'platlib'))
    return list(dict.fromkeys(str(p.resolve()) for p in roots if p.is_dir()))


def inventory(roots):
    names = set()
    for root in roots:
        for child in Path(root).iterdir():
            name = child.name.removesuffix('-stubs') if child.is_dir() else child.stem
            if name in SKIP or not name.isidentifier():
                continue
            if child.is_dir() or child.suffix in {'.py', '.pyi'}:
                names.add(name)
    return sorted(names)


def catalogue(root, package_roots, modules=None):
    entries, errors = build(root) if root else ([], [])
    # Match Python's root precedence: regular packages shadow later packages;
    # namespace packages may contribute different modules from several roots.
    occupied = {e['name'] for e in entries}
    shadowed, occupied_modules = set(), set()
    for extra in package_roots:
        selected = (set(inventory([extra])) if modules is None else modules) - shadowed
        if not selected:
            continue
        rows, failures = build(extra, sources=True, origin='package', modules=selected)
        source_modules = {e['source']: e['name'] for e in rows if e['kind'] == 'module'}
        rows = [e for e in rows if source_modules.get(e['source']) not in occupied_modules]
        entries.extend(e for e in rows if e['name'] not in occupied)
        occupied.update(e['name'] for e in rows)
        occupied_modules.update(e['name'] for e in rows if e['kind'] == 'module')
        shadowed.update(e['name'] for e in rows if e['kind'] == 'module' and '.' not in e['name'])
        errors.extend(failures)
    return entries, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root')
    parser.add_argument('--extra-root', action='append', default=[])
    parser.add_argument('--environment', help='Virtualenv/Conda prefix to scan')
    parser.add_argument('--no-packages', action='store_true')
    parser.add_argument('--output')
    parser.add_argument('--list-packages', action='store_true')
    parser.add_argument('--package', action='append', default=[])
    parser.add_argument('--package-only', action='store_true')
    parser.add_argument('--all-packages', action='store_true')
    args = parser.parse_args()
    roots = args.extra_root + ([] if args.no_packages else environment_roots(args.environment))
    roots = list(dict.fromkeys(str(Path(p).resolve()) for p in roots))
    for path in roots:
        if not Path(path).is_dir():
            parser.error(f'Package root does not exist: {path}')
    if args.list_packages:
        print(json.dumps(dict(roots=roots, packages=inventory(roots))))
        return
    if not args.output:
        parser.error('--output is required for indexing')
    root = None if args.package_only else Path(args.root or '')
    if root is not None and not (root / 'builtins.pyi').is_file():
        parser.error('--root must contain standard-library builtins.pyi')
    modules = set(args.package) if args.package else (None if args.all_packages or args.extra_root else set())
    entries, errors = catalogue(root, roots, modules)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    payload = dict(version=2, root=str(root) if root else None, package_roots=roots,
                   python=sys.executable, entries=entries, errors=errors)
    with tempfile.NamedTemporaryFile(mode='w', dir=output.parent, delete=False) as handle:
        json.dump(payload, handle)
        temporary = handle.name
    os.replace(temporary, output)
    packages = sum(e['origin'] == 'package' for e in entries)
    print(f'Indexed {len(entries)} entries ({packages} installed-package APIs); '
          f'{len(errors)} parse errors\nPackage roots: {", ".join(roots) or "none"}')
    for error in errors:
        print(error)


if __name__ == '__main__':
    main()
