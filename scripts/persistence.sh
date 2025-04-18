#!/usr/bin/env bash
# persistence.sh: Setup persistence for ComfyUI data

# Source shared libraries
[ -z "$SCRIPT_DIR" ] && SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
source "$SCRIPT_DIR/logger.sh"

# Create symlinks for persistent directories
create_symlinks() {
    log_section "Setting up symlinks for persistence"
    
    # Setup basic directory symlinks
    log_debug "Setting up basic directory symlinks"
    mkdir -p "$CODE_DIR/custom_nodes"
    ln -sf "$COMFY_MANAGER_DIR" "$CODE_DIR/custom_nodes/ComfyUI-Manager"
    ln -sf "$BASE_DIR/output" "$CODE_DIR/output"
    ln -sf "$BASE_DIR/user" "$CODE_DIR/user"
    ln -sf "$BASE_DIR/input" "$CODE_DIR/input"
    
    # Model downloader symlink
    log_debug "Setting up model downloader symlink"
    if [ -e "$MODEL_DOWNLOADER_APP_DIR" ]; then
        rm -rf "$MODEL_DOWNLOADER_APP_DIR"
    fi
    ln -sf "$MODEL_DOWNLOADER_PERSISTENT_DIR" "$MODEL_DOWNLOADER_APP_DIR"
    
    # Add main models directory link for compatibility
    log_debug "Setting up models root symlink"
    ln -sf "$BASE_DIR/models" "$CODE_DIR/models_root"
    
    log_info "Basic symlinks created"
}

# Create symlinks for all model directories
create_model_symlinks() {
    log_section "Setting up model directory symlinks"
    
    local MODEL_DIRS=(
        "checkpoints" "configs" "loras" "vae" "clip" "clip_vision"
        "unet" "diffusion_models" "controlnet" "embeddings" "diffusers"
        "vae_approx" "gligen" "upscale_models" "hypernetworks"
        "photomaker" "style_models" "text_encoders"
    )
    
    for dir in "${MODEL_DIRS[@]}"; do
        ln -sf "$BASE_DIR/models/$dir" "$CODE_DIR/models/$dir"
        log_debug "Linked: $dir"
    done
    
    log_info "Model directory symlinks created"
}

# Verify symlinks are correctly setup
verify_symlinks() {
    log_section "Verifying symlinks"
    
    local failures=0
    
    # Check basic symlinks
    for link in "output" "user" "input" "models_root"; do
        if [ ! -L "$CODE_DIR/$link" ]; then
            log_error "Missing symlink: $CODE_DIR/$link"
            failures=$((failures+1))
        fi
    done
    
    # Check model directory symlinks
    for dir in "checkpoints" "loras" "vae" "controlnet"; do
        if [ ! -L "$CODE_DIR/models/$dir" ]; then
            log_error "Missing model symlink: $CODE_DIR/models/$dir"
            failures=$((failures+1))
        fi
    done
    
    # Check custom node symlinks
    if [ ! -L "$CODE_DIR/custom_nodes/ComfyUI-Manager" ]; then
        log_error "Missing ComfyUI-Manager symlink"
        failures=$((failures+1))
    fi
    
    if [ ! -L "$CODE_DIR/custom_nodes/model_downloader" ]; then
        log_error "Missing model downloader symlink"
        failures=$((failures+1))
    fi
    
    if [ $failures -eq 0 ]; then
        log_info "All symlinks verified successfully"
        return 0
    else
        log_warn "Found $failures symlink issues"
        return 1
    fi
}

# Setup all persistence
setup_persistence() {
    create_symlinks
    create_model_symlinks
    verify_symlinks
    
    log_section "Persistence setup complete"
}
