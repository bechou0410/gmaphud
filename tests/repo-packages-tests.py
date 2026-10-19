"""Validate published artifacts and rebuilds using real packages in a temporary source."""
import bz2
import gzip
import hashlib
import lzma
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
GMAPHUD = 'com.chou.googlemaps.vietmap'
COMPANIONS = {'com.chou.ythud': ('YTHUD', 'ythud'), 'com.chou.carplayscale': ('CarPlay Scale', 'carplay-scale')}
HASHES = [('MD5sum', 'md5'), ('SHA1', 'sha1'), ('SHA256', 'sha256'), ('SHA512', 'sha512')]
INDEX_FIELDS = {'Filename', 'Size', *(field for field, _ in HASHES)}


def companion_links(package_id):
    directory = COMPANIONS[package_id][1]
    return {
        'Homepage': f'https://github.com/bechou0410/gmaphud/tree/main/{directory}',
        'Bugs': 'https://github.com/bechou0410/gmaphud/issues',
        'Depiction': f'https://bechou0410.github.io/gmaphud/{directory}/',
        'SileoDepiction': f'https://bechou0410.github.io/gmaphud/{directory}/sileo-depiction.json',
    }


def fields(block):
    result = {}
    key = None
    for line in block.splitlines():
        if line.startswith((' ', '\t')) and key:
            result[key] += '\n' + line
        else:
            key, value = line.split(': ', 1)
            assert key not in result, f'Duplicate field: {key}'
            result[key] = value
    return result


def stanzas(repo):
    return (repo / 'docs/Packages').read_text().strip().split('\n\n')


def validate_repository(repo):
    raw = (repo / 'docs/Packages').read_bytes()
    records = [fields(block) for block in stanzas(repo)]
    gmaphud = [record for record in records if record['Package'] == GMAPHUD]
    companions = [record['Package'] for record in records if record['Package'] != GMAPHUD]
    assert {record['Architecture'] for record in gmaphud} == {'iphoneos-arm', 'iphoneos-arm64'}
    assert len(gmaphud) == 2 and len({record['Version'] for record in gmaphud}) == 1
    assert len(records) == 2 + len(companions) and [record['Package'] for record in records[:2]] == [GMAPHUD, GMAPHUD]
    assert companions == [package_id for package_id in COMPANIONS if package_id in companions], 'Unknown, repeated or reordered companion'

    for record in records:
        assert record['Filename'] == f"pool/{record['Package']}_{record['Version']}_{record['Architecture']}.deb"
        package = repo / 'docs' / record['Filename']
        assert package.is_file() and not package.is_symlink()
        data = package.read_bytes()
        assert len(data) == int(record['Size'])
        for field, algorithm in HASHES:
            assert hashlib.new(algorithm, data).hexdigest() == record[field]
        control = fields(subprocess.check_output(['dpkg-deb', '-f', str(package)], text=True).strip())
        for field in ('Package', 'Version', 'Architecture'):
            assert control[field] == record[field]
        if record['Package'] in COMPANIONS:
            assert record['Architecture'] == 'iphoneos-arm64'
            assert {key: value for key, value in record.items() if key not in INDEX_FIELDS} == control
            for key, value in companion_links(record['Package']).items():
                assert record[key] == value
    indexes = {'Packages': raw}
    for suffix, decode in [('gz', gzip.decompress), ('bz2', bz2.decompress), ('xz', lzma.decompress)]:
        indexes[f'Packages.{suffix}'] = (repo / f'docs/Packages.{suffix}').read_bytes()
        assert decode(indexes[f'Packages.{suffix}']) == raw
    release = (repo / 'docs/Release').read_text()
    for line in ('Origin: GMapHUD', 'Label: GMapHUD', 'Codename: gmaphud',
                 'Architectures: iphoneos-arm iphoneos-arm64'):
        assert line in release.splitlines()
    for field, algorithm in [('MD5Sum', 'md5'), ('SHA256', 'sha256'), ('SHA512', 'sha512')]:
        section = release.split(field + ':\n', 1)[1]
        entries = re.findall(r'^ ([a-f0-9]+) ([0-9]+) (Packages(?:\.(?:gz|bz2|xz))?)$', section, re.MULTILINE)[:4]
        assert len(entries) == 4 and {entry[2] for entry in entries} == indexes.keys()
        for digest, size, filename in entries:
            assert int(size) == len(indexes[filename])
            assert digest == hashlib.new(algorithm, indexes[filename]).hexdigest()
    return records


def snapshot(repo):
    return {str(path.relative_to(repo)): hashlib.sha256(path.read_bytes()).digest()
            for path in (repo / 'docs').rglob('*') if path.is_file()}


def run_builder(repo, packages, success=True):
    before = snapshot(repo)
    result = subprocess.run([sys.executable, str(repo / 'build-repo.py'), *map(str, packages)],
                            capture_output=True, text=True)
    assert (result.returncode == 0) == success, result.stdout + result.stderr
    if not success:
        assert snapshot(repo) == before, 'Rejected publication rewrote the source'
    return result


