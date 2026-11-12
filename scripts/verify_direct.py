#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Read-only signature, production isolation and mounted DMG content checks."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

output = Path(sys.argv[1]).resolve()
app = output / '阅读从简.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
exe = app / 'Contents/MacOS/MarginReader'
dmg = output / f'ReadingSimple-{info["CFBundleShortVersionString"]}-arm64.dmg'

def run(args, required=True):
    result = subprocess.run(args, capture_output=True)
    if required and result.returncode:
        raise RuntimeError(f'{args[0]} failed ({result.returncode}): {result.stderr.decode(errors="replace")}')
    return result

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def tree(path):
    return {str(p.relative_to(path)): {'symlink': str(p.readlink())} if p.is_symlink()
            else {'sha256': digest(p)} for p in sorted(path.rglob('*')) if p.is_symlink() or p.is_file()}

assert info['CFBundleIdentifier'] == 'com.haley.MarginReader'
assert info['CFBundleDisplayName'] == '阅读从简'
assert info['NSHumanReadableCopyright'] == '2026 Yanli Tan'
assert info['LSMinimumSystemVersion'] == '14.0'
assert run(['xcrun', 'lipo', '-archs', str(exe)]).stdout.strip() == b'arm64'
run(['codesign', '--verify', '--deep', '--strict', str(app)])
signature = run(['codesign', '-dv', '--verbose=4', str(app)]).stderr.decode()
entitlements = run(['codesign', '-d', '--entitlements', ':-', str(app)]).stdout
entitlements = plistlib.loads(entitlements)
assert entitlements.get('com.apple.security.app-sandbox') is True
assert entitlements.get('com.apple.security.network.client') is True
assert entitlements.get('com.apple.security.files.user-selected.read-write') is True
assert entitlements.get('com.apple.security.get-task-allow') is not True
strings = run(['strings', '-a', str(exe)]).stdout.decode(errors='replace')
symbols = run(['xcrun', 'nm', '-a', str(exe)]).stdout.decode(errors='replace')
for marker in ['IntegrationCLI', '--self-test', '--pdf-test', '--web-test', '--inject-anchor', '--inspect-data', 'READER_TEST_DATA_DIR', 'READER_DIAGNOSTICS']:
    assert marker not in strings and marker not in symbols, marker
for url in ['https://xgchip.github.io/reading-simple/support.html', 'https://xgchip.github.io/reading-simple/privacy.html']:
    assert url in strings
manifests = [str(p.relative_to(app)) for p in app.rglob('PrivacyInfo.xcprivacy')]
assert 'Contents/Resources/PrivacyInfo.xcprivacy' in manifests
assert any('ZIPFoundation' in path for path in manifests)
for notice in ['COPYING.txt', 'ZIPFoundation-LICENSE.txt', 'PaperTexture-LICENSE.txt']:
    assert (app / 'Contents/Resources' / notice).is_file(), notice
assert 'GNU GENERAL PUBLIC LICENSE' in (app / 'Contents/Resources/COPYING.txt').read_text()
source_tree = tree(app)
run(['hdiutil', 'verify', str(dmg)])
with tempfile.TemporaryDirectory(prefix='reading-simple-mount-') as mount:
    mounted = False
    try:
        run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen', '-mountpoint', mount, str(dmg)])
        mounted = True
        root = Path(mount)
        assert (root / 'COPYING.txt').read_bytes() == (app / 'Contents/Resources/COPYING.txt').read_bytes()
        assert (root / '第三方许可/ZIPFoundation-LICENSE.txt').is_file()
        assert (root / '第三方许可/PaperTexture-LICENSE.txt').is_file()
        assert (root / 'Applications').is_symlink()
        assert str((root / 'Applications').readlink()) == '/Applications'
        assert tree(root / '阅读从简.app') == source_tree, 'DMG App differs from output App'
        run(['codesign', '--verify', '--deep', '--strict', str(root / '阅读从简.app')])
    finally:
        if mounted:
            run(['hdiutil', 'detach', mount])
staple = run(['xcrun', 'stapler', 'validate', str(dmg)], required=False)
report = {
    'name': info['CFBundleDisplayName'], 'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'], 'bundle_id': info['CFBundleIdentifier'],
    'architecture': 'arm64', 'minimum_macos': info['LSMinimumSystemVersion'],
    'signature_type': 'ad-hoc' if 'Signature=adhoc' in signature else 'Developer ID' if 'Authority=Developer ID Application:' in signature else 'other',
    'signature_verification_pass': True, 'signing_details': signature,
    'entitlements': entitlements, 'diagnostics_removed': True, 'help_privacy_urls_present': True,
    'privacy_manifests': manifests, 'dmg_verify_pass': True, 'dmg_mount_pass': True,
    'dmg_app_matches_output': True, 'applications_link': '/Applications',
    'stapled_notarization_ticket_valid': staple.returncode == 0,
    'executable_sha256': digest(exe), 'dmg_sha256': digest(dmg),
    'app_tree_sha256': hashlib.sha256(json.dumps(source_tree, sort_keys=True).encode()).hexdigest(),
    'app_files': source_tree,
}
(output / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
(output / 'SHA256SUMS').write_text(f'{report["dmg_sha256"]}  {dmg.name}\n{report["executable_sha256"]}  阅读从简.app/Contents/MacOS/MarginReader\n')
print(json.dumps({key: value for key, value in report.items() if key not in ['app_files', 'signing_details', 'entitlements']}, ensure_ascii=False, indent=2))
