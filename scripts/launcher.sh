#!/usr/bin/env bash
set -euo pipefail

# Config
COMFY_VERSION="0.3.28"
COMFY_PORT="8188"
BASE_DIR="$HOME/.config/comfy-ui"
CODE_DIR="$BASE_DIR/app"
COMFY_VENV="$BASE_DIR/venv"
COMFY_MANAGER_DIR="$BASE_DIR/custom_nodes/ComfyUI-Manager"
OPEN_BROWSER=false

# Create directory structure with all required persistent directories
mkdir -p "$BASE_DIR" "$CODE_DIR" "$BASE_DIR/custom_nodes"

# Create main persistent directories
mkdir -p "$BASE_DIR/output" "$BASE_DIR/user" "$BASE_DIR/input"
mkdir -p "$BASE_DIR/user/workflows" "$BASE_DIR/user/default" "$BASE_DIR/user/extra"

# Create model directory structure in the persistent location
mkdir -p "$BASE_DIR/models/checkpoints" "$BASE_DIR/models/configs" "$BASE_DIR/models/loras"
mkdir -p "$BASE_DIR/models/vae" "$BASE_DIR/models/clip" "$BASE_DIR/models/clip_vision"
mkdir -p "$BASE_DIR/models/unet" "$BASE_DIR/models/diffusion_models" "$BASE_DIR/models/controlnet"
mkdir -p "$BASE_DIR/models/embeddings" "$BASE_DIR/models/diffusers" "$BASE_DIR/models/vae_approx"
mkdir -p "$BASE_DIR/models/gligen" "$BASE_DIR/models/upscale_models" "$BASE_DIR/models/hypernetworks"
mkdir -p "$BASE_DIR/models/photomaker" "$BASE_DIR/models/style_models" "$BASE_DIR/models/text_encoders"

# Create specific directories for image inputs if they don't exist
mkdir -p "$BASE_DIR/input/img" "$BASE_DIR/input/video" "$BASE_DIR/input/mask"

