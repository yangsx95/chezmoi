# Read-only status and diagnostic commands, sourced by sing-box-managed.
# Uses the manager path constants and presentation/process helper functions.
# diagnostic_result owns aggregation; result_row only renders output.

diagnostic_result() {
  result_row "$@"
  [ "$1" != FAIL ] || report_failed=1
}

http_probe() {
  probe_label=$1; probe_url=$2; shift 2
  if probe_output=$(/usr/bin/curl --noproxy '*' "$@" --silent --output /dev/null --connect-timeout 2 --max-time 4 --write-out '%{http_code} %{time_total}s' "$probe_url" 2>/dev/null); then
    case "$probe_output" in 2*|3*) probe_result=PASS ;; *) probe_result=CHECK ;; esac
    diagnostic_result "$probe_result" "$probe_label" "HTTP $probe_output"
  else
    diagnostic_result FAIL "$probe_label" "connection failed ($probe_output)"
  fi
}

startup_status() {
  # Loaded and disabled are independent: disable does not stop a loaded job.
  if ! disabled_output=$(launchctl print-disabled system 2>/dev/null); then
    field Autostart UNKNOWN
    return
  fi
  override=$(printf '%s\n' "$disabled_output" | awk -v label="\"$1\"" '$1 == label {print $3}')
  case "$override" in
    true|disabled) field Autostart disabled; return ;;
  esac
  if [ ! -f "$2" ]; then
    field Autostart 'not installed'
  elif [ "$override" = enabled ] || [ "$override" = false ]; then
    field Autostart enabled
  elif default_disabled=$(plutil -extract Disabled raw -o - "$2" 2>/dev/null); then
    case "$default_disabled" in true) field Autostart disabled ;; false) field Autostart enabled ;; *) field Autostart UNKNOWN ;; esac
  elif plutil -lint "$2" >/dev/null 2>&1; then
    field Autostart enabled
  else
    field Autostart UNKNOWN
  fi
}

launch_service_status() {
  if launch_output=$(launchctl print "system/$1" 2>/dev/null); then
    field 'Launch service' loaded
    launch_exit=$(printf '%s\n' "$launch_output" | awk '/^[ \t]*last exit code =/ {print $5; exit}')
    launch_signal=$(printf '%s\n' "$launch_output" | awk '/^[ \t]*last terminating signal =/ {print $5; exit}')
    launch_pid=$(printf '%s\n' "$launch_output" | awk '/^[ \t]*pid =/ {print $3; exit}')
    if [ "$3" = absent ]; then
      if [ -n "$launch_pid" ]; then
        field Service 'starting (launcher active)'
        if [ -n "$launch_exit" ] && [ "$launch_exit" != 0 ] && [ "$launch_exit" != '(never' ]; then
          field 'Previous exit' "$launch_exit"
        fi
        [ -z "$launch_signal" ] || field 'Previous signal' "$launch_signal"
      elif [ -n "$launch_signal" ] || { [ -n "$launch_exit" ] && [ "$launch_exit" != 0 ] && [ "$launch_exit" != '(never' ]; }; then
        field Service 'exited; launchd may retry'
        [ -z "$launch_exit" ] || field 'Last exit' "$launch_exit"
        [ -z "$launch_signal" ] || field 'Last signal' "$launch_signal"
      else
        field Service 'pending (no process; cause UNKNOWN)'
      fi
    fi
  else
    field 'Launch service' 'not loaded or inaccessible'
    [ "$3" != absent ] || field Service 'not running'
  fi
  startup_status "$1" "$2"
}

