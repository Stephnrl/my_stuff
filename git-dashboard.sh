#!/bin/bash
# Git repository dashboard

REPO_PATH="$1"
cd "$REPO_PATH" 2>/dev/null || exit 1

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not a Git repository"
    exit 1
fi

clear
echo "🌿 Git Repository Dashboard"
echo "=========================="
echo "📁 Repository: $(basename $REPO_PATH)"
echo "🌿 Branch: $(git rev-parse --abbrev-ref HEAD)"
echo "📝 Status: $(git status --porcelain | wc -l) changes"
echo "📊 Commits: $(git rev-list --count HEAD) total"
echo ""

echo "Recent commits:"
git log --oneline -5

echo ""
echo "Current status:"
git status --short

echo ""
echo "Branch info:"
git branch -v
