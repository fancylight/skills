"""Exercise the actual Git inventory in an isolated repository."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

MODULE = Path(__file__).resolve().parents[2] / 'skills/flow-codex-check/scripts/git-scope.py'
spec = importlib.util.spec_from_file_location('git_scope', MODULE)
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)


class InventoryTest(unittest.TestCase):
    def test_all_layers_and_explicit_baseline(self):
        with tempfile.TemporaryDirectory() as tmp:
            def run(*args):
                return subprocess.check_output(['git', '-C', tmp, *args]).decode().strip()
            run('init', '-q')
            run('config', 'user.name', 'fixture')
            run('config', 'user.email', 'fixture@example.invalid')
            p = Path(tmp) / '业务 file.txt'
            p.write_text('base', encoding='utf-8')
            run('add', '.')
            run('commit', '-qm', 'baseline')
            base = run('rev-parse', 'HEAD')
            p.write_text('committed', encoding='utf-8')
            run('commit', '-qam', 'change')
            p.write_text('staged', encoding='utf-8')
            run('add', '.')
            p.write_text('unstaged', encoding='utf-8')
            (Path(tmp) / 'extra.json').write_text('{}')
            before = run('status', '--porcelain')
            result = scope.inventory(tmp, base)
            for layer in ('committed', 'staged', 'unstaged'):
                self.assertEqual(result[layer], [{'status': 'M', 'path': p.name}])
            self.assertEqual(result['untracked'], ['extra.json'])
            self.assertEqual(scope.inventory(tmp)['committedScope'], 'UNVERIFIED')
            self.assertEqual(before, run('status', '--porcelain'))
            run('reset', '--hard', '-q')
            p.unlink()
            self.assertEqual(scope.inventory(tmp, base)['unstaged'][0]['status'], 'D')
            with self.assertRaises(ValueError):
                scope.inventory(tmp, 'missing-ref')


if __name__ == '__main__':
    unittest.main()
