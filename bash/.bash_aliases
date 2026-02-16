if command -v xdg-open >/dev/null; then
  alias open='xdg-open'
elif command -v open >/dev/null; then
  alias open='open'
fi
