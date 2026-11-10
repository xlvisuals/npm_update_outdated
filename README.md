# npm_update_outdated.sh

A small Bash script that updates outdated npm packages to their **wanted** version (the highest version allowed by the ranges in `package.json`), but only if that version has been public for a minimum number of days. This avoids pulling in freshly published releases that may be unstable, unsafe, or later yanked.

After updating, the script refreshes the browserslist database, runs `npm audit fix`, and writes dependency and vulnerability reports.

## Features

- Updates only to the **wanted** version, so your declared semver ranges are respected (it never jumps to `latest` across a major version).
- **Minimum release age** check using the publish date from the npm registry.
- `--dry-run` mode to preview package updates.
- Colour-coded summary table showing current, wanted, latest, release date and status.
- Works on both macOS (BSD `date`) and Linux (GNU `date`).
- Writes dependency and audit reports for later review.

## Requirements

- `bash`
- `node` and `npm`
- `jq`
- `curl`
- Network access to `https://registry.npmjs.org`

## Usage

Run from the root of your project (the directory containing `package.json`):

```bash
chmod +x npm_update_outdated.sh
./npm_update_outdated.sh            # update packages
./npm_update_outdated.sh --dry-run  # preview package updates only
```

The script exits with an error if `package.json` is not found in the current directory.

## Configuration

Edit the variables at the top of the script:

| Variable        | Default | Description                                                        |
| --------------- | ------- | ------------------------------------------------------------------ |
| `PACKAGE_JSON`  | `package.json` | File that must exist in the working directory.              |
| `MIN_AGE_DAYS`  | `5`     | A wanted version must be at least this many days old to be installed. |
| `DRY_RUN`       | `false` | Set to `true` by passing `--dry-run`.                              |

> Note: the comment block in the script header mentions a default of 2 days, but the actual value in the code is `5`. Update whichever you intend to keep.

## How it works

1. Runs `npm outdated --json` to list outdated packages. If there are none, the script exits.
2. For each package, fetches its publish history from the npm registry and finds the release date of the **wanted** version.
3. Decides a status for each package:

   | Status        | Meaning                                                          |
   | ------------- | ---------------------------------------------------------------- |
   | `UPDATED`     | Wanted version is old enough and was installed (or would be, in dry run). |
   | `TOO NEW`     | Wanted version is younger than `MIN_AGE_DAYS`; skipped.          |
   | `UP TO DATE`  | Wanted version equals the current version; nothing to do.        |
   | `FAILED`      | Release date could not be found, or `npm install` failed.        |

4. Installs eligible packages with `npm install --save <name>@<wanted>`, which updates `package.json` and the lock file.
5. Prints a summary (`Updated` / `Too new` counts).
6. Runs `npx update-browserslist-db@latest`.
7. Runs `npm audit fix --legacy-peer-deps`.
8. Writes report files (see below).

## Output files

Written to the current directory (existing files are overwritten):

| File                          | Contents                              |
| ----------------------------- | ------------------------------------- |
| `npm-dependencies-local.txt`  | `npm ls --depth=100` for the project  |
| `npm-dependencies-global.txt` | `npm ls -g --depth=100` (global packages) |
| `npm-vulnerabilities.txt`     | `npm audit` output                    |

## Example output

```
-----------------------------------------------------------------
NPM UPDATE SCRIPT
Date:          2026-11-10
Active Node:   /usr/local/bin/node (v22.0.0)
-----------------------------------------------------------------

Checking for outdated packages...
Found 3 outdated package(s).

PACKAGE        CURRENT   WANTED    LATEST    RELEASED     STATUS
example-a      1.2.0     1.4.1     2.0.0     2026-10-01   UPDATED
example-b      3.0.0     3.0.5     3.0.5     2026-11-08   TOO NEW (2 days old)
example-c      0.9.0     0.9.0     1.0.0     2026-09-12   UP TO DATE
---------------------------------------------------------------
Updated: 1  Too new: 1
```

## Known limitations

- **`--dry-run` only covers the package update loop.** The browserslist update, `npm audit fix`, and the report-file writes still run in dry-run mode, so they can modify `package.json`, the lock file and `node_modules`. Guard those steps with `[ "$DRY_RUN" = false ]` if you want a fully side-effect-free preview.
- `latest` versions beyond your declared ranges are shown but never installed; bump those manually.
- Release-age checking relies on the npm registry's `time` field; if it cannot be fetched, that package is reported as `FAILED` and skipped rather than installed.
- `npm install` output is silenced, so failure reasons are not shown.
- `npm audit fix --legacy-peer-deps` can change dependency versions beyond the age check.
- The script has no `set -e`; failures in later steps do not stop the run.
- It is intended for a single `package.json` project, not workspaces or monorepos.

## Recommendation

Commit your work before running, then review the resulting `git diff` and run your tests before committing the updates.
