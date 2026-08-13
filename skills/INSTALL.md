# Install

```bash
mkdir -p ~/.copilot/skills
cp -r board-ops ~/.copilot/skills/
chmod +x ~/.copilot/skills/board-ops/scripts/*.sh

# global instructions (small, always-on)
cp copilot-instructions-trimmed.md ~/.copilot/copilot-instructions.md

# one-time board config
bash ~/.copilot/skills/board-ops/scripts/setup.sh
bash ~/.copilot/skills/board-ops/scripts/board-ids.sh
```

In a Copilot CLI session:

```
/skills reload
/skills info board-ops
```

If `/skills info` comes back empty, check the folder sits directly under
`~/.copilot/skills/` with no extra nesting, and that the file is named exactly
`SKILL.md` (case-sensitive).

Then try: `board health`

Requires `jq` and `gh`.