doctor_sing_box() {
  report_failed=0
  status_all || report_failed=1
  browser_policy_diagnostics
  section 'DNS blocking · local resolver'
  block_test_index=0
  for domain in gamebus001.com pornhub.com hongguoduanju.com; do
    block_test_index=$((block_test_index + 1))
    answer=$(/usr/bin/dig @127.0.0.1 "$domain" A +short +time=2 +tries=1 2>&1) || true
    if printf '%s\n' "$answer" | grep -Fq 'This query has been locally blocked'; then
      diagnostic_result PASS "Block test $block_test_index" 'local block response'
    else
      diagnostic_result FAIL "Block test $block_test_index" 'expected block response not received'
    fi
  done
  section 'Connectivity'
  interface=$(/sbin/route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
  field 'Default interface' "${interface:-unavailable}"
  dns_answer=$(/usr/bin/dig @127.0.0.1 example.com A +time=2 +tries=1 +noall +answer 2>/dev/null) || true
  if printf '%s\n' "$dns_answer" | awk '$4 == "A" {found=1} END {exit !found}'; then
    diagnostic_result PASS 'Local DNS / example.com' 'IPv4 answer received'
  else
    diagnostic_result FAIL 'Local DNS / example.com' 'no IPv4 answer'
  fi
  for mode in normal physical; do
    set --
    if [ "$mode" = physical ]; then
      case "$interface" in ''|lo*|utun*) diagnostic_result SKIP 'Physical interface' 'no physical default interface'; continue ;; esac
      set -- --interface "$interface"
    fi
    for url in https://www.jd.com http://captive.apple.com/hotspot-detect.html; do
      case "$url" in *jd.com*) probe_name=JD ;; *) probe_name='Apple connectivity' ;; esac
      http_probe "$mode / $probe_name" "$url" "$@"
    done
  done
  http_probe 'Proxy / Google' https://www.google.com
  printf '\nHTTP checks verify responses, not page content or Safe Search enforcement.\n'
  printf 'For startup errors: sing-box-managed logs -n 100\n'
  return "$report_failed"
}

status_sing_box() {
  section 'sing-box'
  pid=$(sing_box_pid)
  if [ -z "$pid" ]; then
    launch_service_status "$launchd_label" "$launchd_plist" absent
    field 'Next step' 'sing-box-managed logs -n 100'
    return 1
  fi
  user=$(ps -p "$pid" -o user= | tr -d ' ')
  elapsed=$(ps -p "$pid" -o etime= | tr -d ' ')
  rss_kib=$(ps -p "$pid" -o rss= | tr -d ' ')
  memory_mib=$(awk -v rss_kib="$rss_kib" 'BEGIN { printf "%.1f MiB", rss_kib / 1024 }')
  field Service running
  field Process "PID $pid · $user"
  field Uptime "$elapsed"
  field Memory "$memory_mib"
  launch_service_status "$launchd_label" "$launchd_plist" present
}

browser_security_status() {
  section 'Browser DNS security'
  if ! profile_output=$(profiles show -type configuration 2>/dev/null); then
    field Profile 'UNKNOWN (cannot read profiles)'
  elif printf '%s\n' "$profile_output" | grep -Fq 'profileIdentifier: com.yangshunxiang.singbox.browser-security'; then
    field Profile installed
  else
    field Profile 'not found in accessible profiles'
    return 1
  fi
}

status_all() {
  service_result=0
  status_sing_box || service_result=$?
  dns_pid=$(pgrep -x dnscrypt-proxy | head -n 1 || true)
  section 'dnscrypt-proxy'
  if [ -n "$dns_pid" ]; then
    field Service "running (PID $dns_pid)"
  else
    service_result=1
  fi
  dns_presence=absent
  [ -z "$dns_pid" ] || dns_presence=present
  launch_service_status homebrew.mxcl.dnscrypt-proxy /Library/LaunchDaemons/homebrew.mxcl.dnscrypt-proxy.plist "$dns_presence"
  browser_security_status || service_result=1
  printf '\nStatus shows installation/process state. Test functionality: sing-box-managed doctor\n'
  return "$service_result"
}

browser_policy_diagnostics() {
  section 'Browser managed policies · files only'
  diagnostic_result UNKNOWN 'Browser runtime' 'not checked'
  for browser in com.google.Chrome com.microsoft.Edge; do
    found_policy=false
    for policy_file in "/Library/Managed Preferences/$browser.plist" "/Library/Managed Preferences/$(id -un)/$browser.plist"; do
      [ -f "$policy_file" ] || continue
      found_policy=true
      printf '%s\n' "$policy_file"
      for key in DnsOverHttpsMode ForceGoogleSafeSearch ForceYouTubeRestrict; do
        case "$key" in DnsOverHttpsMode) expected=off ;; ForceGoogleSafeSearch) expected=true ;; *) expected=1 ;; esac
        value=$(plutil -extract "$key" raw -o - "$policy_file" 2>/dev/null) || value=unavailable
        if [ "$value" = "$expected" ]; then verdict=PASS; elif [ "$value" = unavailable ]; then verdict=UNKNOWN; else verdict=FAIL; fi
        diagnostic_result "$verdict" "$key" "$value (expected $expected)"
      done
    done
    $found_policy || diagnostic_result UNKNOWN "$browser" 'managed policy file unavailable'
  done
  printf '%s\n' 'Confirm runtime policies in chrome://policy or edge://policy. Safari is not covered by this profile.'
}
