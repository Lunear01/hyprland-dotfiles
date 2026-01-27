#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias die='poweroff'
PS1='[\u@\h \W]\$ '
alias connect-uoft='TERM=xterm-256color ssh huangike@teach.cs.utoronto.ca'

uoft-push() {
    scp -r "$1" huangike@teach.cs.utoronto.ca:~;
}

export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
export PATH="$HOME/.local/bin:$PATH"

export PATH=$PATH:/home/lunear/.spicetify
export PATH=$PATH:$HOME/.spicetify
