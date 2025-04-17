#!/usr/bin/env bash
set -euo pipefail

# Config
COMFY_VERSION="0.3.28"
COMFY_PORT="8188"
BASE_DIR="$HOME/.config/comfy-ui"
CODE_DIR="$BASE_DIR/app"
COMFY_VENV="$BASE_DIR/venv"
COMFY_MANAGER_DIR="$BASE_DIR/custom_nodes/ComfyUI-Manager"

# Create directory structure
mkdir -p "$BASE_DIR" "$CODE_DIR" "$BASE_DIR/custom_nodes"
mkdir -p "$BASE_DIR/output" "$BASE_DIR/models" "$BASE_DIR/user" "$BASE_DIR/input"

# Always create a fresh installation to ensure we have write permissions
echo "Installing ComfyUI $COMFY_VERSION in $CODE_DIR"
# Remove the existing directory completely
rm -rf "$CODE_DIR"
# Recreate it
mkdir -p "$CODE_DIR"
# Copy the ComfyUI source
cp -r "@comfyuiSrc@"/* "$CODE_DIR/"
echo "$COMFY_VERSION" > "$CODE_DIR/VERSION"
chmod -R u+rw "$CODE_DIR"

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
ln -sf "$BASE_DIR/models" "$CODE_DIR/models"
ln -sf "$BASE_DIR/user" "$CODE_DIR/user"
ln -sf "$BASE_DIR/input" "$CODE_DIR/input"

# Apply model downloader patch
echo "Applying model downloader patches..."
# Copy the backend patch
cp "@modelDownloaderPatch@" "$CODE_DIR/model_downloader_patch.py"

# Find the frontend package directory in the Python site-packages
FRONTEND_PACKAGE_DIR="$COMFY_VENV/lib/python3.12/site-packages/comfyui_frontend_package"

# Create a custom node that will inject our frontend patch
CUSTOM_NODE_DIR="$CODE_DIR/custom_nodes"
mkdir -p "$CUSTOM_NODE_DIR/model_downloader/js"

# Copy the frontend patch to the custom node directory
cp "@frontendPatch@" "$CUSTOM_NODE_DIR/model_downloader/js/backend_download.js"

# Copy the model downloader patch to the custom node directory
cp "@modelDownloaderPatch@" "$CUSTOM_NODE_DIR/model_downloader/model_downloader_patch.py"

# Create a simple __init__.py file for the custom node
cat > "$CUSTOM_NODE_DIR/model_downloader/__init__.py" << 'EOL'
# Model Downloader Custom Node
import os
import sys
import requests
import json
import logging
import traceback
from pathlib import Path
import folder_paths
from aiohttp import web
from server import PromptServer

# This node doesn't add any actual nodes to the graph
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

# Register the web extension
WEB_DIRECTORY = os.path.join(os.path.dirname(os.path.realpath(__file__)), "js")

# Define the download model endpoint
async def download_model(request):
    """
    Handle POST requests to download models
    """
    try:
        data = await request.json()
        url = data.get('url')
        folder = data.get('folder')
        filename = data.get('filename')
        
        print(f"[MODEL_DOWNLOADER] Received download request for {filename} in folder {folder} from {url}")
        
        if not url or not folder or not filename:
            print(f"[MODEL_DOWNLOADER] Missing required parameters: url={url}, folder={folder}, filename={filename}")
            return web.json_response({"success": False, "error": "Missing required parameters"})
        
        # Get the model folder path
        folder_path = folder_paths.get_folder_paths(folder)
        
        if not folder_path:
            print(f"[MODEL_DOWNLOADER] Invalid folder: {folder}")
            return web.json_response({"success": False, "error": f"Invalid folder: {folder}"})
        
        # Create the full path for the file
        full_path = os.path.join(folder_path[0], filename)
        
        print(f"[MODEL_DOWNLOADER] Downloading model to {full_path}")
        
        # Download the file
        try:
            # Create the directory if it doesn't exist
            os.makedirs(os.path.dirname(full_path), exist_ok=True)
            
            # Download the file
            with requests.get(url, stream=True) as r:
                r.raise_for_status()
                total_size = int(r.headers.get('content-length', 0))
                downloaded = 0
                with open(full_path, 'wb') as f:
                    for chunk in r.iter_content(chunk_size=8192):
                        if chunk:
                            f.write(chunk)
                            downloaded += len(chunk)
                            if total_size > 0 and downloaded % (1024 * 1024 * 10) == 0:  # Report every 10MB
                                print(f"[MODEL_DOWNLOADER] Downloaded {downloaded / (1024 * 1024):.2f} MB of {total_size / (1024 * 1024):.2f} MB ({(downloaded / total_size) * 100:.2f}%)")
            
            print(f"[MODEL_DOWNLOADER] Model downloaded successfully to {full_path}")
            return web.json_response({"success": True, "path": full_path})
        except Exception as e:
            print(f"[MODEL_DOWNLOADER] Error downloading file: {e}")
            return web.json_response({"success": False, "error": str(e)})
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"[MODEL_DOWNLOADER] Error downloading model: {str(e)}")
        print(f"[MODEL_DOWNLOADER] Error details: {error_details}")
        return web.json_response({"success": False, "error": str(e)})

# Register the API endpoint when the server starts
try:
    app = PromptServer.instance.app
    app.router.add_post('/api/download-model', download_model)
    print("[MODEL_DOWNLOADER] API endpoint registered at /api/download-model")
except Exception as e:
    print(f"[MODEL_DOWNLOADER] Error registering API endpoint: {e}")
    traceback.print_exc()

print(f"Model Downloader patch loaded successfully from {WEB_DIRECTORY}")
EOL

# Create a simple model_downloader.js file that loads our patch
cat > "$CUSTOM_NODE_DIR/model_downloader/js/model_downloader.js" << 'EOL'
import './backend_download.js';
console.log("[MODEL_DOWNLOADER] Loading model downloader extension...");

function registerModelDownloader() {
    console.log("[MODEL_DOWNLOADER] Model downloader extension initialized");
}

registerModelDownloader();
EOL

# Create a proper web_extensions.json file
cat > "$CUSTOM_NODE_DIR/model_downloader/web_extensions.json" << 'WEB_EXTENSIONS_EOF'
{
  "javascript": [
    "js/model_downloader.js"
  ]
}
WEB_EXTENSIONS_EOF

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

# Modify main.py to import our patch
if ! grep -q "import model_downloader_patch" "$CODE_DIR/main.py"; then
  echo -e "\n# Import model downloader patch\nimport model_downloader_patch" >> "$CODE_DIR/main.py"
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
echo -e "\033[1;36mWhen ComfyUI is running, open this URL in your browser:\033[0m"
echo "http://127.0.0.1:$COMFY_PORT"
echo -e "\nOr run this command to open automatically:\nopen http://127.0.0.1:$COMFY_PORT"

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

# Start ComfyUI
cd "$CODE_DIR"
echo -e "\033[1;32mStarting ComfyUI...\033[0m"
echo "Once the server starts, you can access ComfyUI at: http://127.0.0.1:$COMFY_PORT"
echo "Press Ctrl+C to exit"
exec "$COMFY_VENV/bin/python" "$CODE_DIR/main.py" --port "$COMFY_PORT" --force-fp16 "$@"
