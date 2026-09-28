#!/bin/bash
# ZehnStudio danger-guard — Claude Code PreToolUse hook (Bash / PowerShell tools)
#
# 目的: 「git でも復元できない操作」と「ダウンロード即実行」だけを機械的にブロックする最小ガード。
# CLAUDE.md のルールはモデルへのお願いにすぎないが、この hook はプロンプトインジェクションを
# 受けた場合でも実行前に機械的に止める（exit 2 = ツール呼び出しをブロック）。
#
# ブロック対象（これだけ。日常の削除やビルドは邪魔しない）:
#   1. curl/wget/iwr/irm の結果をそのままシェルに流す (pipe-to-shell)
#   2. ホーム・ファイルシステムルート・ドライブ直下への再帰削除
#   3. git push --force / -f（共有履歴の破壊）
#
# 誤検知した場合（コミットメッセージに危険コマンド文字列を引用した等）は、
# そのコマンドを人間がターミナルで直接実行すればよい。

INPUT="$(cat)"

block() {
  echo "BLOCKED by ZehnStudio danger-guard: $1" >&2
  echo "This operation is irreversible or unsafe and is machine-blocked for all members." >&2
  echo "If it is genuinely needed, the user must run it manually in the terminal (or ask Jawad/Bee)." >&2
  exit 2
}

m() { printf '%s' "$INPUT" | grep -qiE "$1"; }

SP='[[:space:]]'
Q='\\?["'\'']?'

# --- 1) download piped straight into a shell -------------------------------
m "(curl|wget)[^|;&]*\|${SP}*(sudo${SP}+)?(ba|z|da)?sh([^a-z]|$)" \
  && block "downloaded content piped into a shell (curl|wget ... | sh)"
m "(iwr|irm|invoke-webrequest|invoke-restmethod)[^|]*\|${SP}*iex" \
  && block "downloaded content piped into Invoke-Expression"
m "iex${SP}*\([^)]*(iwr|irm|invoke-webrequest|invoke-restmethod)" \
  && block "Invoke-Expression on downloaded content"

# --- 2) recursive delete of home / root / drive root -----------------------
# 対象: rm -r 系で、ターゲットが / ~ $HOME %USERPROFILE% $env:USERPROFILE X:\ のとき
ROOTS='(/|~|\$HOME|%USERPROFILE%|\$env:USERPROFILE|[a-z]:)'
m "rm${SP}+(-{1,2}[a-z-]+${SP}+)*(-[a-z]*r[a-z]*|--recursive)(${SP}+-{1,2}[a-z-]+)*${SP}+${Q}${ROOTS}[\\\\/]*\*?${Q}(${SP}|$|[;&|\"])" \
  && block "recursive delete of home / root / drive root (rm -r)"
m "remove-item[^;|]*${SP}${Q}([a-z]:[\\\\/]+\*?|\\\$env:userprofile[\\\\/]*\*?)${Q}(${SP}|$|[;&|\"])" \
  && block "Remove-Item on drive root / user profile"

# --- 3) force push (shared history destruction) ----------------------------
m "git${SP}+push[^;&|]*${SP}(-f|--force(-with-lease)?)(${SP}|$|[\";&|])" \
  && block "git push --force (rewrites shared history)"

exit 0
