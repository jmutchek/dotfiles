mdview() {
  local md="$1"
  local css="$2"
  local tmp
  tmp="$(mktemp --suffix=.html)"

  if [ -n "$css" ]; then
    pandoc "$md" -s --css "$css" -o "$tmp"
  else
    pandoc "$md" -s -o "$tmp"
  fi

  if grep -qi microsoft /proc/version 2>/dev/null; then
    if command -v wslview >/dev/null 2>&1; then
      wslview "$tmp" >/dev/null 2>&1 &
    else
      cmd.exe /c start "" "$(wslpath -w "$tmp")" >/dev/null 2>&1 &
    fi
  else
    xdg-open "$tmp" >/dev/null 2>&1 &
  fi
}
