# ios-builder

macOS build and probe runner for the Vela iOS port (plan: `PORTAGE_IOS.md` on the
`ios/main` branch of `git.alt144.net/antoine/alt144maps`).

- `main` holds only this builder: workflows, scripts, requests. Never the upstream workflows.
- `src/<name>` branches are source snapshots with `.github/` removed:
  `scripts/push-src.sh <vela checkout> <name> [ref]`.
- A job runs when `requests/<job>` changes on `main`. Line 1 names the source branch.
- Each job writes its output to the orphan `results` branch, in `<job>/<run>/` and
  `<job>/latest/`. Read it with `git fetch origin results && git show origin/results:<job>/latest/STATUS`.

| Job | Request file | Output |
| --- | --- | --- |
| `spike` | `requests/spike` (line 2: identities, optional) | `env.txt`, `spike.txt`, `STATUS` |

macOS minutes count ten times on a private repository. Run a macOS job only for what Linux
cannot check.
