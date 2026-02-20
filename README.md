# dockyard

tmux-based multi-agent CLI orchestration with SSOT (`state/session.yaml`) and stateless runner dispatch.

## Requirements

- bash
- git
- yq (mikefarah v4)
- flock (util-linux)
- timeout (GNU `timeout` or `gtimeout`)
- tmux (for `dock up`, optional for headless orchestrate)

Optional (tests/CI):

- bats
- shellcheck
- shfmt

## Quick start

1. Copy config and state templates.

```bash
cp config/agents.env.example config/agents.env
cp state/session.yaml.example state/session.yaml
```

2. Clone target repository into `repos/`.

```bash
./dock clone <git-url>
```

3. Bring up tmux panes and worktrees.

```bash
./dock up <repo> --runners 2 --attach stateless
```

4. Run one orchestration cycle.

```bash
./dock orchestrate --once --repo <repo> --runners 2
```

5. Inspect status.

```bash
./dock status --repo <repo>
```

## Commands

- `dock clone <git-url>`
- `dock up <repo> [--runners N] [--attach stateless|resident|none]`
- `dock orchestrate --once|--loop [--repo <repo>] [--runners N] [--interval seconds]`
- `dock status [--repo <repo>]`
- `dock journal [--repo <repo>] [--message "..."]`
- `dock clean --repo <repo> [--dry-run]`
- `dock archive --repo <repo> [--job <job_id>]`
- `dock send <role> "<command>"`

## Mock mode

Use mock LLM outputs for local verification:

```bash
DOCKYARD_MOCK_LLM=1 ./dock orchestrate --once --repo <repo>
```
