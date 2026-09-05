#!/bin/sh
set -eu

source_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
service=$(chezmoi execute-template < "$source_root/dot_config/private_sing-box/launchd/com.yangshunxiang.sing-box.plist.tmpl")
limiter=$(chezmoi execute-template < "$source_root/dot_config/private_sing-box/launchd/com.yangshunxiang.sing-box-log-limit.plist.tmpl")

printf '%s' "$service" | plutil -lint - >/dev/null
printf '%s' "$limiter" | plutil -lint - >/dev/null
[ "$(printf '%s' "$service" | plutil -extract KeepAlive raw -o - -)" = true ]
if printf '%s' "$service" | plutil -extract RunAtLoad raw -o - - >/dev/null 2>&1; then exit 1; fi
[ "$(printf '%s' "$service" | plutil -extract ProcessType raw -o - -)" = Background ]
printf '%s' "$service" | grep -q '/\.local/libexec/sing-box-start-when-network-ready</string>'
printf '%s' "$service" | grep -q '/\.local/share/sing-box/private/10-outbounds.json</string>'
printf '%s' "$service" | grep -q '/opt/homebrew/bin/sing-box</string>'
printf '%s' "$limiter" | grep -q '<integer>60</integer>'
printf '%s' "$limiter" | grep -q '<string>5242880</string>'
printf '%s' "$limiter" | grep -q '<string>1048576</string>'
