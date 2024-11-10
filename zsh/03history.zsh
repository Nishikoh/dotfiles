# -----------------------------
# History
# -----------------------------
# 基本設定
HISTFILE=$HOME/.zsh_history
HISTSIZE=100000
SAVEHIST=1000000

# ヒストリーに重複を表示しない
setopt histignorealldups

# 他のターミナルとヒストリーを共有
setopt share_history

# すでにhistoryにあるコマンドは残さない
setopt hist_ignore_all_dups



# ヒストリに保存するときに余分なスペースを削除する
setopt hist_reduce_blanks

# 履歴をすぐに追加する
setopt inc_append_history

setopt SHARE_HISTORY             # Share history between all sessions.

# ヒストリを呼び出してから実行する間に一旦編集できる状態になる
setopt hist_verify

#余分なスペースを削除してヒストリに記録する
setopt hist_reduce_blanks

# historyコマンドは残さない
setopt hist_save_no_dups

# ^R で履歴検索をするときに * でワイルドカードを使用出来るようにする
bindkey '^R' history-incremental-pattern-search-backward
#bindkey "^S" history-incremental-search-forward

function zle-line-init zle-keymap-select {
    VIM_NORMAL="%K{208}%F{black}⮀%k%f%K{208}%F{white} % NORMAL %k%f%K{black}%F{208}⮀%k%f"
    VIM_INSERT="%K{075}%F{black}⮀%k%f%K{075}%F{white} % INSERT %k%f%K{black}%F{075}⮀%k%f"
    RPS1="${${KEYMAP/vicmd/$VIM_NORMAL}/(main|viins)/$VIM_INSERT}"
    RPS2=$RPS1
    zle reset-prompt
}
# show vim mode
# zle -N zle-line-init
# zle -N zle-keymap-selec

# ^P,^Nを検索へ割り当て
#bindkey "^P" history-beginning-search-backward-end
#bindkey "^N" history-beginning-search-forward-end

eval "$(mcfly init zsh)"
export MCFLY_RESULTS=30
