# memento-app

The Memento recipe app for a jailbroken Kindle (KUAL extension, pure busybox
sh + fbink). This repo is the OTA source: the device pulls its own code from
here over GitHub raw, the same way it pulls recipes from
[memento-recipes](https://github.com/lulvul/memento-recipes).

## How the device updates itself

1. Every commit, the pre-commit hook regenerates `VERSION` (a datetime stamp)
   and `app-manifest.txt` (`md5  path` per OTA-updatable file).
2. On the Kindle, Settings -> "update software" (or KUAL -> "Memento: Update
   software") runs `bin/update.sh`: it compares `VERSION` to the local
   `app-version`, stages the whole manifest to `/tmp`, verifies md5s, runs
   `sh -n` on every script, backs up the current files to `.backup/`, then
   installs by atomic per-file rename. If anything fails, nothing changes.
3. From inside the app, a successful update re-execs `memento.sh` so the new
   build is live immediately.
4. KUAL -> "Memento: Roll back update" (`bin/rollback.sh`) restores the
   backup. It is deliberately NOT in the manifest, so a bad update can never
   break the recovery path. `menu.json`/`config.xml` are also excluded (KUAL
   plumbing, USB-only).

## Dev loop

Edit -> commit -> push -> on the Kindle, cover -> bottom strip -> settings ->
center tap. No USB.

One-time setup after cloning: `cp tools/pre-commit .git/hooks/pre-commit &&
chmod +x .git/hooks/pre-commit`.

Working docs (STATUS.md, DEPLOY.md, device calibration history) live in the
private vault, not here.
