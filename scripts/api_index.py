#!/usr/bin/env python3
"""Static API extraction through Universal Ctags or existing rustdoc HTML."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from html.parser import HTMLParser

SKIP = {'.git', 'node_modules', 'target', 'build', 'dist', 'tests', 'test', 'examples', 'benches', '.venv', 'out', 'vendor', 'third_party', '__pycache__'}
EXTENSIONS = {'typescript': {'.ts', '.tsx', '.mts', '.cts'}, 'c': {'.c', '.h'}, 'cpp': {'.h', '.hpp', '.hh', '.cpp', '.cc'}, 'rust': {'.rs'}}


def source_files(root, language, installed=False):
    for directory, dirs, files in os.walk(root):
        skip = SKIP - {'dist', 'build', 'out'} if installed else SKIP
        dirs[:] = sorted(d for d in dirs if d not in skip and not d.startswith('.'))
        for name in sorted(files):
            path = Path(directory) / name
            if path.suffix in EXTENSIONS[language]:
                yield path


def includes(path, roots):
    pending, seen = list(path) if isinstance(path, (list, tuple)) else [path], set()
    while pending:
        file = pending.pop()
        if file in seen:
            continue
        seen.add(file)
        try:
            text = file.read_text(errors='replace')
        except OSError:
            continue
        if file.suffix == '.ts':
            for library in re.findall(r'<reference lib="([^"]+)"', text):
                candidate = file.parent / ('lib.' + library + '.d.ts')
                if candidate.is_file():
                    pending.append(candidate)
        for header in re.findall(r'^\s*#\s*include\s*[<"]([^">]+)', text, re.M):
            for root in [file.parent] + roots:
                candidate = (root / header).resolve()
                if candidate.is_file() and any(candidate.is_relative_to(r.resolve()) for r in roots):
                    pending.append(candidate)
                    break
    return sorted(seen)


C_HEADERS = "assert.h complex.h ctype.h errno.h fenv.h float.h inttypes.h iso646.h limits.h locale.h math.h setjmp.h signal.h stdalign.h stdarg.h stdatomic.h stdbit.h stdbool.h stdckdint.h stddef.h stdint.h stdio.h stdlib.h stdnoreturn.h string.h tgmath.h threads.h time.h uchar.h wchar.h wctype.h".split()


def standard_headers(root, language, extra_roots=()):
    roots = [root] + list(extra_roots)
    seeds = []
    if language == 'c':
        for name in C_HEADERS:
            for directory in roots:
                candidate = directory / name
                if candidate.is_file():
                    seeds.append(candidate.resolve())
                    break
    else:
        seeds = [p.resolve() for p in root.iterdir() if p.is_file() and
                 not p.name.startswith('_') and p.suffix in {'', '.h', '.hpp', '.hh'}]
    return includes(seeds, roots)


def tags(root, language, paths, executable='ctags', compact=False):
    entries = []
    for offset in range(0, len(paths), 150):
        command = [executable, '--options=NONE', '--output-format=json', '--fields=+nSa', '--sort=no',
                   '--language-force=' + {'typescript': 'TypeScript', 'c': 'C', 'cpp': 'C++', 'rust': 'Rust'}[language]]
        if language in {'c', 'cpp'}:
            command += ['--kinds-' + ('C' if language == 'c' else 'C++') + '=+p']
        result = subprocess.run(command + ['-f', '-'] + [str(p) for p in paths[offset:offset+150]],
                                text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError(result.stderr.strip())
        file_lines = {}
        for line in result.stdout.splitlines():
            row = json.loads(line)
            if row.get('_type') != 'tag' or row.get('kind') in {'local', 'parameter', 'label', 'macro', 'import'}:
                continue
            path = Path(row['path'])
            if path not in file_lines:
                file_lines[path] = path.read_text(errors='replace').splitlines()
            lines = file_lines[path]
            number = row.get('line', 1)
            # Ctags supplies scope/signatures; retain the original declaration
            # too, because return types and TS method annotations vary by parser.
            declaration = []
            balance = 0
            for text in lines[number-1:number+16]:
                declaration.append(text.strip())
                balance += text.count('(') - text.count(')')
                if balance <= 0:
                    break
            signature = ' '.join(declaration)
            if row.get('signature') and row['signature'] not in signature:
                signature += ' ' + row['signature']
            if row.get('kind') in {'function', 'method', 'prototype'}:
                before = signature.split('{', 1)[0]
                if before.count('(') == before.count(')'):
                    signature = before.rstrip()
                if row.get('typeref'):
                    signature += ' -> ' + row['typeref'].split(':', 1)[-1]
            separator = '::' if language in {'cpp', 'rust'} else '.'
            scope = row.get('scope', '')
            name = (scope + separator if scope else '') + row['name']
            if language == 'rust':
                relative = path.relative_to(root).with_suffix('')
                prefix = [p for p in relative.parts if p not in {'src', 'lib', 'main', 'mod'}]
                name = '::'.join(prefix + [name])
            doc = '' if compact else '\n'.join(lines[max(0, number-8):min(len(lines), number+12)])
            entries.append(dict(name=name, signature=signature, source=str(path), line=number, doc=doc, url=''))
    return entries


class Rustdoc(HTMLParser):
    def __init__(self, path, root):
        super().__init__(convert_charrefs=True)
        self.path, self.root = path, root
        self.anchor = ''
        self.capture = None
        self.entries = []
        relative = path.relative_to(root)
        parent = list(relative.parts[:-1])
        stem = path.stem
        if '.' in stem:
            stem = stem.split('.', 1)[1]
        self.name = '::'.join([root.name] + parent + ([] if stem == 'index' else [stem]))

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            self.anchor = attrs['id']
        classes = attrs.get('class', '').split()
        if self.capture is None and ('item-decl' in classes or tag == 'h4' and 'code-header' in classes):
            self.capture = [tag, [], self.anchor]

    def handle_data(self, text):
        if self.capture:
            self.capture[1].append(text)

    def handle_endtag(self, tag):
        if self.capture and tag == self.capture[0]:
            _, text, anchor = self.capture
            signature = ' '.join(''.join(text).split())
            name = self.name
            if anchor.startswith(('method.', 'tymethod.', 'associatedconstant.', 'associatedtype.')):
                name += '::' + anchor.split('.', 1)[1].split('-')[0]
            self.entries.append(dict(name=name, signature=signature, source='', line=1,
                                     doc='Local rustdoc declaration.', url=self.path.as_uri() + ('#' + anchor if anchor else '')))
            self.capture = None


# Rustdoc emits signatures in bounded header fragments. Feeding only those
# through HTMLParser avoids parsing megabytes of examples/sidebar prose.
RUST_DECL = re.compile(r'<(?P<tag>pre|div)\b[^>]*class="[^"]*\bitem-decl\b[^"]*"[^>]*>.*?</(?P=tag)>', re.S)
RUST_METHOD = re.compile(r'<section\b[^>]*\bid="(?:method|tymethod|associatedconstant|associatedtype)\.[^"]+"[^>]*>.{0,32768}?<h4\b[^>]*class="[^"]*\bcode-header\b[^"]*"[^>]*>.*?</h4>', re.S)


def rustdoc(root, module, whole=False):
    selected = root / module if module else root
    entries = []
    paths = selected.rglob('*.html') if module or whole else selected.glob('*.html')
    for path in sorted(paths):
        parser = Rustdoc(path, root)
        text = path.read_text(errors='replace')
        for match in RUST_DECL.finditer(text):
            parser.feed(match.group(0))
        for match in RUST_METHOD.finditer(text):
            parser.feed(match.group(0))
        entries.extend(parser.entries)
    return entries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--language', required=True, choices=list(EXTENSIONS) + ['rustdoc'])
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--file', type=Path)
    parser.add_argument('--include-root', type=Path, action='append', default=[])
    parser.add_argument('--module', default='')
    parser.add_argument('--ctags', default='ctags')
    parser.add_argument('--installed', action='store_true')
    parser.add_argument('--stdlib', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.root = args.root.resolve()
    if not args.root.is_dir():
        parser.error('Index root does not exist')
    if args.language == 'rustdoc':
        entries = rustdoc(args.root.resolve(), args.module, args.stdlib)
    else:
        if args.stdlib:
            paths = standard_headers(args.root, args.language, args.include_root)
        else:
            paths = includes(args.file.resolve(), [args.root.resolve()] + args.include_root) if args.file else list(source_files(args.root, args.language, args.installed))
        entries = tags(args.root, args.language, paths, args.ctags, compact=args.stdlib)
    unique = {(e['name'], e['signature']): e for e in entries}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=args.output.parent, delete=False) as handle:
        json.dump(dict(version=1, entries=list(unique.values())), handle)
        temporary = handle.name
    os.replace(temporary, args.output)
    print(f'Indexed {len(unique)} API declarations')


if __name__ == '__main__':
    main()