# Always create a fresh installation to ensure we have write permissions
echo "Installing ComfyUI $COMFY_VERSION in $CODE_DIR"
# Remove the existing directory completely (but keep symlinked content safe)
rm -rf "$CODE_DIR"
# Recreate it
mkdir -p "$CODE_DIR"
# Copy the ComfyUI source
cp -r "@comfyuiSrc@"/* "$CODE_DIR/"
echo "$COMFY_VERSION" > "$CODE_DIR/VERSION"

# Copy our persistence scripts
cp -f "@persistenceMainScript@" "$CODE_DIR/persistent_main.py" 2>/dev/null || true

chmod -R u+rw "$CODE_DIR"

# Ensure model directories exist in the CODE_DIR for symlinks
mkdir -p "$CODE_DIR/models"

# Install/update ComfyUI-Manager
if [ ! -d "$COMFY_MANAGER_DIR" ]; then
  echo "Installing ComfyUI-Manager..."
  git -c commit.gpgsign=false clone https://github.com/Comfy-Org/ComfyUI-Manager.git "$COMFY_MANAGER_DIR"
elif [ -z "$(find "$COMFY_MANAGER_DIR" -name ".git" -mtime -7 2>/dev/null)" ]; then
  echo "Updating ComfyUI-Manager (last updated > 7 days ago)"
  cd "$COMFY_MANAGER_DIR" && git -c commit.gpgsign=false pull
fi

# Setup symlinks
mkdir -p "$CODE_DIR/custom_nodes"
ln -sf "$COMFY_MANAGER_DIR" "$CODE_DIR/custom_nodes/ComfyUI-Manager"
ln -sf "$BASE_DIR/output" "$CODE_DIR/output"
ln -sf "$BASE_DIR/user" "$CODE_DIR/user"
ln -sf "$BASE_DIR/input" "$CODE_DIR/input"

# Link each model subdirectory properly
# This ensures models are stored in the persistent location
ln -sf "$BASE_DIR/models/checkpoints" "$CODE_DIR/models/checkpoints"
ln -sf "$BASE_DIR/models/configs" "$CODE_DIR/models/configs"
ln -sf "$BASE_DIR/models/loras" "$CODE_DIR/models/loras"
ln -sf "$BASE_DIR/models/vae" "$CODE_DIR/models/vae"
ln -sf "$BASE_DIR/models/clip" "$CODE_DIR/models/clip"
ln -sf "$BASE_DIR/models/clip_vision" "$CODE_DIR/models/clip_vision"
ln -sf "$BASE_DIR/models/unet" "$CODE_DIR/models/unet"
ln -sf "$BASE_DIR/models/diffusion_models" "$CODE_DIR/models/diffusion_models"
ln -sf "$BASE_DIR/models/controlnet" "$CODE_DIR/models/controlnet"
ln -sf "$BASE_DIR/models/embeddings" "$CODE_DIR/models/embeddings"
ln -sf "$BASE_DIR/models/diffusers" "$CODE_DIR/models/diffusers"
ln -sf "$BASE_DIR/models/vae_approx" "$CODE_DIR/models/vae_approx"
ln -sf "$BASE_DIR/models/gligen" "$CODE_DIR/models/gligen"
ln -sf "$BASE_DIR/models/upscale_models" "$CODE_DIR/models/upscale_models"
ln -sf "$BASE_DIR/models/hypernetworks" "$CODE_DIR/models/hypernetworks"
ln -sf "$BASE_DIR/models/photomaker" "$CODE_DIR/models/photomaker"
ln -sf "$BASE_DIR/models/style_models" "$CODE_DIR/models/style_models"
ln -sf "$BASE_DIR/models/text_encoders" "$CODE_DIR/models/text_encoders"

# Also add main models directory link for compatibility
ln -sf "$BASE_DIR/models" "$CODE_DIR/models_root"

# Apply model downloader patch
echo "Applying model downloader patches..."

# Create the custom node directory
CUSTOM_NODE_DIR="$CODE_DIR/custom_nodes"
mkdir -p "$CUSTOM_NODE_DIR/model_downloader/js"

# Copy the model downloader custom node files
cp -r "@modelDownloaderDir@"/* "$CUSTOM_NODE_DIR/model_downloader/"

# Copy the model downloader patch to the main directory for import
cp "$CUSTOM_NODE_DIR/model_downloader/model_downloader_patch.py" "$CODE_DIR/model_downloader_patch.py"

# No need to create model_downloader.js or web_extensions.json as they are copied from the custom_nodes directory

# Setup virtual environment if needed
if [ ! -d "$COMFY_VENV" ]; then
  echo "Creating virtual environment for ComfyUI at $COMFY_VENV"
  "@pythonEnv@/bin/python" -m venv "$COMFY_VENV"
  
  # Install dependencies
  "$COMFY_VENV/bin/pip" install --upgrade pip
  "$COMFY_VENV/bin/pip" install pyyaml pillow numpy
  "$COMFY_VENV/bin/pip" install -r "$CODE_DIR/requirements.txt"
  "$COMFY_VENV/bin/pip" install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cpu
  "$COMFY_VENV/bin/pip" install spandrel av GitPython toml rich safetensors
  
  # Install requests for our model downloader
  "$COMFY_VENV/bin/pip" install requests
fi

# We use persistent.py for path management, no need for the path_override custom node
# Copy our persistence scripts to ensure directory paths are persistent
cp -f "@persistenceScript@" "$CODE_DIR/persistent.py" 2>/dev/null || true
cp -f "@persistenceMainScript@" "$CODE_DIR/persistent_main.py" 2>/dev/null || true
chmod +x "$CODE_DIR/persistent.py"
chmod +x "$CODE_DIR/persistent_main.py"

# Create a more direct approach to inject our frontend patch
# First, let's find where the frontend package is installed
FRONTEND_PATH="$(find "$COMFY_VENV" -path "*/site-packages/comfyui_frontend_package/static" -type d 2>/dev/null)"
echo "[MODEL_DOWNLOADER] Frontend package path: $FRONTEND_PATH"

# Find the frontend package path for debugging purposes only
if [ -n "$FRONTEND_PATH" ]; then
  echo "[MODEL_DOWNLOADER] Found frontend package at: $FRONTEND_PATH"
  echo "[MODEL_DOWNLOADER] Note: This is a read-only directory managed by Nix"
else
  echo "[MODEL_DOWNLOADER] WARNING: Could not find frontend package path"
fi

# Instead of modifying the frontend package directly, we'll use a custom node approach
# The custom_nodes directory is already set up earlier in the script
echo "[MODEL_DOWNLOADER] Using custom node approach for frontend integration"

# Add a debug message to check the custom node installation
echo "[MODEL_DOWNLOADER] Custom node installed at $CUSTOM_NODE_DIR"

# Modify main.py to import our patches
if ! grep -q "import model_downloader_patch" "$CODE_DIR/main.py"; then
  echo -e "\n# Import model downloader patch
import model_downloader_patch" >> "$CODE_DIR/main.py"
  echo "Added model downloader patch import to main.py"
fi

# Check if port is in use
if nc -z localhost $COMFY_PORT 2>/dev/null; then
  echo -e "\033[1;33mPort $COMFY_PORT is in use. ComfyUI may already be running.\033[0m"
  echo -e "Options:\n  1. Open browser to existing ComfyUI\n  2. Try a different port\n  3. Kill the process using port $COMFY_PORT"
  echo -n "Enter choice (1-3, default=1): "
  read choice
  
  case "$choice" in
    "3")
      echo "Attempting to free up the port..."
      PIDS=$(lsof -t -i:$COMFY_PORT 2>/dev/null || netstat -anv | grep ".$COMFY_PORT " | awk '{print $9}' | sort -u)
      if [ -n "$PIDS" ]; then
        for PID in $PIDS; do kill -9 "$PID" 2>/dev/null; done
        sleep 2
        if nc -z localhost $COMFY_PORT 2>/dev/null; then
          echo -e "\033[1;31mFailed to free up port $COMFY_PORT. Try a different port.\033[0m"
          exit 1
        fi
      else
        echo "Could not find any process using port $COMFY_PORT"
      fi
      ;;
    "2")
      echo "To use a different port, restart with --port option."
      exit 0
      ;;
    *)
      open http://127.0.0.1:$COMFY_PORT
      exit 0
      ;;
  esac
