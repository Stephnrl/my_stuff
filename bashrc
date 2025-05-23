# Enhanced PS1 with Git Integration for Ubuntu WSL
# Add this to your ~/.bashrc file

# Color definitions for easy customization
readonly RED='\[\033[0;31m\]'
readonly GREEN='\[\033[0;32m\]'
readonly YELLOW='\[\033[0;33m\]'
readonly BLUE='\[\033[0;34m\]'
readonly PURPLE='\[\033[0;35m\]'
readonly CYAN='\[\033[0;36m\]'
readonly WHITE='\[\033[0;37m\]'
readonly LIGHT_GREEN='\[\033[1;32m\]'
readonly LIGHT_BLUE='\[\033[1;34m\]'
readonly LIGHT_CYAN='\[\033[1;36m\]'
readonly LIGHT_GRAY='\[\033[0;37m\]'
readonly DARK_GRAY='\[\033[1;30m\]'
readonly RESET='\[\033[0m\]'

# Unicode symbols (you can replace with ASCII if needed)
readonly BRANCH_SYMBOL="⎇"      # or use "git:" for ASCII
readonly AHEAD_SYMBOL="↑"       # or use "+" for ASCII  
readonly BEHIND_SYMBOL="↓"      # or use "-" for ASCII
readonly MODIFIED_SYMBOL="✗"    # or use "*" for ASCII
readonly STAGED_SYMBOL="✓"      # or use "+" for ASCII
readonly UNTRACKED_SYMBOL="?"   # same in ASCII
readonly STASH_SYMBOL="⚑"       # or use "S" for ASCII

# Function to get current git status with detailed information
git_prompt_info() {
    local git_status branch_name git_info
    local ahead behind modified staged untracked stashed
    local status_color branch_color
    
    # Check if we're in a git repository
    git_status=$(git status --porcelain -b 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        return
    fi
    
    # Get branch name
    branch_name=$(git symbolic-ref --short HEAD 2>/dev/null || git describe --tags --always 2>/dev/null)
    
    # Count different types of changes
    modified=$(echo "$git_status" | grep -c "^[ M]M\|^MM\|^[ M]D")
    staged=$(echo "$git_status" | grep -c "^M[ M]\|^A[ M]\|^D[ M]\|^R[ M]\|^C[ M]")
    untracked=$(echo "$git_status" | grep -c "^??")
    
    # Check for stashed changes
    stashed=$(git stash list 2>/dev/null | wc -l)
    
    # Check if we're ahead/behind remote
    local remote_info=$(git status --porcelain -b 2>/dev/null | head -n1)
    ahead=$(echo "$remote_info" | grep -o "ahead [0-9]*" | grep -o "[0-9]*")
    behind=$(echo "$remote_info" | grep -o "behind [0-9]*" | grep -o "[0-9]*")
    
    # Determine colors based on repo status
    if [[ $modified -gt 0 || $untracked -gt 0 ]]; then
        status_color=$RED
        branch_color=$RED
    elif [[ $staged -gt 0 ]]; then
        status_color=$YELLOW
        branch_color=$YELLOW
    else
        status_color=$GREEN
        branch_color=$GREEN
    fi
    
    # Build git info string
    git_info="${branch_color}${BRANCH_SYMBOL} ${branch_name}${RESET}"
    
    # Add status indicators
    local indicators=""
    [[ $ahead -gt 0 ]] && indicators="${indicators}${GREEN}${AHEAD_SYMBOL}${ahead}${RESET}"
    [[ $behind -gt 0 ]] && indicators="${indicators}${RED}${BEHIND_SYMBOL}${behind}${RESET}"
    [[ $modified -gt 0 ]] && indicators="${indicators}${RED}${MODIFIED_SYMBOL}${modified}${RESET}"
    [[ $staged -gt 0 ]] && indicators="${indicators}${GREEN}${STAGED_SYMBOL}${staged}${RESET}"
    [[ $untracked -gt 0 ]] && indicators="${indicators}${YELLOW}${UNTRACKED_SYMBOL}${untracked}${RESET}"
    [[ $stashed -gt 0 ]] && indicators="${indicators}${CYAN}${STASH_SYMBOL}${stashed}${RESET}"
    
    # Combine branch and indicators
    if [[ -n $indicators ]]; then
        echo " ${git_info} ${DARK_GRAY}[${indicators}${DARK_GRAY}]${RESET}"
    else
        echo " ${git_info}"
    fi
}

# Function to get current time
get_time() {
    date +"%H:%M:%S"
}

# Function to show last command exit status
last_command_status() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo "${RED}✗${exit_code}${RESET} "
    fi
}

