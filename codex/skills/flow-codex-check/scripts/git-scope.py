"""Read-only Git delivery inventory. No business correctness claims."""
import argparse
import json
import subprocess


def git(repo, *args):
    result = subprocess.run(["git", "-C", repo, *args], capture_output=True)
    if result.returncode:
        raise ValueError(result.stderr.decode("utf-8", "replace").strip())
    return result.stdout.decode("utf-8", "surrogateescape")


def changes(repo, *args):
    parts = git(repo, "diff", "--name-status", "-z", "--no-renames", *args, "--").split("\0")
    return [{"status": parts[i], "path": parts[i + 1]} for i in range(0, len(parts) - 1, 2)]


def inventory(repo, base=None, target="HEAD"):
    root = git(repo, "rev-parse", "--show-toplevel").strip()
    head = git(repo, "rev-parse", "--verify", "HEAD^{commit}").strip()
    target_sha = git(repo, "rev-parse", "--verify", "--end-of-options", target + "^{commit}").strip()
    base_sha = git(repo, "rev-parse", "--verify", "--end-of-options", base + "^{commit}").strip() if base else None
    return {
        "repo": root, "head": head, "base": base_sha, "target": target_sha,
        "committedScope": "KNOWN" if base else "UNVERIFIED",
        "committed": changes(repo, base_sha, target_sha) if base else [],
        "staged": changes(repo, "--cached"), "unstaged": changes(repo),
        "untracked": [p for p in git(repo, "ls-files", "--others", "--exclude-standard", "-z").split("\0") if p],
        "note": "Renames are represented as delete/add; workspace changes are relative to current HEAD, not target."
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--base")
    parser.add_argument("--target", default="HEAD")
    args = parser.parse_args()
    try:
        print(json.dumps(inventory(args.repo, args.base, args.target), ensure_ascii=True, indent=2))
    except ValueError as error:
        parser.exit(2, str(error) + "\n")
