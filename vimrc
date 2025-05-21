" Enhanced Vim Configuration with Neovim-like features
" ====================================================

" General Settings
" ---------------
set nocompatible                " Be iMproved (required for many features)
filetype plugin indent on       " Enable filetype detection and plugins
syntax on                       " Enable syntax highlighting
set encoding=utf-8              " Use UTF-8 encoding
set hidden                      " Allow hidden buffers
set backspace=indent,eol,start  " Make backspace behave normally
set history=1000                " Increase command history
set updatetime=300              " Faster updates (good for plugins)
set autoread                    " Auto-reload changed files
set mouse=a                     " Enable mouse support
set clipboard=unnamed           " Use system clipboard (if available)
set termguicolors               " Use true colors (if supported)

" Visual Improvements
" ------------------
set number                      " Show line numbers
set relativenumber              " Show relative line numbers
set cursorline                  " Highlight current line
set showmatch                   " Highlight matching parentheses
set showcmd                     " Show command in status line
set wildmenu                    " Better command-line completion
set wildmode=longest:full,full  " More intuitive tab completion
set laststatus=2                " Always show status line
set signcolumn=yes              " Always show sign column (for git/linting)
set scrolloff=8                 " Keep cursor away from screen edge
set sidescrolloff=8             " Keep cursor away from screen edge horizontally
set display+=lastline           " Always try to show paragraph's last line

" Search & Replace
" --------------
set incsearch                   " Incremental search
set hlsearch                    " Highlight search results
set ignorecase                  " Case-insensitive search by default
set smartcase                   " Unless search contains uppercase chars
" Clear search highlight with ESC in normal mode
nnoremap <silent> <Esc> :nohlsearch<CR>

" Indentation & Formatting
" -----------------------
set expandtab                   " Use spaces instead of tabs
set smarttab                    " Smarter tab behavior
set shiftwidth=4                " One tab = 4 spaces
set tabstop=4                   " Width of actual tab character
set softtabstop=4               " Backspace deletes whole tabs
set autoindent                  " Copy indent from current line
set smartindent                 " Smart autoindenting on new line
set wrap                        " Wrap lines
set linebreak                   " Don't break words when wrapping
set breakindent                 " Preserve indentation in wrapped text

" Performance & Files
" -----------------
set lazyredraw                  " Don't redraw during macros (for performance)
set ttyfast                     " Faster terminal redraw
set noswapfile                  " No swap files

" Set backup/undo directories (for persistence)
if has('persistent_undo')
  set undofile
  set undodir=~/.vim/undo
endif

" Create directories if they don't exist
if !isdirectory($HOME.'/.vim/undo')
  call mkdir($HOME.'/.vim/undo', 'p', 0700)
endif

" Splits
" ------
set splitbelow                  " Open horizontal splits below
set splitright                  " Open vertical splits to the right

" Mappings
" -------
" Leader key
let mapleader = " "
let maplocalleader = " "

" Better split navigation
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Terminal emulation (like Neovim)
if has('terminal')
  nnoremap <leader>t :terminal<CR>
endif

" Better buffer navigation
nnoremap <leader>bn :bnext<CR>
nnoremap <leader>bp :bprevious<CR>
nnoremap <leader>bd :bdelete<CR>
nnoremap <leader>ls :ls<CR>

" Tab navigation
nnoremap <leader>tn :tabnew<CR>          " Create new tab
nnoremap <leader>tc :tabclose<CR>        " Close current tab
nnoremap <C-PageUp> :tabprevious<CR>     " Previous tab with Ctrl+PageUp
nnoremap <C-PageDown> :tabnext<CR>       " Next tab with Ctrl+PageDown
nnoremap <leader>t1 1gt                  " Go to tab 1
nnoremap <leader>t2 2gt                  " Go to tab 2
nnoremap <leader>t3 3gt                  " Go to tab 3
nnoremap <leader>t4 4gt                  " Go to tab 4
nnoremap <leader>t5 5gt                  " Go to tab 5
nnoremap <leader>t6 6gt                  " Go to tab 6
nnoremap <leader>t7 7gt                  " Go to tab 7
nnoremap <leader>t8 8gt                  " Go to tab 8
nnoremap <leader>t9 9gt                  " Go to tab 9

