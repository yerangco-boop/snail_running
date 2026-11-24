#!/usr/bin/env bash
# PreToolUse(Bash) 훅: `git push` 직전에 dart analyze(오류만 실패) + flutter test를 돌린다.
# 실패하면 마지막 40줄을 stderr로 내고 exit 2(→ push 차단). Flutter 없는 PC(노트북)는 그냥 통과.
input=$(cat)
# 명령 안의 이스케이프된 따옴표(\")를 먼저 지워야 `cd "..."; git push`처럼 따옴표 뒤에 오는 push도 잡힘
echo "$input" | sed 's/\\"//g' | grep -Eq '"command"[[:space:]]*:[[:space:]]*"[^"]*git push' || exit 0
command -v flutter >/dev/null 2>&1 || exit 0

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}" || exit 0
before=$(git diff --name-only)
log=$(mktemp)

dart analyze --no-fatal-warnings lib test >"$log" 2>&1 && flutter test >>"$log" 2>&1
status=$?

# 이번 실행이 새로 바꾼 추적 파일(플러그인 등록 파일, local.properties 등)만 되돌림
comm -13 <(echo "$before" | sort) <(git diff --name-only | sort) | while read -r f; do
  [ -n "$f" ] && git checkout -- "$f"
done

if [ $status -ne 0 ]; then
  echo "[pre-push-check] dart analyze 또는 flutter test 실패 — push를 막았습니다." >&2
  tail -n 40 "$log" >&2
  rm -f "$log"
  exit 2
fi
rm -f "$log"
exit 0
