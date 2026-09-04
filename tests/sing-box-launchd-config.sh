#!/bin/sh
set -eu

source_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
service=$(chezmoi execute-template < "$source_root/dot_config/private_sing-box/launchd/com.yangshunxiang.sing-box.plist.tmpl")
limiter=$(chezmoi execute-template < "$source_root/dot_config/private_sing-box/launchd/com.yangshunxiang.sing-box-log-limit.plist.tmpl")

printf '%s' "$service" | plutil -lint - >/dev/null
printf '%s' "$limiter" | plutil -lint - >/dev/null
printf '%s' "$service" | grep -q '<key>RunAtLoad</key>'
printf '%s' "$service" | grep -q '<key>KeepAlive</key>'
printf '%s' "$limiter" | grep -q '<integer>60</integer>'
printf '%s' "$limiter" | grep -q '<string>5242880</string>'
printf '%s' "$limiter" | grep -q '<string>1048576</string>'
