#!/bin/bash
# Enhanced Git status for tmux

CURRENT_DIR="$1"
cd "$CURRENT_DIR" 2>/dev/null || exit 1

# Check if we're in a git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo ""
    exit 0
fi

# Get branch name
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -z "$BRANCH" ]; then
    echo ""
    exit 0
fi

# Get status indicators
STATUS=""

# Check for uncommitted changes
CHANGES=$(git status --porcelain 2>/dev/null)
if [ -n "$CHANGES" ]; then
    MODIFIED=$(echo "$CHANGES" | grep -c "^.M")
    ADDED=$(echo "$CHANGES" | grep -c "^A")
    DELETED=$(echo "$CHANGES" | grep -c "^.D")
    UNTRACKED=$(echo "$CHANGES" | grep -c "^??")
    
    [ $MODIFIED -gt 0 ] && STATUS="${STATUS}📝$MODIFIED "
    [ $ADDED -gt 0 ] && STATUS="${STATUS}➕$ADDED "
    [ $DELETED -gt 0 ] && STATUS="${STATUS}❌$DELETED "
    [ $UNTRACKED -gt 0 ] && STATUS="${STATUS}❓$UNTRACKED "
else
    STATUS="✅ "
fi

# Check ahead/behind
AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null)
BEHIND=$(git rev-list --count HEAD..@{u} 2>/dev/null)

[ "$AHEAD" -gt 0 ] 2>/dev/null && STATUS="${STATUS}⬆️$AHEAD "
[ "$BEHIND" -gt 0 ] 2>/dev/null && STATUS="${STATUS}⬇️$BEHIND "

# Get last commit info
LAST_COMMIT=$(git log -1 --pretty=format:"%cr" 2>/dev/null)

# Output format
echo "🌿 $BRANCH | $STATUS| 🕐 $LAST_COMMIT"
