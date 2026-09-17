#!/usr/bin/env python3
"""Install/remove the Flow TOML block; migrate Flow-only JSON, never grant trust."""
import argparse
import json
import os
from pathlib import Path
import shlex
import sys

MARKER = 'Flow Git conventions (flow-v1)'


BEGIN = '# BEGIN Flow Git conventions (flow-v1)'
END = '# END Flow Git conventions (flow-v1)'


def update(home, runtime=None, python=None, remove=False):
    import tomllib
    home = Path(home)
    target, legacy = home / 'config.toml', home / 'hooks.json'
    original = target.read_bytes() if target.exists() else b''
    text = original.decode('utf-8-sig')
    before = tomllib.loads(text)
    if text.count(BEGIN) != text.count(END) or text.count(BEGIN) > 1:
        raise ValueError('Incomplete or duplicate Flow managed block; no files changed.')
    if BEGIN in text:
        start, end = text.index(BEGIN), text.index(END) + len(END)
        if end < start:
            raise ValueError('Invalid Flow managed block; no files changed.')
        if text[end:end + 2] == '\r\n':
            end += 2
        elif text[end:end + 1] == '\n':
            end += 1
        # Confirm this block owns only the Flow group before removing it.
        block = tomllib.loads(text[start:end])
        groups = block.get('hooks', {}).get('PreToolUse', [])
        if set(block) != {'hooks'} or set(block['hooks']) != {'PreToolUse'} or len(groups) != 1 or any(
                h.get('statusMessage') != MARKER for h in groups[0].get('hooks', [])):
            raise ValueError('Managed block contains unrelated settings; no files changed.')
        text = text[:start] + text[end:]
    clean = tomllib.loads(text)
    for groups in clean.get('hooks', {}).values():
        if isinstance(groups, list) and any(h.get('statusMessage') == MARKER
                for g in groups for h in g.get('hooks', [])):
            raise ValueError('Flow hook outside managed block; review before migration.')
    old_json = legacy.read_bytes() if legacy.exists() else None
    data = json.loads(old_json.decode('utf-8-sig')) if old_json else {'hooks': {}}
    events = data.setdefault('hooks', {})
    groups = []
    for group in events.get('PreToolUse', []):
        handlers = [h for h in group.get('hooks', []) if h.get('statusMessage') != MARKER]
        if handlers:
            groups.append(dict(group, hooks=handlers))
    if groups:
        events['PreToolUse'] = groups
    else:
        events.pop('PreToolUse', None)
    if not remove and any(events.values()):
        raise ValueError('hooks.json contains non-Flow hooks; review their migration first. No files changed.')
    if not remove:
        runtime, python = Path(runtime).resolve(), Path(python).resolve()
        if not runtime.is_file() or not python.is_file():
            raise ValueError('Python executable and installed flow-git.py must exist.')
        expression = '& ' + ' '.join("'" + str(p).replace("'", "''") + "'" for p in (python, runtime)) + ' hook'
        import base64
        command = 'powershell.exe -NoProfile -NonInteractive -EncodedCommand ' + base64.b64encode(expression.encode('utf-16le')).decode('ascii')
        handler = {'type': 'command', 'command': shlex.join([str(python), str(runtime), 'hook']),
                   'commandWindows': command, 'timeout': 15, 'statusMessage': MARKER}
        lines = [BEGIN, '[[hooks.PreToolUse]]', 'matcher = "^Bash$"', '[[hooks.PreToolUse.hooks]]']
        lines += [key + ' = ' + json.dumps(value, ensure_ascii=False) for key, value in handler.items()]
        lines += [END, '']
        text = text + ('' if not text or text.endswith('\n') else '\n') + '\n'.join(lines)
    after = tomllib.loads(text)
    if before.get('hooks', {}).get('state') != after.get('hooks', {}).get('state'):
        raise ValueError('Refusing to change hook trust/state.')
    updated = (b'\xef\xbb\xbf' if original.startswith(b'\xef\xbb\xbf') else b'') + text.encode('utf-8')
    changed = updated != original
    if (target.read_bytes() if target.exists() else b'') != original or (
            legacy.read_bytes() if legacy.exists() else None) != old_json:
        raise ValueError('Hook configuration changed during installation; retry after reviewing it.')
    home.mkdir(parents=True, exist_ok=True)
    for path, raw in ((target, original), (legacy, old_json)):
        backup = path.with_name(path.name + '.before-flow-inline')
        if raw is not None and path.exists() and not backup.exists():
            backup.write_bytes(raw)
    if changed:
        temp = target.with_suffix('.toml.tmp')
        temp.write_bytes(updated)
        os.replace(temp, target)
    if old_json is not None:
        if not any(events.values()):
            # Original JSON (including metadata) is retained in the backup.
            legacy.unlink()
            changed = True
        elif json.loads(old_json.decode('utf-8-sig')) != data:
            temp = legacy.with_suffix('.json.tmp')
            temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
            os.replace(temp, legacy)
            changed = True
    return {'changed': changed, 'file': str(target),
            'trust': 'Removed' if remove else 'Review exact hook in /hooks; trust/state is not modified'}


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
