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

  xdg-open "$tmp" >/dev/null 2>&1 &
}
