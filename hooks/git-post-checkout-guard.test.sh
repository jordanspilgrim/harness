#!/usr/bin/env bash
# All Git mutations below are confined to disposable fixtures.
set -euo pipefail
HOOK="$(cd "$(dirname "$0")" && pwd)/git-post-checkout-guard.sh"
python3 - "$HOOK" <<'PY'
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

hook = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix='harness-post-checkout-') as tmp:
    root = Path(tmp)
    primary, secondary = root / 'primary', root / 'secondary'
    env = {k: v for k, v in os.environ.items()
           if not k.startswith('GIT_') and k not in ('CLAUDECODE', 'HARNESS_POSTCHECKOUT_RECOVERING')}
    env.update(HOME=str(root / 'home'), GIT_CONFIG_NOSYSTEM='1',
               GIT_CONFIG_GLOBAL=os.devnull)
    Path(env['HOME']).mkdir()
    def run(args, cwd=primary, claude=None):
        e = env.copy()
        if claude is not None:
            e['CLAUDECODE'] = claude
        return subprocess.run(args, cwd=cwd, env=e, text=True, capture_output=True, timeout=15)
    def git(*args, cwd=primary, claude=None, ok=True):
        result = run(['git', *map(str, args)], cwd, claude)
        if ok:
            assert result.returncode == 0, (args, result.stderr)
        return result
    def head(cwd=primary):
        r = git('symbolic-ref', '--short', '-q', 'HEAD', cwd=cwd, ok=False)
        return r.stdout.strip() if r.returncode == 0 else 'DETACHED'
    passed = 0
    def check(label, condition):
        global passed
        assert condition, label
        passed += 1
        print('PASS', label)
    git('init', '-q', '-b', 'main', primary, cwd=root)
    git('config', 'user.name', 'Guard test')
    git('config', 'user.email', 'guard@example.invalid')
    (primary / 'tracked').write_text('main\n')
    git('add', 'tracked')
    git('commit', '-qm', 'main')
    git('switch', '-qc', 'other')
    (primary / 'tracked').write_text('other\n')
    git('commit', '-qam', 'other')
    git('branch', 'carry')
    git('switch', '-q', 'main')
    git('worktree', 'add', '-qb', 'review', secondary)
    hooks = primary / '.git' / 'hooks'
    post = hooks / 'post-checkout'
    post.write_text('#!/bin/sh\nexec bash ' + shlex.quote(hook) + ' "$@"\n')
    post.chmod(0o755)
    log = Path(env['HOME']) / '.claude' / 'harness-alerts.log'
    def alerted(result):
        return ('HARNESS ALERT' in result.stderr and log.exists()
                and str(primary) in log.read_text() and 'HEAD=' in log.read_text())
    r = run(['bash', hook, 'old', 'new', '1'], cwd=root, claude='1')
    check('non-repository invocation is silent', r.returncode == 0 and not r.stderr and not log.exists())
    git('switch', 'other')
    check('human branch checkout unchanged; no log', head() == 'other' and not log.exists())
    git('switch', 'main')
    git('switch', '--detach', 'HEAD')
    check('human detached checkout unchanged', head() == 'DETACHED' and not log.exists())
    git('switch', 'main')
    git('switch', 'other', claude='0')
    check('CLAUDECODE must equal 1', head() == 'other' and not log.exists())
    git('switch', 'main')
    r = git('switch', 'other', claude='1')
    check('Claude primary branch restored and alerted', head() == 'main' and alerted(r))
    r = git('switch', '--detach', 'HEAD', claude='1')
    check('Claude primary detach restored and original HEAD logged',
          head() == 'main' and alerted(r) and 'DETACHED@' in log.read_text())
    before = log.read_text()
    git('switch', '-c', 'secondary-new', cwd=secondary, claude='1')
    git('switch', '--detach', 'HEAD', cwd=secondary, claude='1')
    check('secondary switch and detach untouched',
          head(secondary) == 'DETACHED' and log.read_text() == before)
    r = run(['bash', hook, 'old', 'new', '0'], claude='1')
    check('file checkout flag ignored', r.returncode == 0 and log.read_text() == before)
    git('switch', 'main', claude='1')
    check('already primary is silent (also terminates recursive hook)', log.read_text() == before)
    git('tag', 'main')
    r = git('switch', 'main', claude='1')
    check('same-name tag cannot cause recursive recovery', log.read_text() == before)
    git('tag', '-d', 'main')
    # Dirty changes that can travel must survive restoration.
    (primary / 'untracked').write_text('keep me\n')
    r = git('switch', 'other', claude='1')
    check('nonconflicting dirty tree preserved', head() == 'main'
          and (primary / 'untracked').read_text() == 'keep me\n' and alerted(r))
    # Carry -> other has identical trees, so the initiating checkout can carry
    # this edit; restoration to main conflicts and must leave it untouched.
    git('switch', 'carry')
    (primary / 'tracked').write_text('uncommitted work\n')
    r = git('switch', 'other', claude='1', ok=False)
    check('conflicting dirty tree alerts without force',
          r.returncode != 0 and head() == 'other' and alerted(r)
          and 'RECOVERY FAILED' in r.stderr
          and (primary / 'tracked').read_text() == 'uncommitted work\n')
    (primary / 'tracked').write_text('other\n')
    git('config', 'harness.primaryBranch', 'other')
    r = git('switch', 'main', claude='1')
    check('configured primary override', head() == 'other' and alerted(r))
    git('config', '--unset', 'harness.primaryBranch')
    git('update-ref', 'refs/remotes/origin/main', 'main')
    git('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main')
    r = run(['bash', hook, 'old', 'new', '1'], claude='1')
    check('remote default branch resolved', r.returncode == 0 and head() == 'main' and alerted(r))
    git('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/other')
    git('update-ref', 'refs/remotes/origin/other', 'other')
    r = run(['bash', hook, 'old', 'new', '1'], claude='1')
    check('remote default takes precedence over main', r.returncode == 0 and head() == 'other')
    git('symbolic-ref', '--delete', 'refs/remotes/origin/HEAD')
    git('config', 'init.defaultBranch', 'other')
    r = git('switch', 'main', claude='1')
    check('local default branch resolved', head() == 'other' and alerted(r))
    git('config', 'harness.primaryBranch', 'missing')
    r = git('switch', 'main', claude='1', ok=False)
    check('missing primary alerts without guessing',
          r.returncode != 0 and head() == 'main' and 'Cannot resolve' in r.stderr and alerted(r))
    # Ignored files (and ignored directories) must survive either initiating
    # branch-switch spelling when restoration would replace them with a file.
    git('config', 'harness.primaryBranch', 'main')
    git('switch', 'main')
    (primary / '.gitignore').write_text('payload\n')
    (primary / 'payload').write_text('committed payload\n')
    git('add', '.gitignore')
    git('add', '-f', 'payload')
    git('commit', '-qm', 'main payload')
    git('switch', '-qc', 'no-payload')
    git('rm', '-q', 'payload')
    git('commit', '-qm', 'remove payload')
    git('branch', 'no-payload-copy')
    for spelling in ('switch', 'checkout'):
        for directory in (False, True):
            payload = primary / 'payload'
            if directory:
                payload.mkdir()
                local = payload / 'local'
            else:
                local = payload
            local.write_text('irreplaceable\n')
            r = git(spelling, 'no-payload-copy', claude='1', ok=False)
            check(f'{spelling}: ignored {"directory" if directory else "file"} preserved',
                  r.returncode != 0 and head() == 'no-payload-copy'
                  and local.read_text() == 'irreplaceable\n'
                  and 'RECOVERY FAILED' in r.stderr)
            local.unlink()
            if directory:
                payload.rmdir()
            git('switch', 'no-payload')
    git('switch', 'other')
    # Exercise the explicitly best-effort layer-1 directory forms end-to-end.
    git('config', 'harness.primaryBranch', 'main')
    for label, args in [
        ('repeated -C', ['-C', str(primary), '-C', '.', 'switch', 'other']),
        ('relative git-dir', ['-C', str(primary), '--git-dir=.git', 'switch', 'other']),
    ]:
        r = git(*args, cwd=secondary, claude='1')
        check(label + ' outcome restored', head() == 'main' and 'HARNESS ALERT' in r.stderr)
    # Both CLI work-tree spellings and the inherited environment can select
    # secondary files while retaining the primary administrative directory.
    for label, args, inherited in [
        ('equals work-tree', [f'--git-dir={primary}/.git', f'--work-tree={secondary}'], {}),
        ('split work-tree', ['--git-dir', str(primary / '.git'), '--work-tree', str(secondary)], {}),
        ('inherited work-tree', [], {'GIT_DIR': str(primary / '.git'), 'GIT_WORK_TREE': str(secondary)}),
    ]:
        git('switch', 'carry')
        before_files = {p.name: p.read_bytes() for p in secondary.iterdir() if p.is_file()}
        e = dict(env, CLAUDECODE='1', **inherited)
        r = subprocess.run(['git', *args, 'switch', 'other'], cwd=secondary,
                           env=e, text=True, capture_output=True, timeout=15)
        check(label + ': secondary files and both HEADs untouched by recovery',
              r.returncode != 0 and head() == 'other' and head(secondary) == 'DETACHED'
              and before_files == {p.name: p.read_bytes() for p in secondary.iterdir() if p.is_file()}
              and 'RECOVERY REFUSED' in r.stderr)
    # Equivalent primary paths are safe, including symlinks and spaces.
    alias = root / 'primary alias'
    alias.symlink_to(primary, target_is_directory=True)
    e = dict(env, CLAUDECODE='1', GIT_DIR=str(primary / '.git'), GIT_WORK_TREE=str(alias))
    # Clearing GIT_WORK_TREE must not expose a conflicting core.worktree config.
    e.update(GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.worktree', GIT_CONFIG_VALUE_0=str(secondary))
    before_files = {p.name: p.read_bytes() for p in secondary.iterdir() if p.is_file()}
    r = subprocess.run(['bash', hook, 'old', 'new', '1'], cwd=secondary,
                       env=e, text=True, capture_output=True, timeout=15)
    check('primary alias recovers using explicitly bound primary tree',
          r.returncode == 0 and head() == 'main' and alerted(r)
          and before_files == {p.name: p.read_bytes() for p in secondary.iterdir() if p.is_file()})
    # A branch-dependent target used to bounce between main and other forever.
    git('config', '--unset', 'harness.primaryBranch')
    for branch, target in [('main', 'other'), ('other', 'main')]:
        config = root / ('on-' + branch)
        config.write_text('[harness]\nprimaryBranch = ' + target + '\n')
        git('config', f'includeIf.onbranch:{branch}.path', config)
    count = root / 'entries'
    post.write_text('#!/bin/sh\necho entry >> ' + shlex.quote(str(count)) + '\nexec bash '
                    + shlex.quote(hook) + ' "$@"\n')
    r = git('switch', 'other', claude='1')
    check('branch-dependent configuration recovers once without recursion',
          head() == 'main' and len(count.read_text().splitlines()) == 2 and alerted(r))
    before = log.read_text()
    e = dict(env, CLAUDECODE='1', HARNESS_POSTCHECKOUT_RECOVERING='1')
    r = subprocess.run(['bash', hook, 'old', 'new', '1'], cwd=primary,
                       env=e, text=True, capture_output=True, timeout=15)
    check('inherited sentinel exits silently before resolving changing config',
          r.returncode == 0 and not r.stderr and head() == 'main' and log.read_text() == before)
    git('config', 'harness.primaryBranch', 'main')
    log.unlink()
    log.parent.rmdir()
    log.parent.write_text('blocks log directory creation')
    r = git('switch', 'other', claude='1')
    check('log failure still restores and alerts on stderr', head() == 'main'
          and 'could not write' in r.stderr and 'HARNESS ALERT' in r.stderr)
    print(f'git-post-checkout-guard: pass={passed} fail=0')
PY
