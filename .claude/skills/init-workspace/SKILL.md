---
name: init-workspace
description: >
  Apply this project's local Claude configurations (status line, permissions)
  to the global ~/.claude/settings.json so the setup is replicated in a new environment.
  Trigger when the user asks to: "init workspace", "set up global settings", "apply local
  config globally", "bootstrap this environment", "sync settings to global", or
  "run init-workspace".
---

# init-workspace

Run the script from the project root:

```bash
bash .claude/skills/init-workspace/run.sh
```

Report the script output to the user.
