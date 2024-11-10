#!/bin/bash

# 入力ファイルが指定されていない場合はエラーメッセージを表示
if [ -z "$1" ]; then
	echo "Usage: $0 <input_file>"
	exit 1
fi

# 入力ファイルの引数を読み込む
input_file="$1"

# 入力ファイルの内容を格納する
command_args=$(cat "$input_file")

# 最初の行（コマンド部分）を抽出
command=$(echo "$command_args" | head -n 1)

# 2行目以降の引数を抽出してソート
sorted_args=$(echo "$command_args" | sed '1d; s/\\//g' | sort)

# ソートした結果を新しいファイルに出力
echo "$command" >$input_file

# 各引数を改行で出力し、最後の引数の後にはバックスラッシュをつけないようにする
echo "$sorted_args" | sed '$!s/$/ \\/' >>$input_file

# sort bin_github.txt | tee bin_github.txt
