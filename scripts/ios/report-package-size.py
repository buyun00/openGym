"""Report exported IPA size and ensure the native offline media copy is complete."""
import os
from pathlib import Path
import sys
import zipfile


def main():
    ipa = Path(sys.argv[1])
    source = Path(__file__).resolve().parents[2] / 'catalogue' / 'media'
    expected = {p.relative_to(source).as_posix(): p.stat().st_size
                for p in source.rglob('*') if p.is_file()}
    with zipfile.ZipFile(ipa) as package:
        entries = [entry for entry in package.infolist() if not entry.is_dir()]
        roots = {entry.filename.split('/')[1] for entry in entries
                 if entry.filename.startswith('Payload/') and len(entry.filename.split('/')) > 2}
        if len(roots) != 1:
            raise SystemExit('Expected one app in the exported IPA')
        prefix = 'Payload/' + roots.pop() + '/'
        media_prefix = prefix + 'media/'
        media = [entry for entry in entries if entry.filename.startswith(media_prefix)]
        actual = {entry.filename[len(media_prefix):]: entry.file_size for entry in media}
        if not expected or actual != expected:
            raise SystemExit('Native offline media is missing, incomplete, or differs in size')
        if any(entry.filename.startswith(prefix + 'public/exercise-media/') for entry in entries):
            raise SystemExit('Duplicate web exercise media remains in the IPA')
        size = ipa.stat().st_size
        compressed_media = sum(entry.compress_size for entry in media)
        # Previous successful build's altool transfer log, not installed device size.
        baseline = 419095469  # 1.0.1 (13.1), run 41966686872
        report = (
            f'IPA size: {size:,} bytes ({size / 1_000_000:.2f} MB).\n'
            f'Compared with 1.0.1 (13.1) upload ({baseline / 1_000_000:.2f} MB): '
            f'{(baseline - size) / 1_000_000:.2f} MB smaller '
            f'({(baseline - size) / baseline:.1%}).\n'
            f'Offline media: {len(media):,} files, '
            f'{sum(expected.values()) / 1_000_000:.2f} MB uncompressed, '
            f'{compressed_media / 1_000_000:.2f} MB compressed; complete single native copy.\n'
            'IPA/upload sizes are not the installed size or Apple device-specific download size.\n'
        )
        print(report)
        if os.environ.get('GITHUB_STEP_SUMMARY'):
            with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as summary:
                summary.write(report)


if __name__ == '__main__':
    main()
