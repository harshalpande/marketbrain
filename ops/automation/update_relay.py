"""Attended upgrade of existing relay code only; pairing and queue retained."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


def main():
    if os.geteuid() != 0:
        raise SystemExit('Run with sudo')
    source = Path(sys.argv[1]).read_bytes()
    if hashlib.sha256(source).hexdigest() != sys.argv[2]:
        raise SystemExit('SOURCE_HASH_MISMATCH')
    compile(source, 'relay.py', 'exec')
    target = Path('/opt/marketbrain-automation/relay.py')
    if not target.is_file() or target.is_symlink() or target.stat().st_uid != 0:
        raise SystemExit('EXISTING_ROOT_OWNED_RELAY_REQUIRED')
    unit = 'marketbrain-automation.service'
    def run(*args):
        return subprocess.run(args, check=True, capture_output=True, timeout=30)
    run('systemctl', 'is-active', '--quiet', unit)
    backup = Path(tempfile.mkdtemp(prefix='marketbrain-relay-backup-', dir='/var/backups')) / 'relay.py'
    shutil.copy2(target, backup)
    run('systemctl', 'stop', unit)
    try:
        staged = target.with_suffix('.new')
        staged.write_bytes(source)
        staged.chmod(0o644)
        os.replace(staged, target)
        run('systemctl', 'start', unit)
        time.sleep(3)
        run('systemctl', 'is-active', '--quiet', unit)
        print('RELAY_TEST_EXECUTION_UPDATED; existing queue and pairing preserved')
    except Exception:
        run('systemctl', 'stop', unit)
        shutil.copy2(backup, target)
        run('systemctl', 'start', unit)
        raise


if __name__ == '__main__':
    main()
