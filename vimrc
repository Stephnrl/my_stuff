" ============================================================================
" BASIC SETTINGS
" ============================================================================

" Enable syntax highlighting
syntax on

" Enable file type detection
filetype plugin indent on

" Set encoding
set encoding=utf-8

" Show line numbers
set number
set relativenumber

" Show cursor position
set ruler

" Highlight current line
set cursorline

" Enable mouse support
set mouse=a

" ============================================================================
" INDENTATION & TABS
" ============================================================================

" Set tab settings
set tabstop=4       " Visual width of tab
set shiftwidth=4    " Width for auto-indents
set expandtab       " Convert tabs to spaces
set smartindent     " Smart auto-indenting
set autoindent      " Copy indent from current line

" Show tabs and trailing spaces (but less intrusive)
set list
set listchars=tab:▸\ ,trail:·,extends:❯,precedes:❮,nbsp:±

" ============================================================================
" SEARCH SETTINGS
" ============================================================================

" Highlight search results
set hlsearch

" Incremental search (search as you type)
set incsearch

" Case insensitive search unless uppercase letters are used
set ignorecase
set smartcase

" ============================================================================
" VISUAL & UI IMPROVEMENTS
" ============================================================================

" Show matching brackets
set showmatch

" Enable 256 colors
set t_Co=256

" Show command in status line
set showcmd

" Always show status line
set laststatus=2

" Better status line
set statusline=%F%m%r%h%w\ [%l,%c]\ [%L\ lines]\ [%p%%]

" Enable folding
set foldmethod=indent
set foldlevel=99

" Disable annoying beeping
set noerrorbells
set novisualbell

" ============================================================================
" FILE HANDLING
" ============================================================================

" Enable backups but put them in a separate directory
set backup
set backupdir=~/.vim/backup//
set directory=~/.vim/swap//
set undodir=~/.vim/undo//

" Create backup directories if they don't exist
silent !mkdir -p ~/.vim/backup ~/.vim/swap ~/.vim/undo

" Better file completion
set wildmenu
set wildmode=longest:full,full

" ============================================================================
" PERFORMANCE & BEHAVIOR
" ============================================================================

" Faster redrawing
set ttyfast

" Don't update screen during macro execution
set lazyredraw

" Time out on key codes but not mappings
set notimeout
set ttimeout
set ttimeoutlen=10

" Keep cursor in same column when jumping
set nostartofline

" Allow backspacing over everything
set backspace=indent,eol,start

" ============================================================================
" FILE TYPE SPECIFIC SETTINGS
" ============================================================================

" Python
autocmd FileType python setlocal tabstop=4 shiftwidth=4 expandtab

" YAML/Ansible
autocmd FileType yaml setlocal tabstop=2 shiftwidth=2 expandtab
autocmd FileType yml setlocal tabstop=2 shiftwidth=2 expandtab

" JavaScript/JSON
autocmd FileType javascript setlocal tabstop=2 shiftwidth=2 expandtab
autocmd FileType json setlocal tabstop=2 shiftwidth=2 expandtab

" Shell scripts
autocmd FileType sh setlocal tabstop=4 shiftwidth=4 expandtab

" ============================================================================
" USEFUL KEY MAPPINGS
" ============================================================================

" Map leader key to space
let mapleader = " "

" Quick save
nnoremap <leader>w :w<CR>

" Quick quit
nnoremap <leader>q :q<CR>

" Clear search highlighting
nnoremap <leader>h :nohl<CR>

" Toggle line numbers
nnoremap <leader>n :set number!<CR>

" Toggle relative line numbers
nnoremap <leader>r :set relativenumber!<CR>

" Toggle paste mode
nnoremap <leader>p :set paste!<CR>

" Move lines up/down
nnoremap <C-j> :m .+1<CR>==
nnoremap <C-k> :m .-2<CR>==

" Better window navigation
nnoremap <C-h> <C-w>h
nnoremap <C-l> <C-w>l

" ============================================================================
" WSL SPECIFIC SETTINGS
" ============================================================================

" Enable clipboard integration with Windows
if system('uname -r') =~ "microsoft"
    " WSL clipboard integration
    let g:clipboard = {
        \ 'name': 'wsl',
        \ 'copy': {
        \   '+': ['clip.exe'],
        \   '*': ['clip.exe'],
        \ },
        \ 'paste': {
        \   '+': ['powershell.exe', '-c', 'Get-Clipboard'],
        \   '*': ['powershell.exe', '-c', 'Get-Clipboard'],
        \ },
        \ 'cache_enabled': 1,
        \ }
endif

" ============================================================================
" PYTHON DEVELOPMENT
" ============================================================================

" Python syntax highlighting improvements
let python_highlight_all = 1

" Python indentation
autocmd BufNewFile,BufRead *.py
    \ set tabstop=4 |
    \ set softtabstop=4 |
    \ set shiftwidth=4 |
    \ set textwidth=79 |
    \ set expandtab |
    \ set autoindent |
    \ set fileformat=unix

" ============================================================================
" ANSIBLE/YAML DEVELOPMENT
" ============================================================================

" YAML specific settings
autocmd BufNewFile,BufRead *.yml,*.yaml
    \ set tabstop=2 |
    \ set softtabstop=2 |
    \ set shiftwidth=2 |
    \ set expandtab |
    \ set autoindent

" Ansible file detection
autocmd BufRead,BufNewFile */playbooks/*.yml set filetype=yaml.ansible
autocmd BufRead,BufNewFile */roles/*.yml set filetype=yaml.ansible

" ============================================================================
" USEFUL COMMANDS
" ============================================================================

" Remove trailing whitespace
command! StripTrailing %s/\s\+$//e

" Convert tabs to spaces
command! TabsToSpaces %s/\t/    /g

" Convert spaces to tabs
command! SpacesToTabs %s/    /\t/g