" File explorer
nnoremap <leader>e :Explore<CR>

" Save and quit shortcuts
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>wq :wq<CR>

" Reload vimrc
nnoremap <leader>sv :source $MYVIMRC<CR>
nnoremap <leader>ev :edit $MYVIMRC<CR>

" Install vim-plug if not found
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" Initialize plugin system
call plug#begin('~/.vim/plugged')

" Plugins that mimic Neovim capabilities
" -------------------------------------
" Asynchronous operations (like Neovim)
Plug 'tpope/vim-dispatch'                  " Asynchronous build and test dispatcher

" Fuzzy finding (like Telescope in Neovim)
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'                    " Fuzzy finder integration

" Better syntax highlighting (like Treesitter in Neovim)
Plug 'sheerun/vim-polyglot'                " Language pack

" Git integration
Plug 'airblade/vim-gitgutter'              " Shows git diff in gutter
Plug 'tpope/vim-fugitive'                  " Git commands

" Auto-completion and language features
Plug 'prabirshrestha/vim-lsp'              " Language Server Protocol
Plug 'mattn/vim-lsp-settings'              " Auto-configurations for LSP
Plug 'prabirshrestha/asyncomplete.vim'     " Async completion
Plug 'prabirshrestha/asyncomplete-lsp.vim' " LSP source for asyncomplete

" File explorer improvements (alternative to Nvim-tree)
Plug 'preservim/nerdtree'                  " Improved file browser

" Status line (like lualine in Neovim)
Plug 'vim-airline/vim-airline'             " Status line
Plug 'vim-airline/vim-airline-themes'      " Status line themes

" Color scheme (similar to popular Neovim themes)
Plug 'joshdick/onedark.vim'                " Color scheme
Plug 'morhetz/gruvbox'                     " Another popular theme
Plug 'catppuccin/vim', { 'as': 'catppuccin' } " Catppuccin theme

" Commenting
Plug 'tpope/vim-commentary'                " Easy code commenting

" Surround text
Plug 'tpope/vim-surround'                  " Edit surrounding chars

" Initialize plugin system
call plug#end()

" Plugin Configuration
" ------------------

" FZF configuration (like Telescope)
nnoremap <leader>ff :Files<CR>
nnoremap <leader>fg :Rg<CR>
nnoremap <leader>fb :Buffers<CR>
nnoremap <leader>fh :History<CR>

" NERDTree configuration
nnoremap <leader>n :NERDTreeToggle<CR>
nnoremap <leader>nf :NERDTreeFind<CR>

" Open NERDTree automatically when vim starts
autocmd VimEnter * NERDTree
" Focus on the main window after opening NERDTree
autocmd VimEnter * wincmd p
" Close vim if NERDTree is the only window remaining
autocmd BufEnter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif

" Use Airline
let g:airline_powerline_fonts = 1
let g:airline#extensions#tabline#enabled = 1

" Theme settings
if has('termguicolors')
  set termguicolors
endif

" Set Catppuccin theme options (before applying the colorscheme)
let g:catppuccin_flavour = "mocha" " Options: latte, frappe, macchiato, mocha
colorscheme catppuccin " Or use onedark or gruvbox if you prefer

" Customize airline theme to match
let g:airline_theme = 'catppuccin'

" LSP Configuration
if executable('pylsp')
    " Python
    au User lsp_setup call lsp#register_server({
        \ 'name': 'pylsp',
        \ 'cmd': {server_info->['pylsp']},
        \ 'allowlist': ['python'],
        \ })
endif

if executable('typescript-language-server')
    " TypeScript/JavaScript
    au User lsp_setup call lsp#register_server({
        \ 'name': 'typescript-language-server',
        \ 'cmd': {server_info->['typescript-language-server', '--stdio']},
        \ 'root_uri':{server_info->lsp#utils#path_to_uri(lsp#utils#find_nearest_parent_file_directory(lsp#utils#get_buffer_path(), 'tsconfig.json'))},
        \ 'allowlist': ['typescript', 'javascript', 'javascript.jsx', 'typescript.tsx'],
        \ })
endif

