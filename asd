mkdir -p ~/.copilot/skills
cp -r board-ops ~/.copilot/skills/
chmod +x ~/.copilot/skills/board-ops/scripts/*.sh

# global instructions (small, always-on)
cp copilot-instructions-trimmed.md ~/.copilot/copilot-instructions.md

# one-time board config
bash ~/.copilot/skills/board-ops/scripts/setup.sh
bash ~/.copilot/skills/board-ops/scripts/board-ids.sh
