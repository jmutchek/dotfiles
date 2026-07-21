# Starship prompt (https://starship.rs)
# Config lives at ~/.config/starship.toml
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
