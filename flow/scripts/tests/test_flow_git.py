"""Real temporary Git repositories; no installed hooks or user repos are changed."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / 'flow/scripts/flow-git.py'
INSTALL = ROOT / 'codex/scripts/install-git-hook.py'


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


flow = load('flow_git', SCRIPT)
installer = load('flow_hook_install', INSTALL)


class FlowGitTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='flow git 测试 ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.new_repo('business')
        self.base = flow.git(self.repo, 'rev-parse', 'HEAD')
        result = self.cli('init', '--root', self.root, '--issue', 'GLW-92995', '--title', '考勤展示优化',
                          '--slug', 'attendance-display', '--delivery-date', '20260930')
        self.change = Path(result['change_file'])
        self.expected = result['branch']

    def new_repo(self, name):
        repo = self.root / name
        repo.mkdir()
        flow.git(repo, 'init', '-b', 'main')
        flow.git(repo, 'config', 'user.name', 'Flow Test')
        flow.git(repo, 'config', 'user.email', 'flow-test@example.invalid')
        flow.git(repo, 'config', 'commit.gpgsign', 'false')
        # Neutralize ambient user/system hook paths for isolated tests, never the real user config.
        empty_hooks = self.root / 'empty-hooks'
        empty_hooks.mkdir(exist_ok=True)
        flow.git(repo, 'config', 'core.hooksPath', str(empty_hooks))
        (repo / 'a.txt').write_text('baseline\n', encoding='utf-8')
        flow.git(repo, 'add', 'a.txt')
        flow.git(repo, 'commit', '-m', 'initial manual commit')
        return repo

    def cli(self, *args, ok=True):
        result = subprocess.run([sys.executable, str(SCRIPT), *map(str, args)],
                                capture_output=True, encoding='utf-8')
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def bind(self, repo=None):
        repo = repo or self.repo
        self.cli('bind', '--repo', repo, '--change', self.change)
        self.cli('create-branch', '--repo', repo, '--base', 'main')

    def test_legacy_service_branch_is_workdir_bound(self):
        legacy = self.root / '.flow/changes/legacy'
        legacy.mkdir(parents=True)
        self.cli('adopt', '--change-dir', legacy, '--repo', self.repo,
                 '--issue', 'glw-92524', '--title', '存量需求')
        service = self.new_repo('service')
        flow.git(service, 'switch', '-c', 'feature/legacy-st-local')
        self.cli('bind', '--repo', service, '--change', legacy / 'change.json', '--existing')
        self.assertEqual(flow.check_branch(service)['requirement_id'], 'glw-92524')
        self.cli('bind', '--repo', self.repo, '--change', self.change, '--existing', ok=False)
        copied = flow.read(flow.git_dir(service) / flow.CONTEXT)
        flow.write(flow.git_dir(self.repo) / flow.CONTEXT, copied)
        with self.assertRaises(ValueError):
            flow.context(self.repo)
    def message(self, value):
        path = self.root / '消息.txt'
        path.write_text(value, encoding='utf-8')
        return path

    def pending(self):
        (self.repo / 'a.txt').write_text('changed\n', encoding='utf-8')
        flow.git(self.repo, 'add', 'a.txt')

    def test_identity_and_no_overwrite(self):
        self.assertEqual(flow.metadata(self.change)['requirement_id'], 'glw-92995')
        self.assertEqual(self.change.parent.name, 'attendance-display-20260930')
        self.cli('init', '--root', self.root, '--issue', 'glw-1', '--title', '另一个需求',
                 '--slug', 'attendance-display', '--delivery-date', '20260930', ok=False)
        for value in ('20260230', '2026-09-30', '202609'):
            self.cli('init', '--root', self.root, '--issue', 'glw-1', '--title', '需求',
                     '--slug', 'another', '--delivery-date', value, ok=False)
        self.cli('init', '--root', self.root, '--title', '需求', '--slug', 'another',
                 '--delivery-date', '20260930', ok=False)

    def test_message_types_and_chinese(self):
        ctx = {'requirement_id': 'glw-92995'}
        for kind in flow.TYPES:
            flow.validate_message('glw-92995 ' + kind + ' 更新 API 契约\n\n说明影响范围', ctx)
        for value in ('glw-2 fix 修复问题', 'GLW-92995 fix 修复问题', 'glw-92995 fix: 修复问题',
                      'glw-92995 other 修复问题', 'glw-92995 fix English only', 'glw-92995 fix | 修复',
                      'glw-92995 fix  修复', 'glw-92995 fix 修复\n\nEnglish body'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                flow.validate_message(value, ctx)

    def test_branch_before_commit_and_no_upstream(self):
        self.cli('bind', '--repo', self.repo, '--change', self.change)
        self.pending()
        before = flow.git(self.repo, 'rev-parse', 'HEAD')
        self.cli('commit', '--repo', self.repo, '--message-file', self.message('glw-92995 fix 修复'), ok=False)
        self.cli('create-branch', '--repo', self.repo, '--base', 'main', ok=False)
        self.assertEqual(flow.git(self.repo, 'rev-parse', 'HEAD'), before)

    def test_git_root_initial_identity_only(self):
        data = self.cli('init', '--root', self.repo, '--issue', 'glw-123', '--title', '根仓需求',
                        '--slug', 'root-change', '--delivery-date', '20260930')
        self.cli('bind', '--repo', self.repo, '--change', data['change_file'])
        extra = self.repo / 'unrelated.txt'
        extra.write_text('user work', encoding='utf-8')
        self.cli('create-branch', '--repo', self.repo, '--base', 'main', ok=False)
        extra.unlink()
        self.cli('create-branch', '--repo', self.repo, '--base', 'main')
        self.assertEqual(flow.branch(self.repo), data['branch'])

    def test_switch_existing_bound_branch_preserves_history(self):
        self.bind()
        flow.git(self.repo, 'commit', '--allow-empty', '-m', 'existing feature work')
        expected_head = flow.git(self.repo, 'rev-parse', 'HEAD')
        flow.git(self.repo, 'switch', 'main')
        result = self.cli('switch-branch', '--repo', self.repo, '--branch', self.expected)
        self.assertEqual(result['branch'], self.expected)
        self.assertEqual(flow.git(self.repo, 'rev-parse', 'HEAD'), expected_head)
        self.assertEqual(flow.git(self.repo, 'rev-parse', 'main'), self.base)
        self.cli('check-branch', '--repo', self.repo)
        command = 'python flow-git.py switch-branch --repo . --branch ' + self.expected
        self.assertEqual(flow.hook({'cwd': str(self.repo), 'tool_input': {'cmd': command}}), {})

    def test_switch_rejects_wrong_missing_or_stale_binding(self):
        self.cli('bind', '--repo', self.repo, '--change', self.change)
        self.cli('switch-branch', '--repo', self.repo, '--branch', self.expected, ok=False)
        self.assertEqual(flow.branch(self.repo), 'main')
        self.cli('create-branch', '--repo', self.repo, '--base', 'main')
        flow.git(self.repo, 'switch', 'main')
        self.cli('switch-branch', '--repo', self.repo, '--branch', 'main', ok=False)
        data = flow.read(self.change)
        data['requirement_id'] = 'glw-123'
        flow.write(self.change, data)
        self.cli('switch-branch', '--repo', self.repo, '--branch', self.expected, ok=False)
        self.assertEqual(flow.branch(self.repo), 'main')

    def test_switch_preserves_dirty_work_and_in_progress_operations(self):
        self.bind()
        flow.git(self.repo, 'switch', 'main')
        for staged in (False, True):
            (self.repo / 'a.txt').write_text('user changes\n', encoding='utf-8')
            if staged:
                flow.git(self.repo, 'add', 'a.txt')
            self.cli('switch-branch', '--repo', self.repo, '--branch', self.expected, ok=False)
            self.assertEqual(flow.branch(self.repo), 'main')
            self.assertEqual((self.repo / 'a.txt').read_text(), 'user changes\n')
        flow.git(self.repo, 'restore', '--staged', 'a.txt')
        flow.git(self.repo, 'restore', 'a.txt')
        merge_head = flow.git_dir(self.repo) / 'MERGE_HEAD'
        merge_head.write_text(self.base + '\n', encoding='utf-8')
        self.cli('switch-branch', '--repo', self.repo, '--branch', self.expected, ok=False)
        self.assertTrue(merge_head.exists())
        self.assertEqual(flow.branch(self.repo), 'main')

    def test_switch_preserves_untracked_evidence_same_and_different_heads(self):
        self.bind()
        flow.git(self.repo, 'switch', 'main')
        evidence = self.repo / 'changes/attendance-display/evidence/result.bin'
        evidence.parent.mkdir(parents=True)
        content = b'original evidence\x00\xff\n'
        evidence.write_bytes(content)
        self.cli('switch-branch', '--repo', self.repo, '--branch', self.expected)
        self.assertEqual(evidence.read_bytes(), content)
        self.assertEqual(flow.git(self.repo, 'rev-parse', 'HEAD'), self.base)
        (self.repo / 'feature.txt').write_text('feature', encoding='utf-8')
        flow.git(self.repo, 'add', 'feature.txt')
        flow.git(self.repo, 'commit', '-m', 'feature change')
        expected_head = flow.git(self.repo, 'rev-parse', 'HEAD')
        flow.git(self.repo, 'switch', 'main')
        self.cli('switch-branch', '--repo', self.repo, '--branch', self.expected)
        self.assertEqual(evidence.read_bytes(), content)
        self.assertEqual(flow.git(self.repo, 'rev-parse', 'HEAD'), expected_head)
        self.assertEqual(flow.git(self.repo, 'diff', '--cached', '--name-only'), '')

    def test_switch_rejects_untracked_and_ignored_file_collisions(self):
        self.bind()
        collision = self.repo / 'collision.txt'
        collision.write_text('tracked on feature', encoding='utf-8')
        flow.git(self.repo, 'add', 'collision.txt')
        flow.git(self.repo, 'commit', '-m', 'feature file')
        flow.git(self.repo, 'switch', 'main')
        for ignored in (False, True):
            with self.subTest(ignored=ignored):
                if ignored:
                    (flow.git_dir(self.repo) / 'info/exclude').write_text('collision.txt\n', encoding='utf-8')
                collision.write_text('precious local evidence', encoding='utf-8')
                self.cli('switch-branch', '--repo', self.repo, '--branch', self.expected, ok=False)
                self.assertEqual(flow.branch(self.repo), 'main')
                self.assertEqual(collision.read_text(), 'precious local evidence')

    def test_commit_audit_manual_unaffected(self):
        self.bind()
        self.assertEqual(flow.git(self.repo, 'for-each-ref', '--format=%(upstream)', 'refs/heads/' + self.expected), '')
        self.pending()
        self.cli('commit', '--repo', self.repo, '--message-file', self.message('glw-92995 fix 修复 API\n\n中文说明'))
        flow.git(self.repo, 'commit', '--allow-empty', '-m', 'temporary manual commit')
        result = self.cli('audit', '--repo', self.repo, '--base', self.base)
        self.assertEqual((result['agent_pass'], result['agent_fail'], result['unclassified']), (1, 0, 1))
        self.assertEqual(result['findings'][0]['level'], 'WARN')

    def test_same_identity_multiple_repos(self):
        self.bind()
        other = self.new_repo('tests')
        self.bind(other)
        self.assertEqual(flow.context(self.repo)['requirement_id'], flow.context(other)['requirement_id'])

    def test_worktree_isolation(self):
        self.bind()
        other = self.root / 'worktree'
        flow.git(self.repo, 'worktree', 'add', '-b', 'temporary', str(other), 'main')
        try:
            self.cli('bind', '--repo', other, '--adhoc', '--existing')
            self.assertNotEqual(flow.git_dir(other), flow.git_dir(self.repo))
            self.assertIsNone(flow.context(other)['requirement_id'])
            self.assertEqual(flow.context(self.repo)['requirement_id'], 'glw-92995')
        finally:
            flow.git(self.repo, 'worktree', 'remove', str(other))

    def test_adhoc_and_rebinding(self):
        self.cli('bind', '--repo', self.repo, '--adhoc', '--existing')
        self.pending()
        self.cli('commit', '--repo', self.repo, '--message-file', self.message('chore 更新配置'))
        self.cli('bind', '--repo', self.repo, '--change', self.change, ok=False)
        self.cli('bind', '--repo', self.repo, '--change', self.change, '--replace')
        self.cli('bind', '--repo', self.repo, '--change', self.change, '--issue', 'glw-2', ok=False)

    def test_bugfix_naming(self):
        self.cli('bind', '--repo', self.repo, '--adhoc', '--branch', 'bugfix/fix-display-20260916')
        self.cli('create-branch', '--repo', self.repo, '--base', 'main')
        self.assertEqual(flow.branch(self.repo), 'bugfix/fix-display-20260916')
        self.cli('bind', '--repo', self.repo, '--adhoc', '--branch', 'bugfix/bad-20260230', '--replace', ok=False)

    def test_legacy_exception_is_scoped(self):
        directory = self.root / '.flow/changes/old-name'
        directory.mkdir()
        flow.git(self.repo, 'switch', '-c', 'GLW-92995')
        self.cli('adopt', '--change-dir', directory, '--repo', self.repo, '--issue', 'glw-92995', '--title', '旧需求')
        self.cli('bind', '--repo', self.repo, '--change', directory / 'change.json')
        self.cli('check-branch', '--repo', self.repo)
        self.assertTrue(flow.context(self.repo)['legacy'])
        self.cli('bind', '--repo', self.repo, '--change', self.change, '--replace')
        self.cli('check-branch', '--repo', self.repo, ok=False)

    def test_metadata_drift_rejected(self):
        self.bind()
        data = flow.read(self.change)
        data['requirement_id'] = 'glw-2'
        flow.write(self.change, data)
        self.cli('check-branch', '--repo', self.repo, ok=False)

    def test_hook_supported_calls(self):
        self.bind()
        for command in ('git commit -m "wrong"', 'git.exe switch wrong', 'git -C . commit -F message.txt',
                        'git branch wrong', 'git worktree add somewhere', 'git -c x=y commit -m wrong',
                        'python flow-git.py check-branch; git commit -m wrong'):
            with self.subTest(command=command):
                result = flow.hook({'cwd': str(self.repo), 'tool_input': {'command': command}})
                self.assertEqual(result['hookSpecificOutput']['permissionDecision'], 'deny')
        for command in ('git status --short', 'git branch --show-current', 'git add a.txt',
                        'python flow-git.py commit --repo . --message-file message.txt', 'git push -u origin HEAD'):
            self.assertEqual(flow.hook({'cwd': str(self.repo), 'tool_input': {'cmd': command}}), {})

    def test_hook_scopes_and_cwd(self):
        self.assertEqual(flow.hook({'cwd': str(self.repo), 'tool_input': {'cmd': 'git commit -m temporary'}}), {})
        self.bind()
        for inputs in ({'cmd': 'git commit -m wrong', 'workdir': str(self.repo)},
                       {'cmd': 'git -C "' + str(self.repo) + '" commit -m wrong'},
                       {'command': 'Set-Location -LiteralPath "' + str(self.repo) + '"; git commit -m wrong'}):
            result = flow.hook({'cwd': str(self.root), 'tool_input': inputs})
            self.assertEqual(result['hookSpecificOutput']['permissionDecision'], 'deny')

    def test_optin_root_without_git(self):
        (self.root / '.flow/config.yaml').write_text('conventions:\n  agent_git: "flow-v1"\n', encoding='utf-8')
        self.assertTrue(flow.managed(self.repo))
        result = flow.hook({'cwd': str(self.repo), 'tool_input': {'command': 'git commit -m bad'}})
        self.assertEqual(result['hookSpecificOutput']['permissionDecision'], 'deny')

    def test_explicit_unmanaged_target_from_managed_cwd(self):
        self.bind()
        other = self.new_repo('unmanaged')
        result = flow.hook({'cwd': str(self.repo), 'tool_input': {'cmd': 'git -C "' + str(other) + '" commit -m temporary'}})
        self.assertEqual(result, {})

    def test_install_idempotent_preserves_and_remove(self):
        home = self.root / 'codex-home'
        home.mkdir()
        config = home / 'config.toml'
        config.write_text('[hooks]\n# existing GPT-6 guard\n', encoding='utf-8')
        original = {'description': 'preserve', 'hooks': {'UserPromptSubmit': [{'hooks': [{'type': 'mcp_tool', 'server': 'gpt6_guard'}]}]}}
        flow.write(home / 'hooks.json', original)
        installer.update(home, SCRIPT, sys.executable)
        first = (home / 'hooks.json').read_bytes()
        self.assertFalse(installer.update(home, SCRIPT, sys.executable)['changed'])
        self.assertEqual(first, (home / 'hooks.json').read_bytes())
        self.assertEqual(config.read_text(), '[hooks]\n# existing GPT-6 guard\n')
        installer.update(home, remove=True)
        self.assertEqual(flow.read(home / 'hooks.json'), original)

    @unittest.skipUnless(sys.platform == 'win32', 'Windows command hook')
    def test_installed_windows_command_real_execution(self):
        self.bind()
        home = self.root / 'codex-home'
        installer.update(home, SCRIPT, sys.executable)
        command = flow.read(home / 'hooks.json')['hooks']['PreToolUse'][0]['hooks'][0]['commandWindows']
        result = subprocess.run(command, input=json.dumps({'cwd': str(self.repo), 'tool_input': {'command': 'git commit -m bad'}}),
                                capture_output=True, encoding='utf-8')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['hookSpecificOutput']['permissionDecision'], 'deny')


if __name__ == '__main__':
    unittest.main()
