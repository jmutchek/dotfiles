# GitHub Copilot in Container (ghcp)
# Runs copilot CLI in a sandboxed podman container

ghcp() {
    local container_name="copilot-sandbox"
    local container_dir="$HOME/.local/containers/copilot"
    
    # Check if image exists, build if not
    if ! podman image exists "$container_name" 2>/dev/null; then
        echo "Building $container_name image..." >&2
        podman build -t "$container_name" -f "$container_dir/Containerfile" "$container_dir" || return 1
    fi
    
    # Run container with current directory mounted
    podman run -it --rm \
        -v "$PWD:/workspace:Z" \
        -e GH_TOKEN="$(gh auth token 2>/dev/null)" \
        "$container_name" \
        "$@"
}
