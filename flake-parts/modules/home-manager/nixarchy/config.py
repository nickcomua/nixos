#!/usr/bin/env python3
"""Save and restore the explicitly supported, mutable part of this desktop."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

VERSION = 1
SNAPSHOT_REL = Path('flake-parts/hosts/nixos/desktop')
SINGLE = ['.config/mimeapps.list', '.config/xdg-terminals.list',
          '.config/ddcutil/ddcutilrc', '.config/omarchy/nixi.json',
          '.config/omarchy/shell.json', '.local/state/omarchy/current/theme.name']
TREES = ['.config/omarchy/defaults', '.config/omarchy/extensions',
         '.config/omarchy/branding', '.config/omarchy/hooks',
         '.local/state/omarchy/toggles', '.local/state/omarchy/current/theme']
SKIP = {'.git', '.jj', '__pycache__', '.cache', 'node_modules'}
SECRET = re.compile(r'^(api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret)$', re.I)


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def output(*args):
    return run(*args, stdout=subprocess.PIPE).stdout.strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(value):
    p = Path(value)
    if p.is_absolute() or '..' in p.parts or not p.parts:
        raise ValueError(f'Unsafe relative path: {value}')
    return p


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as f:
        f.write(content)
        tmp = Path(f.name)
    os.replace(tmp, path)  # Replace a symlink, never write through it.


def json_write(path, value):
    atomic_write(path, (json.dumps(value, indent=2, sort_keys=True) + '\n').encode())


def validate(path):
    if path.suffix in ('.json', '.jsonc'):
        text = path.read_text()
        if path.suffix == '.jsonc':
            quoted = r'"(?:\\.|[^"\\])*"'
            text = re.sub(quoted + r'|//[^\n]*|/\*[\s\S]*?\*/',
                          lambda match: match[0] if match[0].startswith('"') else '', text)
            text = re.sub(quoted + r'|,\s*(?=[}\]])',
                          lambda match: match[0] if match[0].startswith('"') else '', text)
        data = json.loads(text)
        def scan(value):
            if isinstance(value, dict):
                for key, item in value.items():
                    if SECRET.match(key) and item:
                        raise ValueError(f'{path}: credential-like field {key}; move it out of desktop settings')
                    scan(item)
            elif isinstance(value, list):
                for item in value:
                    scan(item)
        scan(data)
    elif path.suffix == '.lua':
        run('luac', '-p', str(path), stdout=subprocess.DEVNULL)
    elif path.suffix == '.nix':
        run('nix-instantiate', '--parse', str(path), stdout=subprocess.DEVNULL)


def copy_tree(source, dest):
    """Copy local code/assets; reject links escaping the selected source tree."""
    root = source.resolve()
    for current, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in SKIP)
        for name in list(dirs):
            if (Path(current) / name).is_symlink():
                raise ValueError(f'Directory symlink needs manual export: {Path(current) / name}')
        for name in sorted(files):
            p = Path(current) / name
            if not p.resolve().is_relative_to(root):
                raise ValueError(f'Source symlink escapes its directory: {p}')
            target = dest / p.relative_to(root)
            atomic_write(target, p.read_bytes())
            target.chmod(p.stat().st_mode & 0o777 | 0o600)


def supported_files(home):
    result = set()
    for rel in SINGLE:
        if (home / rel).is_file():
            result.add(rel)
    for folder in TREES:
        root = home / folder
        if root.is_dir():
            for p in root.rglob('*'):
                if p.is_file() and not any(part in SKIP for part in p.relative_to(root).parts):
                    # Current theme includes links to upstream assets, but never
                    # follow arbitrary links outside home or the Nix store.
                    actual = p.resolve()
                    if not (actual.is_relative_to(home.resolve()) or actual.is_relative_to('/nix/store')):
                        raise ValueError(f'External config symlink: {p}')
                    result.add(str(p.relative_to(home)))
    for p in (home / '.config/hypr').glob('*.lua'):
        result.add(str(p.relative_to(home)))
    for p in (home / '.config/nixarchy').rglob('*.nix'):
        result.add(str(p.relative_to(home)))
    return sorted(result)


def source_dirs(home):
    for category in ['plugins', 'themes']:
        root = home / '.config/omarchy' / category
        if root.is_dir():
            for p in sorted(root.iterdir()):
                if p.is_dir() and not p.name.startswith('.'):
                    # Nixi and plugins explicitly declared in a Nix module are
                    # already reproduced by that module and flake.lock. Do not
                    # vendor their store links or remove them during restore.
                    if p.is_symlink() and str(p.resolve()).startswith('/nix/store/'):
                        continue
                    yield f'{category}/{p.name}', p


def tree_hash(path):
    path = path.resolve()
    h = hashlib.sha256()
    for current, dirs, files in os.walk(path, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in SKIP)
        for name in dirs:
            if (Path(current) / name).is_symlink():
                raise ValueError(f'Directory symlink needs manual export: {Path(current) / name}')
        for name in sorted(files):
            p = Path(current) / name
            if not p.resolve().is_relative_to(path):
                raise ValueError(f'Source symlink escapes its directory: {p}')
            h.update(str(p.relative_to(path)).encode())
            h.update(str(p.stat().st_mode & 0o111).encode())
            h.update(p.read_bytes())
    return h.hexdigest()


def read_manifest(snapshot):
    m = json.loads((snapshot / 'manifest.json').read_text())
    if m.get('version') != VERSION:
        raise ValueError('Unsupported desktop snapshot version')
    for name in m['files']:
        relative(name)
        if not (name.startswith(('.config/', '.local/state/omarchy/', '.local/share/nixarchy-config/'))):
            raise ValueError(f'Unsupported snapshot path: {name}')
        p = snapshot / 'files' / name
        if digest(p) != m['files'][name]:
            raise ValueError(f'Snapshot checksum mismatch: {name}')
        validate(p)
    for name, spec in m['sources'].items():
        relative(name)
        if name.split('/')[0] not in ['plugins', 'themes'] or len(Path(name).parts) != 2:
            raise ValueError(f'Invalid source name: {name}')
        if spec['kind'] == 'local':
            relative(spec['path'])
            if tree_hash(snapshot / 'sources' / spec['path']) != spec['contentHash']:
                raise ValueError(f'Source checksum mismatch: {name}')
        elif spec['kind'] != 'git':
            raise ValueError(f'Unknown source type: {name}')
    return m


def capture(home, dest, previous=None, pin=True, validate_content=True):
    manifest = dict(version=VERSION, complete=True, theme='tokyo-night', background=None, files={}, sources={})
    for rel in supported_files(home):
        source = home / rel
        if validate_content:
            validate(source)
        target = dest / 'files' / rel
        atomic_write(target, source.read_bytes())
        if validate_content and target.suffix == '.nix':
            run('alejandra', '--quiet', str(target), stdout=subprocess.DEVNULL)
        target.chmod(source.stat().st_mode & 0o777)
        manifest['files'][rel] = digest(target)
    theme = home / '.local/state/omarchy/current/theme.name'
    if theme.is_file():
        manifest['theme'] = theme.read_text().strip()
    background = home / '.local/state/omarchy/current/background'
    if background.is_file():
        name = digest(background) + background.resolve().suffix
        rel = '.local/share/nixarchy-config/assets/' + name
        atomic_write(dest / 'files' / rel, background.read_bytes())
        manifest['files'][rel] = digest(background)
        manifest['background'] = rel
    for name, path in source_dirs(home):
        content_hash = tree_hash(path)
        old = (previous or {}).get('sources', {}).get(name)
        spec = None
        if pin and old and old['kind'] == 'git' and old['contentHash'] == content_hash:
            spec = old
        elif pin and (path / '.git').exists():
            # Git is used only to inspect third-party plugin sources, never to
            # manage this repository (that is Jujutsu's responsibility).
            dirty = output('git', '-C', str(path), 'status', '--porcelain', '--untracked-files=all')
            if not dirty:
                url = output('git', '-C', str(path), 'remote', 'get-url', 'origin')
                if url.startswith('https://') and '@' not in url.split('/')[2]:
                    rev = output('git', '-C', str(path), 'rev-parse', 'HEAD')
                    fetched = json.loads(output('nix-prefetch-git', '--quiet', '--url', url, '--rev', rev))
                    if tree_hash(Path(fetched['path'])) == content_hash:
                        sri = output('nix', 'hash', 'convert', '--hash-algo', 'sha256',
                                     '--to', 'sri', fetched['sha256'])
                        spec = dict(kind='git', url=url, rev=rev, hash=sri, contentHash=content_hash)
        if spec is None:
            copy_tree(path, dest / 'sources' / name)
            spec = dict(kind='local', path=name, contentHash=content_hash)
        if validate_content and name.startswith('plugins/'):
            data = json.loads((path / 'manifest.json').read_text())
            if data.get('id') != path.name:
                raise ValueError(f'Plugin id does not match directory: {name}')
            if shutil.which('omarchy-plugin-validate'):
                run('omarchy-plugin-validate', str(path))
        manifest['sources'][name] = spec
    json_write(dest / 'manifest.json', manifest)
    return manifest


def replace_directory(staging, destination):
    old = destination.with_name(destination.name + '.previous')
    if old.exists():
        raise ValueError(f'Interrupted earlier export: inspect {old} before retrying')
    if destination.exists():
        destination.rename(old)
    try:
        staging.rename(destination)
    except BaseException:
        if old.exists():
            old.rename(destination)
        raise
    if old.exists():
        shutil.rmtree(old)


def differences(home, manifest):
    diffs = []
    for rel, expected in manifest['files'].items():
        p = home / rel
        actual = None
        if p.is_file():
            actual = digest(p)
            if p.suffix == '.nix':
                formatted = subprocess.run(['alejandra', '--quiet'], input=p.read_text(),
                                           capture_output=True, text=True)
                if formatted.returncode == 0:
                    actual = hashlib.sha256(formatted.stdout.encode()).hexdigest()
        if actual != expected:
            diffs.append(rel)
    if manifest.get('complete'):
        diffs.extend(sorted(set(supported_files(home)) - manifest['files'].keys()))
    live_sources = dict(source_dirs(home))
    for name, spec in manifest['sources'].items():
        if name not in live_sources or tree_hash(live_sources[name]) != spec['contentHash']:
            diffs.append('source:' + name)
    if manifest.get('complete'):
        diffs.extend('source:' + name for name in live_sources.keys() - manifest['sources'].keys())
    background = home / '.local/state/omarchy/current/background'
    if manifest['background'] and (not background.is_file() or digest(background) != manifest['files'][manifest['background']]):
        diffs.append('background')
    return sorted(set(diffs))


def resolve_sources(snapshot, manifest, source_map):
    result = {}
    for name, spec in manifest['sources'].items():
        if spec['kind'] == 'local':
            path = snapshot / 'sources' / spec['path']
        elif name in source_map:
            path = Path(source_map[name])
        else:
            fetched = json.loads(output('nix-prefetch-git', '--quiet', '--url', spec['url'], '--rev', spec['rev']))
            if fetched['sha256'] != spec['hash']:
                raise ValueError(f'Source hash mismatch: {name}')
            path = Path(fetched['path'])
        if tree_hash(path) != spec['contentHash']:
            raise ValueError(f'Realized source contents differ: {name}')
        result[name] = path
    return result


def install(home, snapshot, manifest, sources, overwrite=False):
    if overwrite and manifest.get('complete'):
        for rel in set(supported_files(home)) - manifest['files'].keys():
            (home / rel).unlink()
        for name, path in source_dirs(home):
            if name not in sources:
                if path.is_symlink():
                    path.unlink()
                else:
                    shutil.rmtree(path)
    for name, source in sources.items():
        dest = home / '.config/omarchy' / relative(name)
        if overwrite and dest.exists():
            if dest.is_symlink():
                dest.unlink()
            else:
                shutil.rmtree(dest)
        if not dest.exists():
            copy_tree(source, dest)
    for rel in manifest['files']:
        dest = home / relative(rel)
        if not overwrite and dest.is_symlink() and str(dest.resolve()).startswith('/nix/store/'):
            # Materialize former Home Manager files before linkGeneration
            # removes the obsolete link. Preserve their current contents.
            atomic_write(dest, dest.read_bytes())
        if overwrite or not dest.exists():
            src = snapshot / 'files' / rel
            atomic_write(dest, src.read_bytes())
            dest.chmod(src.stat().st_mode & 0o777 | 0o600)
    if manifest['background']:
        target = home / '.local/state/omarchy/current/background'
        if overwrite or not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            target.unlink(missing_ok=True)
            target.symlink_to(home / manifest['background'])


def backup(home):
    root = home / '.local/state/nixarchy-config/backups'
    root.mkdir(parents=True, exist_ok=True)
    dest = Path(tempfile.mkdtemp(prefix=time.strftime('%Y%m%d-%H%M%S-'), dir=root))
    capture(home, dest, pin=False, validate_content=False)
    print(f'Backup: {dest}')
    return dest


def apply_apps(home, repo):
    src = home / '.config/nixarchy'
    selected = [p for p in src.rglob('*.nix') if p.is_file()]
    if not selected:
        raise ValueError('No app selections yet; choose an app in the Install menu first')
    for path in selected:
        validate(path)
    snapshot = repo / SNAPSHOT_REL
    manifest = read_manifest(snapshot)
    backup_dir = home / '.local/state/nixarchy-config/apply-backups' / str(time.time_ns())
    shutil.copytree(snapshot, backup_dir)
    stage = Path(tempfile.mkdtemp(prefix='.desktop-apply-', dir=snapshot.parent))
    try:
        shutil.copytree(snapshot, stage, dirs_exist_ok=True)
        dest = stage / 'files/.config/nixarchy'
        if dest.exists():
            shutil.rmtree(dest)
        manifest['files'] = {k: v for k, v in manifest['files'].items() if not k.startswith('.config/nixarchy/')}
        for path in selected:
            rel = '.config/nixarchy/' + str(path.relative_to(src))
            atomic_write(stage / 'files' / rel, path.read_bytes())
            run('alejandra', '--quiet', str(stage / 'files' / rel), stdout=subprocess.DEVNULL)
            manifest['files'][rel] = digest(stage / 'files' / rel)
        json_write(stage / 'manifest.json', manifest)
        read_manifest(stage)
        replace_directory(stage, snapshot)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    run('jj', '-R', str(repo), 'status')
    run('nix', 'eval', str(repo) + '#nixosConfigurations.nixos.config.system.build.toplevel.drvPath', '--raw')
    run('nh', 'os', 'switch', str(repo), '--hostname', 'nixos',
        '--elevation-strategy', '/run/wrappers/bin/pkexec')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['export', 'status', 'restore', 'seed', 'apply'])
    parser.add_argument('--home', type=Path, default=Path.home())
    parser.add_argument('--repo', type=Path, default=Path(os.environ.get('NIXARCHY_FLAKE', '/home/nick/.config/nixos')))
    parser.add_argument('--snapshot', type=Path)
    args = parser.parse_args()
    home, repo = args.home.resolve(), args.repo.resolve()
    state = home / '.local/state/nixarchy-config'
    state.mkdir(parents=True, exist_ok=True)
    with (state / 'lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        committed = repo / SNAPSHOT_REL
        snapshot = args.snapshot or (Path(os.environ['NIXARCHY_SNAPSHOT']) if args.command == 'seed' else committed)
        if args.command == 'apply':
            apply_apps(home, repo)
            return
        manifest = read_manifest(snapshot)
        if args.command == 'status':
            diff = differences(home, manifest)
            print('\n'.join(diff) if diff else 'Desktop matches the saved configuration.')
            return
        if args.command == 'export':
            committed.parent.mkdir(parents=True, exist_ok=True)
            stage = Path(tempfile.mkdtemp(prefix='.desktop-export-', dir=committed.parent))
            try:
                capture(home, stage, manifest)
                read_manifest(stage)
                replace_directory(stage, committed)
            finally:
                if stage.exists():
                    shutil.rmtree(stage)
            run('jj', '-R', str(repo), 'status')
            known = set(supported_files(home))
            unknown = [str(p.relative_to(home)) for p in (home / '.config/omarchy').rglob('*')
                       if p.is_file() and str(p.relative_to(home)) not in known
                       and not set(p.relative_to(home / '.config/omarchy').parts) & {'plugins', 'themes'}]
            if unknown:
                print('Desktop files outside the export schema (not captured):\n' + '\n'.join(sorted(unknown)))
            print('Desktop exported. Review with jj diff; no rebuild or commit was made.')
            return
        source_map = {}
        if args.command == 'seed' and os.environ.get('NIXARCHY_SOURCES'):
            source_map = json.loads(Path(os.environ['NIXARCHY_SOURCES']).read_text())
        sources = resolve_sources(snapshot, manifest, source_map)
        if args.command == 'restore':
            backup(home)
            install(home, snapshot, manifest, sources, overwrite=True)
            print('Saved desktop restored. Log out and back in to load all settings.')
        else:
            marker = state / 'migrated'
            if not marker.exists():
                # Preserve old configs before Home Manager removes its old links.
                legacy = state / 'legacy-desktop'
                for folder in ['hypr', 'noctalia', 'satty']:
                    src = home / '.config' / folder
                    if src.exists() and not (legacy / folder).exists():
                        shutil.copytree(src, legacy / folder, symlinks=False)
                install(home, snapshot, manifest, sources)
                marker.touch()
            drift = differences(home, manifest)
            if drift:
                print('Kept live desktop edits; run nixarchy-config status or export.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'nixarchy-config: {error}', file=sys.stderr)
        sys.exit(1)
