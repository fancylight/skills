#!/usr/bin/env python3
"""Codex Flow Git conventions. Standard library only; never installs Git hooks."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
import sys

TYPES = 'feat fix docs test refactor perf style build ci chore revert'.split()
HAN = re.compile(r'[\u3400-\u9fff\U00020000-\U0003134f]')
SLUG = re.compile(r'[a-z][a-z0-9]*(?:-[a-z0-9]+)*')
CONTEXT = 'flow-git-context.json'
RECEIPTS = 'flow-git-commits.jsonl'


def require(ok, message):
    if not ok:
        raise ValueError(message)


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def write(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    os.replace(temp, path)


def git(repo, *args):
    result = subprocess.run(['git', '-C', str(repo), *args], capture_output=True,
                            encoding='utf-8', errors='replace')
    require(result.returncode == 0, result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip()


def git_dir(repo):
    return Path(git(repo, 'rev-parse', '--absolute-git-dir'))


def branch(repo):
    value = git(repo, 'branch', '--show-current')
    require(value, 'Detached HEAD：请明确目标分支，不自动 checkout。')
    return value


def issue(value):
    value = value.lower()
    require(re.fullmatch(r'glw-[0-9]+', value), '需求编号必须为 glw-数字；不能编造编号。')
    return value


def date(value):
    require(re.fullmatch(r'[0-9]{8}', value), '日期必须为 YYYYMMDD。')
    dt.datetime.strptime(value, '%Y%m%d')
    return value


def metadata(path):
    path = Path(path).resolve()
    data = read(path)
    require(data.get('version') == 1, '不支持的 change.json 版本。')
    require(data.get('requirement_id') == issue(data.get('requirement_id', '')), '编号必须小写。')
    require(HAN.search(data.get('title', '')), '需求标题必须含中文。')
    require(path.name == 'change.json' and path.parent.name == data['change_name'], '需求目录与元数据不一致。')
    if not data.get('legacy'):
        require(SLUG.fullmatch(data['slug']), '英文短名必须为 kebab-case。')
        expected = data['slug'] + '-' + date(data['delivery_date'])
        require(data['change_name'] == expected and data['branch'] == 'feature/' + expected,
                '需求名/分支与初始短名、交期不一致。')
    else:
        require(data.get('evidence_repo') and data.get('branch'), '存量例外缺少分支证据。')
    return data


def context(repo):
    data = read(git_dir(repo) / CONTEXT)
    if data['kind'] == 'flow':
        current = metadata(data['change_file'])
        expected = data.get('legacy_root_branch', data['branch'])
        if 'legacy_root_branch' in data:
            require(current.get('legacy') and data.get('legacy_git_dir') == str(git_dir(repo)),
                    '存量服务分支例外仅对已核实的 Git 工作目录有效。')
        require(current['requirement_id'] == data['requirement_id'] and current['branch'] == expected,
                '需求绑定已变化；先核对并重新绑定，禁止沿用旧编号。')
        data['legacy'] = bool(current.get('legacy'))
    return data


def check_branch(repo, ctx=None):
    ctx = ctx or context(repo)
    require(branch(repo) == ctx['branch'], '当前分支与绑定需求不符：预期 ' + ctx['branch'])
    return ctx


def validate_message(message, ctx):
    lines = message.strip('\r\n').splitlines()
    require(lines, '提交信息不能为空。')
    prefix = (ctx.get('requirement_id') + ' ') if ctx.get('requirement_id') else ''
    match = re.fullmatch(re.escape(prefix) + r'(' + '|'.join(TYPES) + r') ([^\s].*)', lines[0])
    require(match, '格式应为 ' + prefix + '<type> <中文描述>；类型后不加冒号或竖线。')
    description = match.group(2)
    require(description == description.strip() and not description.startswith((':', '：', '|')),
            '描述前后不能带多余分隔符或空白。')
    require(HAN.search(description), '提交描述必须使用中文，可混合必要技术标识。')
    body = '\n'.join(lines[1:]).strip()
    require(not body or HAN.search(body), '提交正文必须用中文说明，可包含技术标识及代码。')


def save_context(repo, data, replace=False):
    target = git_dir(repo) / CONTEXT
    if target.exists():
        old = read(target)
        require(old == data or replace, '该工作目录已绑定其他上下文；核对当前任务后显式 --replace。')
    write(target, data)


def initialize(args):
    require(SLUG.fullmatch(args.slug), '英文短名必须为 kebab-case。')
    name = args.slug + '-' + date(args.delivery_date)
    target = Path(args.root).resolve() / '.flow' / 'changes' / name / 'change.json'
    data = dict(version=1, requirement_id=issue(args.issue), title=args.title,
                slug=args.slug, delivery_date=args.delivery_date, change_name=name,
                branch='feature/' + name, legacy=False)
    require(HAN.search(args.title), '需求标题必须含中文。')
    if target.exists():
        require(read(target) == data, '已存在的需求身份不可覆盖；延期不修改初始交期。')
    else:
        require(not target.parent.exists(), '已有目录请使用 adopt，不自动当作新需求。')
        write(target, data)
    return dict(change_file=str(target), **data)


def adopt(args):
    directory = Path(args.change_dir).resolve()
    require(directory.is_dir() and directory.parent.name == 'changes' and
            directory.parent.parent.name == '.flow', '仅接入已存在的 .flow/changes/<需求>。')
    target = directory / 'change.json'
    require(not target.exists(), '已有 change.json，直接 bind；不覆盖身份。')
    data = dict(version=1, requirement_id=issue(args.issue), title=args.title,
                slug=None, delivery_date=None, change_name=directory.name,
                branch=branch(args.repo), legacy=True,
                evidence_repo=str(Path(args.repo).resolve()))
    require(HAN.search(args.title), '需求标题必须含中文。')
    write(target, data)
    return data


def bind(args):
    if args.change:
        require(not args.issue and not args.branch, '--change 不接受 adhoc 的编号/分支覆盖。')
        data = metadata(args.change)
        git(args.repo, 'check-ref-format', '--branch', data['branch'])
        binding = dict(kind='flow', change_file=str(Path(args.change).resolve()),
                       requirement_id=data['requirement_id'], branch=data['branch'])
        if args.existing:
            require(data.get('legacy'), '仅存量需求允许核实已有服务分支例外。')
            binding.update(branch=branch(args.repo), legacy_root_branch=data['branch'],
                           legacy_git_dir=str(git_dir(args.repo)))
    else:
        require(args.adhoc, '必须指定 --change 或明确 --adhoc。')
        expected = args.branch or branch(args.repo)
        git(args.repo, 'check-ref-format', '--branch', expected)
        if not args.existing:
            match = re.fullmatch(r'bugfix/([a-z][a-z0-9]*(?:-[a-z0-9]+)*)-([0-9]{8})', expected)
            require(match, '新建非 Flow 修复分支应为 bugfix/<英文短名>-YYYYMMDD。')
            date(match.group(2))
        else:
            require(expected == branch(args.repo), '--existing 只接受已核实的当前分支。')
        binding = dict(kind='adhoc', requirement_id=issue(args.issue) if args.issue else None,
                       branch=expected, legacy=bool(args.existing))
    save_context(args.repo, binding, args.replace)
    return binding


def create_branch(args):
    ctx = context(args.repo)
    # A new root Git repository already contains the just-created identity file.
    # Permit only that exact untracked file, never other design artifacts or user edits.
    status = git(args.repo, 'status', '--porcelain=v1', '-z', '--untracked-files=all')
    entries = status.split('\0') if status else []
    top = Path(git(args.repo, 'rev-parse', '--show-toplevel'))
    identity = Path(ctx['change_file']).resolve() if ctx['kind'] == 'flow' else None
    require(all(not entry or (entry.startswith('?? ') and identity is not None and
                              (top / entry[3:]).resolve() == identity) for entry in entries),
            '工作目录有未确认改动；仅允许本次 init 产生的未跟踪 change.json，不自动切换。')
    git(args.repo, 'rev-parse', '--verify', 'refs/heads/' + args.base)
    git(args.repo, 'switch', '--no-track', '-c', ctx['branch'], args.base)
    return {'branch': branch(args.repo)}


def switch_branch(args):
    ctx = context(args.repo)
    require(args.branch == ctx['branch'], '目标分支与绑定需求不符：预期 ' + ctx['branch'])
    git(args.repo, 'check-ref-format', '--branch', args.branch)
    git(args.repo, 'show-ref', '--verify', 'refs/heads/' + args.branch)
    directory = git_dir(args.repo)
    require(not any((directory / marker).exists() for marker in (
        'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply', 'sequencer')),
        '存在进行中的合并、变基或拣选；先处理当前操作，不自动切换。')
    require(not git(args.repo, 'status', '--porcelain=v1', '--untracked-files=no'),
            '已跟踪文件有未提交改动；先确认并处理，不自动 stash 或丢弃。')
    # Git checks real path collisions; unrelated untracked evidence must survive.
    # Also protect ignored files, which Git otherwise permits overwriting.
    git(args.repo, 'switch', '--no-guess', '--no-overwrite-ignore', args.branch)
    check_branch(args.repo)
    return {'branch': branch(args.repo)}


def commit(args):
    ctx = check_branch(args.repo)
    message = Path(args.message_file).read_text(encoding='utf-8-sig')
    validate_message(message, ctx)
    require(git(args.repo, 'diff', '--cached', '--name-only'), '暂存区为空；先明确暂存本任务文件。')
    require(not (git_dir(args.repo) / 'MERGE_HEAD').exists(), '合并提交需单独审查，不由普通提交入口代办。')
    output = git(args.repo, 'commit', '--cleanup=verbatim', '-F', str(Path(args.message_file).resolve()))
    oid = git(args.repo, 'rev-parse', 'HEAD')
    with (git_dir(args.repo) / RECEIPTS).open('a', encoding='utf-8') as stream:
        stream.write(json.dumps(dict(oid=oid, requirement_id=ctx.get('requirement_id'),
                                    branch=ctx['branch']), ensure_ascii=False) + '\n')
    # Existing project hooks may change a message: verify the actual result without rewriting history.
    validate_message(git(args.repo, 'show', '-s', '--format=%B', oid), ctx)
    return dict(commit=oid, output=output)


def audit(args):
    ctx = context(args.repo)
    base = git(args.repo, 'rev-parse', '--verify', args.base + '^{commit}')
    target = git(args.repo, 'rev-parse', '--verify', args.target + '^{commit}')
    git(args.repo, 'merge-base', '--is-ancestor', base, target)
    path = git_dir(args.repo) / RECEIPTS
    receipts = [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()] if path.exists() else []
    known = {r['oid'] for r in receipts if r.get('requirement_id') == ctx.get('requirement_id') and r['branch'] == ctx['branch']}
    result = dict(agent_pass=0, agent_fail=0, unclassified=0, legacy_exceptions=int(bool(ctx.get('legacy'))), findings=[])
    for oid in git(args.repo, 'rev-list', base + '..' + target).splitlines():
        error = None
        try:
            validate_message(git(args.repo, 'show', '-s', '--format=%B', oid), ctx)
        except ValueError as exc:
            error = str(exc)
        if oid in known:
            result['agent_fail' if error else 'agent_pass'] += 1
        else:
            result['unclassified'] += 1
        if error:
            result['findings'].append(dict(commit=oid, level='FAIL' if oid in known else 'WARN', reason=error))
    return result


def managed(cwd):
    cwd = Path(cwd).resolve()
    for parent in (cwd, *cwd.parents):
        config = parent / '.flow' / 'config.yaml'
        if config.is_file() and re.search(r'(?m)^\s*agent_git:\s*[\"\x27]?flow-v1[\"\x27]?\s*(?:#.*)?$', config.read_text(encoding='utf-8-sig')):
            return True
    try:
        return (git_dir(cwd) / CONTEXT).exists()
    except (ValueError, OSError):
        return False


def hook(payload):
    """Recognize literal shell Git calls; not a general shell interpreter/security boundary."""
    inputs = payload.get('tool_input', {})
    if isinstance(inputs, str):
        inputs = json.loads(inputs)
    command = inputs.get('cmd', inputs.get('command', ''))
    cwd = Path(inputs.get('workdir') or inputs.get('cwd') or payload.get('cwd') or os.getcwd())
    tokens = re.findall(r"'(?:[^']|'')*'|\"(?:[^\"`]|`.)*\"|[;&|()\n]|[^\s;&|()\n]+", command)
    tokens = [t[1:-1] if len(t) > 1 and t[0] == t[-1] and t[0] in "'\"" else t for t in tokens]
    cwd_managed = managed(cwd)
    for i, token in enumerate(tokens):
        if token.lower() in ('cd', 'set-location', 'push-location') and i + 1 < len(tokens):
            location = tokens[i + 1]
            if location.lower() in ('-path', '-literalpath') and i + 2 < len(tokens):
                location = tokens[i + 2]
            if not any(c in location for c in '$`%'):
                cwd = (cwd / location).resolve()
                cwd_managed = managed(cwd)
        if token.lower().replace('\\', '/').rsplit('/', 1)[-1] not in ('git', 'git.exe'):
            continue
        repo, j, uncertain = cwd, i + 1, False
        while j < len(tokens) and tokens[j].startswith('-'):
            option = tokens[j]
            if option == '-C' and j + 1 < len(tokens):
                value = tokens[j + 1]
                uncertain |= any(c in value for c in '$`%')
                repo = (repo / value).resolve()
                j += 2
            elif option in ('-c', '--git-dir', '--work-tree') and j + 1 < len(tokens):
                uncertain = True
                j += 2
            else:
                uncertain = True
                j += 1
        if not (managed(repo) or (uncertain and cwd_managed)) or j >= len(tokens):
            continue
        operation = tokens[j].lower()
        tail = tokens[j + 1:]
        for separator in (';', '&', '|', '\n', ')'):
            if separator in tail:
                tail = tail[:tail.index(separator)]
        write_op = operation in ('commit', 'switch', 'checkout', 'merge', 'rebase', 'cherry-pick', 'revert')
        write_op |= operation == 'branch' and bool(tail) and not any(t in tail for t in ('--show-current', '--list', '-l', '-a', '-r', '-v', '-vv', '--contains'))
        write_op |= operation == 'worktree' and bool(tail) and tail[0] in ('add', 'move')
        if write_op or (uncertain and operation not in ('status', 'diff', 'log', 'show', 'rev-parse', 'fetch')):
            return {'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny',
                    'permissionDecisionReason': 'Flow Git：先 bind；新建分支用 flow-git.py create-branch，切换已有分支用 switch-branch --repo REPO --branch BRANCH，提交用 commit。切换后 check-branch。复杂 Git 操作需单独审查，不能用交互 shell 或脚本绕过。手动终端提交不受影响。'}}
        if operation == 'push':
            try:
                check_branch(repo)
            except (ValueError, OSError) as exc:
                return {'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny',
                        'permissionDecisionReason': 'Flow Git push 前检查失败：' + str(exc)}}
    return {}


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='action', required=True)
    init = sub.add_parser('init')
    for name in ('root', 'issue', 'title', 'slug', 'delivery-date'):
        init.add_argument('--' + name, required=True)
    old = sub.add_parser('adopt')
    for name in ('change-dir', 'repo', 'issue', 'title'):
        old.add_argument('--' + name, required=True)
    b = sub.add_parser('bind')
    b.add_argument('--repo', required=True)
    group = b.add_mutually_exclusive_group(required=True)
    group.add_argument('--change')
    group.add_argument('--adhoc', action='store_true')
    for name in ('issue', 'branch'):
        b.add_argument('--' + name)
    for name in ('existing', 'replace'):
        b.add_argument('--' + name, action='store_true')
    for action in ('check-branch', 'check-commit', 'commit', 'create-branch', 'switch-branch', 'audit'):
        cmd = sub.add_parser(action)
        cmd.add_argument('--repo', required=True)
        if action in ('check-commit', 'commit'):
            cmd.add_argument('--message-file', required=True)
        if action == 'create-branch':
            cmd.add_argument('--base', required=True, help='Existing local branch, e.g. main; no inferred base')
        if action == 'switch-branch':
            cmd.add_argument('--branch', required=True, help='Existing local branch matching the bound requirement')
        if action == 'audit':
            cmd.add_argument('--base', required=True)
            cmd.add_argument('--target', default='HEAD')
    sub.add_parser('hook')
    return p


def main():
    args = parser().parse_args()
    try:
        if args.action == 'hook':
            result = hook(json.load(sys.stdin))
        elif args.action == 'check-branch':
            result = check_branch(args.repo)
        elif args.action == 'check-commit':
            ctx = check_branch(args.repo)
            validate_message(Path(args.message_file).read_text(encoding='utf-8-sig'), ctx)
            result = {'status': 'PASS'}
        else:
            result = {'init': initialize, 'adopt': adopt, 'bind': bind, 'commit': commit,
                      'create-branch': create_branch, 'switch-branch': switch_branch, 'audit': audit}[args.action](args)
        print(json.dumps(result, ensure_ascii=False))
        return 1 if args.action == 'audit' and result['agent_fail'] else 0
    except (ValueError, OSError, KeyError, TypeError) as exc:
        print('Flow Git: ' + str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
    sys.stdin.reconfigure(encoding='utf-8-sig')
    sys.exit(main())
