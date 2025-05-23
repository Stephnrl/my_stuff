# Tmux Cheat Sheet

## Custom Key Bindings (Prefix: Ctrl-a)

### Session Management
- `Ctrl-a d` - Detach from session
- `Ctrl-a r` - Reload config

### Window Management
- `Ctrl-a c` - Create new window
- `Ctrl-a |` - Split horizontally
- `Ctrl-a -` - Split vertically
- `Alt-1/2/3/4/5` - Quick window switch

### Pane Navigation
- `Ctrl-a h/j/k/l` - Navigate panes (vim-style)
- `Ctrl-a H/J/K/L` - Resize panes

### Development Shortcuts
- `Ctrl-a P` - Activate Python venv
- `Ctrl-a A` - Check Ansible version
- `Ctrl-a G` - Go to GHES project
- `Ctrl-a S` - Git status
- `Ctrl-a R` - Run Ansible playbook (dry-run)

### Copy Mode
- `Ctrl-a [` - Enter copy mode
- `v` - Start selection
- `y` - Copy selection (to Windows clipboard in WSL)

## Command Line
- `ta <session>` - Attach to session
- `tls` - List sessions
