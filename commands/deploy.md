---
name: deploy
description: Commit, push to GitHub, and deploy to a remote environment
argument-hint: [environment-name]
---

# Deploy

Commit all changes, push to GitHub, and deploy to a remote environment using the `ship` command.

## Instructions

1. Run `ship` from the project root with the provided argument (if any).
2. If no environment is specified and .deploy.json has multiple environments, ask the user which one.
3. If the target is production-like (named `prod`, `production`, `app`, or serving real users), confirm with the user before firing — a deploy is outward-facing, and the environment name in an argument is not the same as a deliberate GO for that environment.
4. Report the results back to the user, including the actual `ship` output — not a summary that assumes success.

## Execution

Run the following command from the project root:

```bash
ship $ARGUMENTS
```

If the `ship` command is not found, tell the user to add `~/bin` to their PATH:
```
export PATH="$HOME/bin:$PATH"
```

If `.deploy.json` is missing, help the user create one by asking for:
- Environment name (e.g., demo, production, alpha)
- SSH host (IP or hostname)
- SSH user (default: ec2-user)
- SSH key path
- Remote app directory path
- Docker services to rebuild (default: web)
