#!/bin/bash
# Git-aware GHES Development Session

# Use the Git-aware tmux config
export TMUX_CONFIG=~/.tmux.conf.git

# Create new tmux session
tmux -f $TMUX_CONFIG new-session -d -s ghes-git -c ~/ghes-upgrade

# Window 1: Main development
tmux rename-window -t ghes-git:1 'main'
tmux send-keys -t ghes-git:1 'source ~/myproject/bin/activate' C-m
tmux send-keys -t ghes-git:1 'git status' C-m

# Window 2: Git operations
tmux new-window -t ghes-git -n 'git' -c ~/ghes-upgrade
tmux send-keys -t ghes-git:2 'git log --oneline -10' C-m

# Window 3: Ansible with Git awareness
tmux new-window -t ghes-git -n 'ansible' -c ~/ghes-upgrade
tmux send-keys -t ghes-git:3 'source ~/myproject/bin/activate' C-m
tmux split-window -h -c ~/ghes-upgrade
tmux send-keys -t ghes-git:3.2 'git diff --name-only' C-m

# Window 4: Monitor
tmux new-window -t ghes-git -n 'monitor'
tmux split-window -h
tmux send-keys -t ghes-git:4.1 'watch -n 2 "git status --porcelain"' C-m
tmux send-keys -t ghes-git:4.2 'htop' C-m

# Select main window and split for editor
tmux select-window -t ghes-git:1
tmux split-window -v -c ~/ghes-upgrade
tmux send-keys -t ghes-git:1.2 'source ~/myproject/bin/activate' C-m

# Attach to session
tmux attach-session -t ghes-git
