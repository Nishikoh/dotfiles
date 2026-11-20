# -----------------------------
# Completion
# -----------------------------

# 補完スクリプトを fpath に置く (compinit より前に置く)
# リポジトリの補完 (zsh/completions)。ツールが補完スクリプトを出せない claude など
fpath=("${ZSH_CONFIG_PATH:-$HOME/setup/dotfiles/zsh}/completions" $fpath)

# mise で入れたツールが出力する補完スクリプト。生成物はリポジトリではなくキャッシュに置き、
# ツールが入れ替わったとき (パスが変わる mise upgrade と、mtime が変わる自己更新) だけ作り直す。
# プロジェクトの mise.toml でこれらのツールのバージョンを変えると、そのディレクトリで開くたびに作り直す (今はどこでも latest なので起きない)
_zsh_comp_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/completions"
fpath=("$_zsh_comp_dir" $fpath)

# _zsh_comp_gen <コマンド> <補完スクリプトを出力する引数...>
_zsh_comp_gen() {
	# 補完関数のほかのファイルの名前は _ で始めない (compinit が補完関数として拾う)
	local name=$1 bin=${commands[$1]} out="$_zsh_comp_dir/_$1" failed="$_zsh_comp_dir/failed.$1" stamp line tmp
	local -a mtime limit
	shift
	# 無いときと、lazy のツールで shim しか無いとき (実行するとインストールが始まる) は作らない
	[[ -n $bin && $bin != "${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims/"* ]] || return 0
	setopt local_options extended_glob
	zmodload -F zsh/stat b:zstat || return 0
	zstat -A mtime +mtime -- "${bin:A}" || return 0
	# 実行したときの実体のパスと mtime を、補完スクリプトの 2 行目 (作れなかったときは failed.<コマンド>) に書いておき、
	# 変わるまでは実行しない (自己更新で mtime が古くなっても気づく)。
	# 作れなかったときは、一時的な失敗かもしれないので 1 日たったら実行し直す
	stamp="# source: ${bin:A} $mtime[1]"
	if [[ -s $out ]]; then
		{ read -r line; read -r line } <"$out"
		[[ $line == "$stamp" ]] && return 0
	fi
	if [[ -n $failed(#qN.mh-24) ]]; then
		read -r line <"$failed"
		[[ $line == "$stamp" ]] && return 0
	fi
	mkdir -p "$_zsh_comp_dir" || return 0
	# 先に作れなかったと記録しておく。同時に開いたシェル (herdr のペインなど) は、ツールが止まっていても待たずに済む
	print -r -- "$stamp" >|"$failed"
	# 同時に開いたシェルと取り合わないよう、一時ファイルに書いてから置き換える
	tmp="$_zsh_comp_dir/tmp.$name.$$"
	# ツールが止まってもシェルが開くよう、timeout があれば 5 秒で打ち切る (作れなかった扱いになる)。
	# --foreground は Ctrl-C で止められるようにする
	if (( $+commands[timeout] )); then
		limit=(timeout --foreground 5)
	elif (( $+commands[gtimeout] )); then
		limit=(gtimeout --foreground 5)
	fi
	if $limit "$bin" "$@" </dev/null >|"$tmp" 2>/dev/null && { read -r line } <"$tmp" && [[ $line == "#compdef "* ]]; then
		# 前に作った補完スクリプトは、作れたときだけ置き換える (作れなければ前のものをそのまま使う)
		{ print -r -- "$line"; print -r -- "$stamp"; tail -n +2 "$tmp" } >|"$tmp.new" && mv -f "$tmp.new" "$out" && rm -f "$failed"
	fi
	rm -f "$tmp" "$tmp.new"
}
# gh・uv・rg などは argc-completions にあるので作らない (99local.zsh などで argc-completions を読むと、後から読むそちらが使われる)
_zsh_comp_gen mise completion zsh
_zsh_comp_gen codex completion zsh
_zsh_comp_gen herdr completion zsh
_zsh_comp_gen hunk completion zsh
unfunction _zsh_comp_gen
unset _zsh_comp_dir

# 自動補完を有効にする
autoload -Uz compinit
compinit -u

# 単語の入力途中でもTab補完を有効化
setopt complete_in_word

# 補完の選択を楽にする
zstyle ':completion:*' menu select

# 補完候補をできるだけ詰めて表示する
setopt list_packed

# 補完候補にファイルの種類も表示する
setopt list_types

# 色の設定
export LSCOLORS=Exfxcxdxbxegedabagacad

# 補完時の色設定
export LS_COLORS='di=01;34:ln=01;35:so=01;32:ex=01;31:bd=46;34:cd=43;34:su=41;30:sg=46;30:tw=42;30:ow=43;30'

# キャッシュの利用による補完の高速化
zstyle ':completion::complete:*' use-cache true

# 補完候補に色つける
zstyle ':completion:*' list-colors "${LS_COLORS}"

# 大文字・小文字を区別しない(大文字を入力した場合は区別する)
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
# manの補完をセクション番号別に表示させる
zstyle ':completion:*:manuals' separate-sections true

# --prefix=/usr などの = 以降でも補完
setopt magic_equal_subst

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# nix
if [ -e ~/.nix-profile/etc/profile.d/nix.sh ]; then . ~/.nix-profile/etc/profile.d/nix.sh; fi