# Function to get directory info with path shortening
get_directory() {
    local dir=$(pwd)
    local home_dir="$HOME"
    
    # Replace home directory with ~
    dir=${dir/#$home_dir/\~}
    
    # Shorten long paths: show first 2 and last 2 directories
    if [[ $(echo "$dir" | tr '/' '\n' | wc -l) -gt 4 ]]; then
        local path_parts=(${dir//\// })
        if [[ ${#path_parts[@]} -gt 3 ]]; then
            dir="${path_parts[0]}/${path_parts[1]}/.../${path_parts[-2]}/${path_parts[-1]}"
        fi
    fi
    
    echo "$dir"
}

# Function to show current Python virtual environment
show_virtualenv() {
    if [[ -n "$VIRTUAL_ENV" ]]; then
        local venv_name=$(basename "$VIRTUAL_ENV")
        echo "${PURPLE}(${venv_name})${RESET} "
    fi
}

# Function to show system load (if you want system info)
show_load() {
    local load=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | sed 's/^[ \t]*//')
    if (( $(echo "$load > 1.0" | bc -l) )); then
        echo "${RED}⚠${load}${RESET} "
    fi
}

# Main PS1 setup
setup_ps1() {
    # Store exit code immediately
    local exit_code=$?
    
    # Build PS1 components
    local time_part="${DARK_GRAY}[${LIGHT_CYAN}$(get_time)${DARK_GRAY}]${RESET}"
    local user_part="${LIGHT_GREEN}\u${RESET}"
    local host_part="${LIGHT_BLUE}\h${RESET}"
    local dir_part="${YELLOW}$(get_directory)${RESET}"
    local git_part="$(git_prompt_info)"
    local venv_part="$(show_virtualenv)"
    local status_part=""
    
    # Show exit code if last command failed
    if [[ $exit_code -ne 0 ]]; then
        status_part="${RED}✗${exit_code}${RESET} "
    fi
    
    # Assemble the full prompt
    PS1="${time_part} ${status_part}${venv_part}${user_part}${DARK_GRAY}@${RESET}${host_part}${DARK_GRAY}:${RESET}${dir_part}${git_part}\n${LIGHT_CYAN}❯${RESET} "
}

# Set PROMPT_COMMAND to update PS1 before each prompt
PROMPT_COMMAND=setup_ps1

# Optional: Enable git completion if available
if [ -f /usr/share/bash-completion/completions/git ]; then
    source /usr/share/bash-completion/completions/git
fi

# Optional: Add some useful aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Git aliases for convenience
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate --all'
alias gd='git diff'
alias gb='git branch'
alias gco='git checkout'

echo "Enhanced PS1 with Git integration loaded!"
echo "Your prompt now shows:"
echo "  • Timestamp"
echo "  • Last command exit status (if failed)"
echo "  • Python virtual environment (if active)"
echo "  • Username@hostname"
echo "  • Current directory (shortened if long)"
echo "  • Git branch and detailed status"
echo "  • Clean prompt symbol on new line"



# SSH Agent Auto-Start Function
# Add this entire section to your ~/.bashrc file

# Function to start SSH agent if not running
start_ssh_agent() {
    # Check if ssh-agent is already running
    if pgrep -u "$USER" ssh-agent > /dev/null; then
        # Agent is running, but we need to find the socket
        export SSH_AGENT_PID=$(pgrep -u "$USER" ssh-agent)
        export SSH_AUTH_SOCK=$(find /tmp -path "*/ssh-*" -name "agent*" -uid $(id -u) 2>/dev/null | head -1)
        
        # Verify the connection works
        if ! ssh-add -l >/dev/null 2>&1; then
            # Connection failed, kill and restart
            pkill -u "$USER" ssh-agent
            eval "$(ssh-agent -s)" > /dev/null
        fi
    else
        # No agent running, start one
        eval "$(ssh-agent -s)" > /dev/null
    fi
    
    # Add your GitHub SSH key if it's not already added
    if ! ssh-add -l | grep -q "id_ed25519_github\|id_rsa_github"; then
        # Try to add the key (will prompt for passphrase if set)
        if [[ -f ~/.ssh/id_ed25519_github ]]; then
            ssh-add ~/.ssh/id_ed25519_github 2>/dev/null
        elif [[ -f ~/.ssh/id_rsa_github ]]; then
            ssh-add ~/.ssh/id_rsa_github 2>/dev/null
        fi
    fi
}

# Function to show SSH agent status in prompt (optional)
ssh_agent_status() {
    if ssh-add -l >/dev/null 2>&1; then
        local key_count=$(ssh-add -l | wc -l)
        echo "${GREEN}🔑${key_count}${RESET}"
    else
        echo "${RED}🔒${RESET}"
    fi
}

# Auto-start SSH agent when terminal opens
start_ssh_agent
