 # Lang
 # -----------------------------
 #export LANG=ja_JP.UTF-8
 #export LESSCHARSET=utf-8

 # -----------------------------
 # General
 # -----------------------------
 # 色を使用
 autoload -Uz colors ; colors

 # エディタをvimに設定
 export EDITOR=vim

 # Ctrl+Dでログアウトしてしまうことを防ぐ
 setopt IGNOREEOF

 # パスを追加したい場合
 export PATH="$HOME/bin:$PATH"

 # cdした際のディレクトリをディレクトリスタックへ自動追加
 setopt auto_pushd

 # ディレクトリスタックへの追加の際に重複させない
 setopt pushd_ignore_dups

 # emacsキーバインド
 #bindkey -e

 # viキーバインド
bindkey -v

 # フローコントロールを無効にする
 setopt no_flow_control

 # ワイルドカード展開を使用する
 setopt extended_glob

 # cdコマンドを省略して、ディレクトリ名のみの入力で移動
 setopt auto_cd

 # コマンドラインがどのように展開され実行されたかを表示するようになる
 #setopt xtrace

 # 自動でpushdを実行
 setopt auto_pushd

 # pushdから重複を削除
 setopt pushd_ignore_dups

 # ビープ音を鳴らさないようにする
 #setopt no_beep

 # カッコの対応などを自動的に補完する
 setopt auto_param_keys

 # ディレクトリ名の入力のみで移動する
 setopt auto_cd

 # bgプロセスの状態変化を即時に知らせる
 setopt notify

 # 8bit文字を有効にする
 setopt print_eight_bit

 # 終了ステータスが0以外の場合にステータスを表示する
 setopt print_exit_value

 # ファイル名の展開でディレクトリにマッチした場合 末尾に / を付加
 setopt mark_dirs

 # コマンドのスペルチェックをする
 setopt correct

 # コマンドライン全てのスペルチェックをする
 setopt correct_all

 # 上書きリダイレクトの禁止
 setopt no_clobber

 # sudo の後ろでコマンド名を補完する
 zstyle ':completion:*:sudo:*' command-path /usr/local/sbin /usr/local/bin \
                    /usr/sbin /usr/bin /sbin /bin /usr/X11R6/bin

# ps コマンドのプロセス名補完
 zstyle ':completion:*:processes' command 'ps x -o pid,s,args'

# パスの最後のスラッシュを削除しない
setopt noautoremoveslash

 # 各コマンドが実行されるときにパスをハッシュに入れる
#setopt hash_cmds

# rsysncでsshを使用する
export RSYNC_RSH=ssh

# その他
umask 022
ulimit -c 0
                    
# -----------------------------
# Prompt
# -----------------------------
# %M    ホスト名
# %m    ホスト名
# %d    カレントディレクトリ(フルパス)
# %~    カレントディレクトリ(フルパス2)
# %C    カレントディレクトリ(相対パス)
# %c    カレントディレクトリ(相対パス)
# %n    ユーザ名
# %#    ユーザ種別
# %?    直前のコマンドの戻り値
# %D    日付(yy-mm-dd)
# %W    日付(yy/mm/dd)
# %w    日付(day dd)
# %*    時間(hh:flag_mm:ss)
# %T    時間(hh:mm)
# %t    時間(hh:mm(am/pm))
# git設定
#PROMPT='%F{cyan}%n@%m%f:%~# '
PROMPT="%{${fg[blue]}%}%F{magenta}%~%f %{${reset_color}%}"
autoload -Uz vcs_info
setopt prompt_subst
zstyle 'vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr "%F{{yellow}!"
zstyle ':vcs_info:git:*' unstagedstr "%F{red}+"
zstyle ':vcs_info:*' formats "%F{green}%c%u[%b]%f"
zstyle ':vcs_info:*' actionformats "[%b|%a]"
precmd () { vcs_info }
PROMPT=$PROMPT'${vcs_info_msg_0_} ▷  '

# -----------------------------
# Completion
# -----------------------------
# 自動補完を有効にする
autoload -Uz compinit ; compinit

# 単語の入力途中でもTab補完を有効化
setopt complete_in_word

# コマンドミスを修正
setopt correct

# 補完の選択を楽にする
zstyle ':completion:*' menu select

# 補完候補をできるだけ詰めて表示する
setopt list_packed

# 補完候補にファイルの種類も表示する
#setopt list_types

# 色の設定
export LSCOLORS=Exfxcxdxbxegedabagacad

# 補完時の色設定
export LS_COLORS='di=01;34:ln=01;35:so=01;32:ex=01;31:bd=46;34:cd=43;34:su=41;30:sg=46;30:tw=42;30:ow=43;30'

# キャッシュの利用による補完の高速化
zstyle ':completion::complete:*' use-cache true

# 補完候補に色つける
autoload -U colors ; colors ; zstyle ':completion:*' list-colors "${LS_COLORS}"
                    #zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# 大文字・小文字を区別しない(大文字を入力した場合は区別する)
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
# manの補完をセクション番号別に表示させる
zstyle ':completion:*:manuals' separate-sections true

# --prefix=/usr などの = 以降でも補完
setopt magic_equal_subst

# -----------------------------
# History
# -----------------------------
# 基本設定
HISTFILE=$HOME/.zsh-history
HISTSIZE=100000
SAVEHIST=1000000

# ヒストリーに重複を表示しない
setopt histignorealldups

# 他のターミナルとヒストリーを共有
setopt share_history

# すでにhistoryにあるコマンドは残さない
setopt hist_ignore_all_dups

# historyに日付を表示
alias h='fc -lt '%F %T' 1'

# ヒストリに保存するときに余分なスペースを削除する
setopt hist_reduce_blanks

# 履歴をすぐに追加する
setopt inc_append_history

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
zle -N zle-line-init
zle -N zle-keymap-selec

# ^P,^Nを検索へ割り当て
#bindkey "^P" history-beginning-search-backward-end
#bindkey "^N" history-beginning-search-forward-end
# エイリアス
 alias lst='ls -ltr --color=auto'
 alias ls='ls --color=auto'
 alias la='ls -lah --color=auto'
 alias ll='ls -lh --color=auto'

 #go
 export PATH=$PATH:/usr/lib/go-1.14/bin

#ruby
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

#python alias
 #alias python='python3'
 #alias pip='pip3'
 #export PATH="/home/koki/anaconda3/bin:$PATH"



# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/home/koki/anaconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/home/koki/anaconda3/etc/profile.d/conda.sh" ]; then
        . "/home/koki/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="/home/koki/anaconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