" LSP keybindings (similar to Neovim LSP)
function! s:on_lsp_buffer_enabled() abort
    setlocal omnifunc=lsp#complete
    setlocal signcolumn=yes
    if exists('+tagfunc') | setlocal tagfunc=lsp#tagfunc | endif
    
    nmap <buffer> gd <plug>(lsp-definition)
    nmap <buffer> gr <plug>(lsp-references)
    nmap <buffer> gi <plug>(lsp-implementation)
    nmap <buffer> gt <plug>(lsp-type-definition)
    nmap <buffer> <leader>rn <plug>(lsp-rename)
    nmap <buffer> [g <plug>(lsp-previous-diagnostic)
    nmap <buffer> ]g <plug>(lsp-next-diagnostic)
    nmap <buffer> K <plug>(lsp-hover)
    
    " Formatting
    nmap <buffer> <leader>f <plug>(lsp-document-format)
    
    let g:lsp_format_sync_timeout = 1000
endfunction

augroup lsp_install
    au!
    " call s:on_lsp_buffer_enabled only for languages that has the server registered.
    autocmd User lsp_buffer_enabled call s:on_lsp_buffer_enabled()
augroup END

" Autocomplete configuration
let g:asyncomplete_auto_popup = 1
let g:asyncomplete_auto_completeopt = 0
set completeopt=menuone,noinsert,noselect,preview

" Close preview window after completion
autocmd! CompleteDone * if pumvisible() == 0 | pclose | endif

" Custom commands
" --------------
" Create a new terminal split below (like in Neovim)
if has('terminal')
  command! Term below terminal
  command! Vterm vertical terminal
endif

" Additional customizations to match Neovim defaults
" -------------------------------------------------
set noshowmode                  " Don't show mode (shown by airline)
set shortmess+=c                " Don't show ins-completion-menu messages
set ttimeout                    " Enable timeout for key codes
set ttimeoutlen=100             " Faster key sequence timeouts
set cmdheight=2                 " More space for command line

" Check if running in a GUI
if has('gui_running')
  set guioptions-=T             " Remove toolbar
  set guioptions-=m             " Remove menu bar
  set guioptions-=r             " Remove right scrollbar
  set guioptions-=L             " Remove left scrollbar
endif

" Custom helper functions
" ----------------------
" Toggle relative line numbers
function! ToggleRelativeNumbers()
  if &relativenumber
    set norelativenumber
  else
    set relativenumber
  endif
endfunction

nnoremap <leader>tr :call ToggleRelativeNumbers()<CR>

" Toggle quickfix window
function! ToggleQuickFix()
  if empty(filter(getwininfo(), 'v:val.quickfix'))
    copen
  else
    cclose
  endif
endfunction

nnoremap <leader>c :call ToggleQuickFix()<CR>

" Auto commands
" ------------
augroup custom_settings
  autocmd!
  " Return to last edit position when opening files
  autocmd BufReadPost *
    \ if line("'\"") > 0 && line("'\"") <= line("$") |
    \   exe "normal! g`\"" |
    \ endif
  
  " Auto-format on save (if supported by LSP)
  autocmd BufWritePre *.js,*.ts,*.py,*.go
    \ if exists('g:lsp_format_sync_timeout') |
    \   call lsp#document_format() |
    \ endif
augroup END

" Customize based on filetypes
augroup filetype_specific
  autocmd!
  " Different indentation for specific file types
  autocmd FileType html,css,javascript,typescript,json setlocal shiftwidth=2 tabstop=2
  autocmd FileType python setlocal shiftwidth=4 tabstop=4
  autocmd FileType go setlocal noexpandtab shiftwidth=4 tabstop=4
augroup END

" Terminal settings (more like Neovim)
" -----------------------------------
if has('terminal')
  " Use Escape to enter normal mode in terminal
  tnoremap <Esc> <C-\><C-n>
  
  " Window navigation from terminal
  tnoremap <C-h> <C-\><C-n><C-w>h
  tnoremap <C-j> <C-\><C-n><C-w>j
  tnoremap <C-k> <C-\><C-n><C-w>k
  tnoremap <C-l> <C-\><C-n><C-w>l
  
  " Auto enter insert mode when entering terminal
  autocmd BufWinEnter,WinEnter term://* startinsert
endif
