#!/usr/bin/env python3
"""Merge/remove only the Flow Git Codex hook; never edits trust or Git hooks."""
import argparse
import json
import os
from pathlib import Path
import shlex
import sys

MARKER = 'Flow Git conventions (flow-v1)'


def update(home, runtime=None, python=None, remove=False):
    target = Path(home) / 'hooks.json'
    original = target.read_bytes() if target.exists() else None
    data = json.loads(original.decode('utf-8-sig')) if original else {'hooks': {}}
    events = data.setdefault('hooks', {})
    groups = []
    for group in events.get('PreToolUse', []):
        handlers = [h for h in group.get('hooks', []) if h.get('statusMessage') != MARKER]
        if handlers:
            groups.append(dict(group, hooks=handlers))
    if not remove:
        runtime, python = Path(runtime).resolve(), Path(python).resolve()
        if not runtime.is_file() or not python.is_file():
            raise ValueError('Python executable and installed flow-git.py must exist.')
        # Invoke PowerShell explicitly: command parsing then does not depend on the session shell.
        expression = '& ' + ' '.join("'" + str(p).replace("'", "''") + "'" for p in (python, runtime)) + ' hook'
        import base64
        encoded = base64.b64encode(expression.encode('utf-16le')).decode('ascii')
        command = 'powershell.exe -NoProfile -NonInteractive -EncodedCommand ' + encoded
        groups.append({'matcher': '^Bash$', 'hooks': [{
            'type': 'command', 'command': shlex.join([str(python), str(runtime), 'hook']),
            'commandWindows': command, 'timeout': 15, 'statusMessage': MARKER}]})
    if groups:
        events['PreToolUse'] = groups
    else:
        events.pop('PreToolUse', None)
    if original and json.loads(original.decode('utf-8-sig')) == data:
        return {'changed': False, 'file': str(target)}
    target.parent.mkdir(parents=True, exist_ok=True)
    backup = target.with_name('hooks.before-flow-git.json')
    if original is not None and not backup.exists():
        backup.write_bytes(original)
    temp = target.with_suffix('.json.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    os.replace(temp, target)
    return {'changed': True, 'file': str(target), 'trust': 'Removed' if remove else 'Review exact hook in /hooks; trust is not modified'}


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--codex-home', required=True)
    p.add_argument('--runtime-script')
    p.add_argument('--python', default=sys.executable)
    p.add_argument('--remove', action='store_true')
    args = p.parse_args()
    try:
        print(json.dumps(update(args.codex_home, args.runtime_script, args.python, args.remove), ensure_ascii=False))
    except (ValueError, OSError, TypeError) as exc:
        p.exit(2, str(exc) + '\n')
