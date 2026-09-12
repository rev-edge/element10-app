#!/bin/bash
# Runs the extracted CI steps in order against the local review database; logs PASS/FAIL per step.
S=$REVIEW_SCRATCH
cd $REPO
export E10_DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
export DATABASE_URL="$E10_DB_URL"
export E10_ADMIN_EMAIL=e10adm@example.com E10_ADMIN_PW='CiLocal!23456' E10_MEMBER_EMAIL=e10mem@example.com E10_MEMBER_PW='CiLocal!23456' E10_GATE_EMAIL=e10gate@example.com E10_GATE_PW='CiLocal!23456'
: > $S/ci_results.txt; mkdir -p $S/ci_logs
i=0
while IFS= read -r step; do
  i=$((i+1)); name=$(echo "$step" | grep -o -E "tests/[A-Za-z0-9_./]+" | head -1 | sed 's#tests/##')
  log=$S/ci_logs/$(printf %03d $i)_$name.log
  start=$(date +%s)
  if bash -c "$step" > "$log" 2>&1; then r=PASS; else r=FAIL; fi
  echo "$r $(( $(date +%s)-start ))s $step" >> $S/ci_results.txt
done < $S/ci_steps.txt
echo DONE >> $S/ci_results.txt
