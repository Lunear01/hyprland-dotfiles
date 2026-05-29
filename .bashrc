#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

fastfetch
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias die='poweroff'
PS1='------------------\n\[$(tput setaf 26)\][\[$(tput setaf 32)\]\u \[$(tput setaf 38)\]@ \[$(tput setaf 44)\]\h\[$(tput setaf 26)\]] \[$(tput setaf 75)\]\w\[$(tput sgr0)\]\n > '
alias connect-uoft='TERM=xterm-256color ssh huangike@teach.cs.utoronto.ca'

uoft-push() {
    scp -r "$1" huangike@teach.cs.utoronto.ca:~;
}

export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
export PATH="$HOME/.local/bin:$PATH"

export PATH=$PATH:$HOME/.spicetify
