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
    def test_rename_binary_and_non_head_target_are_read_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            def run(*args):
                return subprocess.check_output(['git', '-C', tmp, *args]).decode().strip()
            run('init', '-q')
            run('config', 'user.name', 'fixture')
            run('config', 'user.email', 'fixture@example.invalid')
            root = Path(tmp)
            (root / 'old name.txt').write_text('same content', encoding='utf-8')
            (root / 'asset.bin').write_bytes(b'\x00\x01base')
            run('add', '.')
            run('commit', '-qm', 'baseline')
            base = run('rev-parse', 'HEAD')
            run('mv', 'old name.txt', '新 name.txt')
            (root / 'asset.bin').write_bytes(b'\x00\x02changed')
            run('add', '.')
            run('commit', '-qm', 'rename and binary')
            target = run('rev-parse', 'HEAD')
            (root / 'later.txt').write_text('outside selected target')
            run('add', '.')
            run('commit', '-qm', 'later commit')
            (root / 'asset.bin').write_bytes(b'\x00\x03workspace')
            (root / 'untracked.bin').write_bytes(b'\x00\xff')
            before = {p.relative_to(root): p.read_bytes() for p in root.rglob('*') if p.is_file()}
            result = scope.inventory(tmp, base, target)
            self.assertEqual(result['target'], target)
            self.assertNotEqual(result['head'], target)
            self.assertEqual({(r['status'], r['path']) for r in result['committed']},
                             {('D', 'old name.txt'), ('A', '新 name.txt'), ('M', 'asset.bin')})
            self.assertEqual(result['unstaged'], [{'status': 'M', 'path': 'asset.bin'}])
            self.assertEqual(result['untracked'], ['untracked.bin'])
            self.assertEqual(result['staged'], [])
            with self.assertRaises(ValueError):
                scope.inventory(tmp, base, '--invalid-target')
            after = {p.relative_to(root): p.read_bytes() for p in root.rglob('*') if p.is_file()}
            self.assertEqual(before, after, 'Inventory must not alter files or Git metadata')

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