def repack_package(package, destination, field, value):
    """Change one control field while retaining the real installable package payload."""
    with tempfile.TemporaryDirectory() as temp:
        unpacked = Path(temp) / 'unpacked'
        subprocess.run(['dpkg-deb', '--raw-extract', str(package), str(unpacked)], check=True, capture_output=True)
        control = unpacked / 'DEBIAN/control'
        source = control.read_text()
        source, count = re.subn(r'^' + re.escape(field) + r': .*$', field + ': ' + value, source, flags=re.MULTILINE)
        assert count == 1
        control.write_text(source)
        subprocess.run(['dpkg-deb', '--build', str(unpacked), str(destination)], check=True, capture_output=True)
    return destination


records = validate_repository(ROOT)
with tempfile.TemporaryDirectory(prefix='gmaphud-repo-') as temp:
    repo = Path(temp)
    (repo / 'docs/pool').mkdir(parents=True)
    for filename in ('build-repo.py', 'repo-template.html', 'repo-locales.json', 'DISCLAIMER.vi.md', 'DISCLAIMER.md', 'LICENSE'):
        shutil.copy2(ROOT / filename, repo / filename)
    for filename in ('Packages', 'Packages.gz', 'Packages.bz2', 'Packages.xz', 'Release'):
        shutil.copy2(ROOT / 'docs' / filename, repo / 'docs' / filename)
    for record in records:
        shutil.copy2(ROOT / 'docs' / record['Filename'], repo / 'docs' / record['Filename'])
    gmaphud = [record for record in records if record['Package'] == GMAPHUD]
    packages = [repo / 'docs' / record['Filename'] for record in gmaphud]
    run_builder(repo, packages[:1], success=False)
    run_builder(repo, [packages[0], packages[0]], success=False)
    run_builder(repo, [*packages, packages[0]], success=False)
    changed = repack_package(packages[0], repo / 'different-version.deb', 'Version', gmaphud[0]['Version'] + '+repo-test')
    run_builder(repo, [changed, packages[1]], success=False)
    changed = repack_package(packages[0], repo / 'different-bytes.deb', 'Description', gmaphud[0]['Description'] + ' changed')
    run_builder(repo, [changed, packages[1]], success=False)
    run_builder(repo, packages)
    validate_repository(repo)

    published = [record for record in records if record['Package'] in COMPANIONS]
    if published:
        later_packages = [repack_package(package, repo / f'later-{index}.deb', 'Version', record['Version'] + '+repo-test')
                          for index, (package, record) in enumerate(zip(packages, gmaphud))]
    for companion in published:
        package_id, name = companion['Package'], COMPANIONS[companion['Package']][0]
        artifact = repo / 'docs' / companion['Filename']
        artifact_bytes = artifact.read_bytes()
        # Add the companion to a GMapHUD-only source, then retain it on a later GMapHUD release.
        (repo / 'docs/Packages').write_text('\n\n'.join(block for block in stanzas(repo) if fields(block)['Package'] == GMAPHUD) + '\n')
        run_builder(repo, [*packages, artifact])
        validate_repository(repo)
        retained = next(block for block in stanzas(repo) if fields(block)['Package'] == package_id)
        run_builder(repo, later_packages)
        validate_repository(repo)
        assert next(block for block in stanzas(repo) if fields(block)['Package'] == package_id) == retained
        assert artifact.read_bytes() == artifact_bytes

        original_index = (repo / 'docs/Packages').read_text()
        for field, value in [('Size', '0'), ('SHA256', '0' * 64), ('Filename', '../outside.deb'),
                             ('Architecture', 'iphoneos-arm'), ('Description', 'Changed metadata')]:
            altered = re.sub(r'^' + field + r': .*$', field + ': ' + value, retained, flags=re.MULTILINE)
            (repo / 'docs/Packages').write_text(original_index.replace(retained, altered))
            run_builder(repo, later_packages, success=False)
            (repo / 'docs/Packages').write_text(original_index)
        (repo / 'docs/Packages').write_text(original_index.replace(retained, retained + '\nDepiction: ' + companion_links(package_id)['Depiction']))
        run_builder(repo, later_packages, success=False)
        (repo / 'docs/Packages').write_text(original_index)
        artifact.write_bytes(artifact_bytes + b'changed')
        run_builder(repo, later_packages, success=False)
        artifact.write_bytes(artifact_bytes)
        altered = repack_package(artifact, repo / f'changed-{package_id}.deb', 'Description', companion['Description'] + ' changed')
        run_builder(repo, [*later_packages, altered], success=False)
        wrong_links = repack_package(artifact, repo / f'wrong-depiction-{package_id}.deb', 'Depiction', 'https://bechou0410.github.io/gmaphud/')
        run_builder(repo, [*later_packages, wrong_links], success=False)
        run_builder(repo, [*later_packages, artifact, artifact], success=False)
        artifact.unlink()
        run_builder(repo, later_packages, success=False)
        artifact.write_bytes(artifact_bytes)
        validate_repository(repo)
        print(f'{name} publication, retention, metadata validation and immutable artifacts passed')
    if len(published) > 1:
        # Every companion in one publication keeps the index order of COMPANIONS.
        (repo / 'docs/Packages').write_text('\n\n'.join(block for block in stanzas(repo) if fields(block)['Package'] == GMAPHUD) + '\n')
        run_builder(repo, [*later_packages, *(repo / 'docs' / record['Filename'] for record in reversed(published))])
        assert [fields(block)['Package'] for block in stanzas(repo)] == [GMAPHUD, GMAPHUD, *(record['Package'] for record in published)]
        validate_repository(repo)

print('GMapHUD package pairs, immutable artifacts, compressed indexes and Release checksums passed')
