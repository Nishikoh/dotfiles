# ripgrep->fzf->vim [QUERY]
_rfv() (
	RELOAD='reload:rg --column --color=always --smart-case {q} || :'
	OPENER='if [[ $FZF_SELECT_COUNT -eq 0 ]]; then
            vim {1} +{2}     # No selection. Open the current line in Vim.
          else
            vim +cw -q {+f}  # Build quickfix list for the selected items.
          fi'
	fzf --disabled --ansi --multi \
		--bind "start:$RELOAD" --bind "change:$RELOAD" \
		--bind "enter:become:$OPENER" \
		--bind "ctrl-o:execute:$OPENER" \
		--bind 'alt-a:select-all,alt-d:deselect-all,ctrl-/:toggle-preview' \
		--delimiter : \
		--preview 'bat --style=full --color=always --highlight-line {2} {1}' \
		--preview-window '~4,+{2}+4/3,<80(up)' \
		--query "$*"
)
alias rfv='_rfv'

# fd -> fzf -> cd
_cdf(){
	_cdf_run(){
		dir=$(fd -t d $1 $2 | fzf --preview 'exa -T -L 2 -a -I ".git" {}' ) || return
		echo $dir
		cd $dir
	}
	if [ $# -ge 2 ]; then
		_cdf_run $1 $2
		return
	elif [ $# -eq 1 ]; then
		_cdf_run $1 .
	elif [ $# -eq 0 ]; then
		_cdf_run '' .
  	fi
}
alias cdf='_cdf'