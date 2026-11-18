"""POSIX regression for the actual installer statements under launcher umask."""
import ast
import os
from pathlib import Path
import shutil
import stat
import tempfile
import unittest


@unittest.skipUnless(os.name == 'posix', 'Requires POSIX permission semantics')
class InstallerPermissions(unittest.TestCase):
    def test_code_traversable_but_secret_state_private_under_umask_077(self):
        installer = Path(__file__).with_name('install_relay.py')
        tree = ast.parse(installer.read_text())
        # Execute the real creation block, without accounts, systemd or network.
        start = next(i for i, n in enumerate(tree.body) if isinstance(n, ast.Expr) and ast.unparse(n.value).startswith('root.mkdir('))
        end = next(i for i, n in enumerate(tree.body) if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'tokens' for t in n.targets))
        block = compile(ast.Module(body=tree.body[start:end], type_ignores=[]), str(installer), 'exec')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'code'
            state = Path(temporary) / 'private'
            previous = os.umask(0o077)
            try:
                exec(block, dict(root=root, state=state, os=os, shutil=shutil, Path=Path, __file__=str(installer)))
            finally:
                os.umask(previous)
            self.assertEqual(stat.S_IMODE(root.stat().st_mode), 0o755)
            self.assertEqual(stat.S_IMODE((root / 'relay.py').stat().st_mode), 0o644)
            self.assertEqual(stat.S_IMODE(state.stat().st_mode), 0o700)


if __name__ == '__main__':
    unittest.main()