fi

# Display URL info
echo -e "\n-------------------------------------------"
echo -e "ComfyUI URL: http://127.0.0.1:$COMFY_PORT"
echo -e "-------------------------------------------"
echo -e "\033[1;33mNOTE:\033[0m First time startup may take several minutes while dependencies are downloaded."
echo -e "\033[1;33mNOTE:\033[0m Models will be downloaded automatically when selected in the UI."
echo -e "\nTo open manually: open http://127.0.0.1:$COMFY_PORT"

# Setup ComfyUI-Manager in code directory if needed
if [ ! -f "$CODE_DIR/custom_nodes/ComfyUI-Manager" ] && [ ! -L "$CODE_DIR/custom_nodes/ComfyUI-Manager" ]; then
  mkdir -p "$CODE_DIR/custom_nodes"
  git -c commit.gpgsign=false clone https://github.com/ltdrdata/ComfyUI-Manager "$CODE_DIR/custom_nodes/ComfyUI-Manager"
  "$COMFY_VENV/bin/pip" install -r "$CODE_DIR/custom_nodes/ComfyUI-Manager/requirements.txt"
fi

# Create ComfyUI-Manager config
mkdir -p "$CODE_DIR/user/default/ComfyUI-Manager"
cat > "$CODE_DIR/user/default/ComfyUI-Manager/config.ini" << 'CONFIG_EOF'
[default]
config_version=0.7
[manager]
control_net_model_dir=\models\controlnet
upscale_model_dir=\models\upscale_models
lora_model_dir=\models\loras
vae_model_dir=\models\vae
gligen_model_dir=\models\gligen
checkpoint_dir=\models\checkpoints
custom_nodes_dir=custom_nodes
clip_vision_dir=\models\clip_vision
embedding_dir=\models\embeddings
loras_dir=\models\loras
prevent_direct_install=True
privileged_hosting=False
CONFIG_EOF

# Set environment variables
export COMFY_ENABLE_AUDIO_NODES=True
export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
export COMFY_PRECISION="fp16"
export PYTHONPATH="$CODE_DIR:${PYTHONPATH:-}"

# Set ComfyUI variables to ensure it uses our persistent directories
export COMFY_USER_DIR="$BASE_DIR"

# Explicitly point to the user directory where workflows are saved
export COMFY_SAVE_PATH="$BASE_DIR/user"

# We use persistent.py for path management, no need for the path_override custom node

# Parse arguments for our launcher
ARGS=()
for arg in "$@"; do
  case "$arg" in
    "--open")
      OPEN_BROWSER=true
      ;;
    *)
      ARGS+=("$arg")
      ;;
  esac
done

# For debugging
# echo "Open Browser: $OPEN_BROWSER"
# echo "Passing args: ${ARGS[*]}"

# Start ComfyUI
cd "$CODE_DIR"
echo "Starting ComfyUI..."
echo "Press Ctrl+C to exit"

# Handle browser opening
if [ "$OPEN_BROWSER" = true ]; then
  # Set up a trap to kill the child process when this script receives a signal
  trap 'kill $PID 2>/dev/null' INT TERM
  
  # Start ComfyUI in the background using our persistent_main.py wrapper
  "$COMFY_VENV/bin/python" "$CODE_DIR/persistent_main.py" --port "$COMFY_PORT" --force-fp16 "${ARGS[@]}" &
  PID=$!
  
  # Wait for server to start
  echo "Waiting for ComfyUI to start..."
  until nc -z localhost $COMFY_PORT 2>/dev/null; do
    sleep 1
    # Check if process is still running
    if ! kill -0 $PID 2>/dev/null; then
      echo "ComfyUI process exited unexpectedly"
      exit 1
    fi
  done
  
  echo "ComfyUI started! Opening browser..."
  open "http://127.0.0.1:$COMFY_PORT"
  
  # Instead of just waiting, we use a loop that can be interrupted
  while kill -0 $PID 2>/dev/null; do
    wait $PID 2>/dev/null || break
  done
  
  # Make sure to clean up any remaining process
  kill $PID 2>/dev/null || true
  exit 0
else
  # Start ComfyUI normally using our persistent_main.py wrapper
  # This will run the persistence setup once before starting ComfyUI
  exec "$COMFY_VENV/bin/python" "$CODE_DIR/persistent_main.py" --port "$COMFY_PORT" --force-fp16 "${ARGS[@]}"
fi
