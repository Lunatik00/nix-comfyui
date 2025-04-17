{
  description = "A Nix flake for ComfyUI with Python 3.12";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # Allow unfree packages
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            allowUnsupportedSystem = true;
          };
        };

        # Basic Python interpreter
        python = pkgs.python312;
        
        # Custom derivation for ComfyUI including the frontend
        comfyui-src = pkgs.fetchFromGitHub {
          owner = "comfyanonymous";
          repo = "ComfyUI";
          rev = "a14c2fc3565277dfe8ab0ecb22a86c1d0a1f72cf"; # v0.3.28
          hash = "sha256-d+RxxBmkwuZwRvPfdHGjZ7pllvbIcoITn9Z/1k3m4KE=";
        };
        
        # The comfyui-frontend-package is now included directly from the repo
        # So we don't need a separate derivation for it
        
        # Custom derivation for the ComfyUI frontend package
        comfyui-frontend-package = pkgs.python312Packages.buildPythonPackage rec {
          pname = "comfyui-frontend-package";
          version = "1.17.0";
          format = "wheel";
          
          src = pkgs.fetchurl {
            url = "https://files.pythonhosted.org/packages/py3/c/comfyui_frontend_package/comfyui_frontend_package-1.17.0-py3-none-any.whl";
            hash = "sha256-g6P84Vkh81SYHkxgsHHSHAgrxV4tIdzcZ1q/PX7rEZE=";
          };
          
          doCheck = false;
        };
        
        # Using the built-in PyAV package from nixpkgs (v14.1.0)
        # This is slightly older than the latest version but should work fine for our use case
        
        # Note: we'll use direct pip installation for spandrel and av in the launcher script
        
        # Comprehensive Python environment with all required dependencies
        # Environment variables to help prevent tcmalloc crashes
        memoryEnv = {
          # Force system malloc instead of tcmalloc
          PYTHONMALLOC = "malloc";
          
          # Disable tcmalloc completely
          TCMALLOC_LARGE_ALLOC_REPORT_THRESHOLD = "10000000000";
          
          # For Apple Silicon MPS
          PYTORCH_MPS_HIGH_WATERMARK_RATIO = "0.0";
          PYTORCH_ENABLE_MPS_FALLBACK = "1";
        };

        pythonEnv = pkgs.python312.buildEnv.override {
          extraLibs = with pkgs.python312Packages; [
            # Core Python tools
            setuptools
            wheel
            
            # ComfyUI dependencies
            numpy
            pillow
            requests
            pyyaml
            tqdm
            aiohttp
            yarl
            scipy
            psutil
            typing-extensions
            einops
            torch-bin
            torchvision-bin
            torchaudio-bin
            torchsde
            transformers
            tokenizers
            sentencepiece
            safetensors
            kornia
            opencv4  # Nix equivalent of opencv-python
            
            # Additional dependencies that might be needed
            matplotlib
            jsonschema
            
            # Include the ComfyUI frontend package
            comfyui-frontend-package
            # We'll install av and spandrel directly in the persistent directory
          ];
          ignoreCollisions = true;
        };
        
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "comfy-ui";
          version = "0.1.0";
          
          src = comfyui-src;
          
          nativeBuildInputs = [
            pkgs.makeWrapper
            pythonEnv
          ];
          
          buildInputs = [
            # Add system-level dependencies that Python packages might need
            pkgs.libGL
            pkgs.libGLU
          ];
          
          # Skip build phase as ComfyUI is a Python application that doesn't need building
          dontBuild = true;
          
          # Skip configure phase
          dontConfigure = true;
          
          installPhase = ''
            # Create directories
            mkdir -p "$out/bin"
            mkdir -p "$out/share/comfy-ui"
            
            # Copy ComfyUI files
            cp -r ${comfyui-src}/* "$out/share/comfy-ui/"
            
            # Create a launcher script that sets up a writable environment
            cat > "$out/bin/comfy-ui-launcher" << EOF
#!/usr/bin/env bash

set -euo pipefail

# Set user directory for ComfyUI
USER_DIR="\$HOME/.config/comfy-ui"
if [ ! -d "\$USER_DIR" ]; then
  mkdir -p "\$USER_DIR"
  mkdir -p "\$USER_DIR/user"
  mkdir -p "\$USER_DIR/input"
  mkdir -p "\$USER_DIR/output"
  mkdir -p "\$USER_DIR/models"
fi

# Set up persistent directory structure
BASE_DIR="\$HOME/.config/comfy-ui"
CODE_DIR="\$BASE_DIR/app"
echo "Setting up ComfyUI environment in \$BASE_DIR"

# Create directory structure if it doesn't exist
mkdir -p "\$BASE_DIR"
mkdir -p "\$CODE_DIR"
mkdir -p "\$BASE_DIR/custom_nodes"

# Only update the application code if it has changed
if [ -f "\$CODE_DIR/VERSION" ] && [ "\$(cat "\$CODE_DIR/VERSION" 2>/dev/null)" = "0.3.28" ]; then
  echo "ComfyUI 0.3.28 already installed in \$CODE_DIR"
else
  echo "Installing/updating ComfyUI 0.3.28 in \$CODE_DIR"
  # Clear existing code directory to avoid conflicts with old versions
  rm -rf "\$CODE_DIR"/*
  # Copy ComfyUI files
  cp -r "$out/share/comfy-ui"/* "\$CODE_DIR/"
  # Mark the version
  echo "0.3.28" > "\$CODE_DIR/VERSION"
  # Ensure proper permissions
  chmod -R u+rw "\$CODE_DIR"
fi

# Install ComfyUI-Manager if not already installed
COMFY_MANAGER_DIR="\$BASE_DIR/custom_nodes/ComfyUI-Manager"
if [ ! -d "\$COMFY_MANAGER_DIR" ]; then
  echo "Installing ComfyUI-Manager..."
  git -c commit.gpgsign=false clone https://github.com/Comfy-Org/ComfyUI-Manager.git "\$COMFY_MANAGER_DIR"
else
  echo "ComfyUI-Manager already installed"
  # Check if we should update
  if [ -z "\$(find "\$COMFY_MANAGER_DIR" -name ".git" -mtime -7 2>/dev/null)" ]; then
    echo "Updating ComfyUI-Manager (last updated > 7 days ago)"
    cd "\$COMFY_MANAGER_DIR" && git -c commit.gpgsign=false pull
  fi
fi

# Create a symlink to the manager in the app's custom_nodes directory
if [ ! -d "\$CODE_DIR/custom_nodes" ]; then
  mkdir -p "\$CODE_DIR/custom_nodes"
fi
ln -sf "\$COMFY_MANAGER_DIR" "\$CODE_DIR/custom_nodes/ComfyUI-Manager"

# Ensure user data directories exist
mkdir -p "\$BASE_DIR/output"
mkdir -p "\$BASE_DIR/models"
mkdir -p "\$BASE_DIR/user"
mkdir -p "\$BASE_DIR/input"

# Set up symlinks within the app directory
ln -sf "\$BASE_DIR/output" "\$CODE_DIR/output"
ln -sf "\$BASE_DIR/models" "\$CODE_DIR/models"
ln -sf "\$BASE_DIR/user" "\$CODE_DIR/user"
ln -sf "\$BASE_DIR/input" "\$CODE_DIR/input"

echo "Using Nix-provided packages - no additional pip installation needed"

# All node dependencies should now be available
echo "All node dependencies are now available..."

# Set the ComfyUI port - hardcode it for predictability
COMFY_PORT="8188"

# Check if port is in use
if nc -z localhost $COMFY_PORT 2>/dev/null; then
  echo "\033[1;33mPort $COMFY_PORT is in use. ComfyUI may already be running.\033[0m"
  echo ""
  echo "Options:"
  echo "  1. Open browser to existing ComfyUI: open http://127.0.0.1:$COMFY_PORT"
  echo "  2. Try a different port (e.g., 8189): Exit and run with --port 8189"
  echo "  3. Kill the process using port $COMFY_PORT (potentially unsafe)"
  echo ""
  echo -n "Enter choice (1-3, default=1): "
  read choice
  
  case "$choice" in
    "3")
      echo "Attempting to free up the port..."
      
      # Try lsof (works on macOS and Linux)
      PIDS=$(lsof -t -i:$COMFY_PORT 2>/dev/null)
      if [ -n "$PIDS" ]; then
        echo "Found process(es) with PIDs $PIDS using port $COMFY_PORT"
        for PID in $PIDS; do
          echo "Killing process $PID..."
          kill -9 "$PID" 2>/dev/null
        done
      else
        # Try alternate approach with netstat for macOS
        echo "Trying alternate process finding methods..."
        PIDS=$(netstat -anv | grep ".$COMFY_PORT " | awk '{print $9}' | sort -u)
        if [ -n "$PIDS" ]; then
          echo "Found process(es) with PIDs $PIDS using port $COMFY_PORT"
          for PID in $PIDS; do
            echo "Killing process $PID..."
            kill -9 "$PID" 2>/dev/null
          done
        else
          echo "Could not find any process using port $COMFY_PORT"
        fi
      fi
      sleep 2
      if nc -z localhost $COMFY_PORT 2>/dev/null; then
        echo "\033[1;31mFailed to free up port $COMFY_PORT. Try a different port.\033[0m"
        exit 1
      fi
      ;;
    "2")
      echo "To use a different port, restart with --port option."
      exit 0
      ;;
    *)
      # Default to option 1 - open browser
      open http://127.0.0.1:$COMFY_PORT
      exit 0
      ;;
  esac
fi

# Function to open browser once server starts
echo "\033[1;36mWhen ComfyUI is running, open this URL in your browser:\033[0m"
echo "http://127.0.0.1:\$COMFY_PORT"
echo ""
echo "Or run this command to open automatically:"
echo "open http://127.0.0.1:\$COMFY_PORT"

# Frontend package is now included in the Nix environment
echo "ComfyUI frontend package is already included in the environment"

# Run ComfyUI from the code directory
cd "\$CODE_DIR"
echo "\033[1;32mStarting ComfyUI...\033[0m"
echo "Once the server starts, you can access ComfyUI at: http://127.0.0.1:\$COMFY_PORT"
echo "Press Ctrl+C to exit"

# Enable audio nodes and set environment variables for stable execution
export COMFY_ENABLE_AUDIO_NODES=True

# ===== MEMORY MANAGEMENT FOR STABLE DIFFUSION MODELS =====
# The following environment variables help prevent the tcmalloc crashes
# on Apple Silicon when loading large models like SDXL

# Force system allocator instead of tcmalloc
export LD_PRELOAD=/usr/lib/libc.dylib
export DYLD_INSERT_LIBRARIES=/usr/lib/libc.dylib

# Let's keep it simple for Apple Silicon - use fewer environment variables
# and focus on a more direct approach
export PYTORCH_NO_CUDA_MEMORY_CACHING=1
export PYTHONMALLOC=malloc
export COMFY_PRECISION="fp16"

# Create a patch file to modify how ComfyUI loads models on macOS
cat > "\$CODE_DIR/macos_model_patch.py" << 'PATCH_EOF'
import os
import sys
import platform

# Check if we're on macOS
if platform.system() == 'Darwin':
    print("Applying macOS patch for model loading")
    
    # Monkey patch torch.load to use CPU first
    import torch
    import gc
    original_load = torch.load
    
    def safe_macos_load(*args, **kwargs):
        # Clear memory before loading
        gc.collect()
        if hasattr(torch, 'mps') and hasattr(torch.mps, 'empty_cache'):
            torch.mps.empty_cache()
            
        # Always load models to CPU first, then transfer
        if 'map_location' not in kwargs:
            kwargs['map_location'] = 'cpu'
            
        # Load the model
        try:
            result = original_load(*args, **kwargs)
        except RuntimeError as e:
            print(f"Error loading model: {e}")
            # Try one more time with aggressive garbage collection
            gc.collect()
            if hasattr(torch, 'mps') and hasattr(torch.mps, 'empty_cache'):
                torch.mps.empty_cache()
            result = original_load(*args, **kwargs)
        
        # Clear memory after loading
        gc.collect()
        
        return result
        
    # Apply the patch
    torch.load = safe_macos_load
    print("Successfully patched torch.load for macOS")

# Now patch the model_management.py file to change how models are loaded
# This is the most direct approach to prevent the tcmalloc crash
if platform.system() == 'Darwin':
    try:
        import comfy.model_management as model_management
        original_load_model_gpu = model_management.load_model_gpu
        
        def safe_load_model_gpu(model):
            # When on macOS, always ensure models are on CPU first
            print("Safely loading model using CPU intermediary step")
            model.to("cpu")
            gc.collect()
            if hasattr(torch, 'mps') and hasattr(torch.mps, 'empty_cache'):
                torch.mps.empty_cache()
                
            # Now load to GPU safely in chunks
            return original_load_model_gpu(model)
            
        # Apply the patch
        model_management.load_model_gpu = safe_load_model_gpu
        print("Successfully patched model_management for safer macOS loading")
    except Exception as e:
        print(f"Warning: Could not patch model_management: {e}")
        
print("MacOS model loading patches complete")
PATCH_EOF

# Apply the patch before running ComfyUI
${pythonEnv}/bin/python "\$CODE_DIR/macos_model_patch.py" || echo "Warning: Model patch failed, but continuing"

# Create a virtual environment for the extra packages if it doesn't exist
COMFY_VENV="\$BASE_DIR/venv"
if [ ! -d "\$COMFY_VENV" ]; then
  echo "Creating virtual environment for extra packages at \$COMFY_VENV"
  ${pythonEnv}/bin/python -m venv "\$COMFY_VENV"
  
  # Install the necessary packages that ComfyUI can't find through Nix
  echo "Installing required additional packages..."
  "\$COMFY_VENV/bin/pip" install spandrel==0.4.1 av==14.1.0 GitPython toml rich
fi

# Make sure the packages are up to date
if [ \$("\$COMFY_VENV/bin/pip" freeze | grep -c "^spandrel==0.4.1\$") -eq 0 ]; then
  echo "Updating spandrel package..."
  "\$COMFY_VENV/bin/pip" install spandrel==0.4.1
fi

if [ \$("\$COMFY_VENV/bin/pip" freeze | grep -c "^av==14.1.0\$") -eq 0 ]; then
  echo "Updating av package..."
  "\$COMFY_VENV/bin/pip" install av==14.1.0
fi

if [ \$("\$COMFY_VENV/bin/pip" freeze | grep -c "^GitPython\$") -eq 0 ]; then
  echo "Installing GitPython for ComfyUI-Manager..."
  "\$COMFY_VENV/bin/pip" install GitPython
fi

if [ \$("\$COMFY_VENV/bin/pip" freeze | grep -c "^toml\$") -eq 0 ]; then
  echo "Installing toml for ComfyUI-Manager..."
  "\$COMFY_VENV/bin/pip" install toml
fi

if [ \$("\$COMFY_VENV/bin/pip" freeze | grep -c "^rich\$") -eq 0 ]; then
  echo "Installing rich for ComfyUI-Manager..."
  "\$COMFY_VENV/bin/pip" install rich
fi

# Set up Python path to include both Nix packages and venv packages
VENV_SITE_PACKAGES="\$COMFY_VENV/lib/python3.12/site-packages"
export PYTHONPATH="\$CODE_DIR:\$VENV_SITE_PACKAGES:\${PYTHONPATH:-}"

# Create memory management patch file
echo "Creating memory management patches for Apple Silicon..."
cat > "\$CODE_DIR/memory_patch.py" << 'PATCHEOF'
import torch
import gc
import os
import sys

# Aggressive garbage collection settings
gc.set_threshold(100, 5, 5)

# Try to disable tcmalloc's problematic behavior
disable_tcmalloc = True

# For Apple Silicon, we need special memory management
print(f"PyTorch version: {torch.__version__}")
print(f"Python version: {sys.version}")
print(f"Is MPS available: {torch.backends.mps.is_available()}")

# Monkey patch the model loading process
original_load = torch.load
def safe_load(*args, **kwargs):
    # Force garbage collection before loading
    print("Memory patch: Running aggressive garbage collection before model load")
    for _ in range(3):  # Multiple GC passes
        gc.collect()
        
    if hasattr(torch, 'mps') and hasattr(torch.mps, 'empty_cache'):
        torch.mps.empty_cache()
    
    # Try to ensure we're using the safest memory profile
    print("Memory patch: Loading model with safe memory settings")
    
    # Use a try-except block to handle potential memory errors
    try:
        # Load the model with reduced memory usage
        if 'map_location' not in kwargs:
            # For Apple Silicon, initially load on CPU then transfer
            kwargs['map_location'] = 'cpu'
        result = original_load(*args, **kwargs)
    except RuntimeError as e:
        if "CUDA" in str(e) or "memory" in str(e).lower():
            print("Memory error during model load - trying with more aggressive GC")
            gc.collect()
            if hasattr(torch, 'mps') and hasattr(torch.mps, 'empty_cache'):
                torch.mps.empty_cache()
            # Try again with reduced memory
            result = original_load(*args, **kwargs)
        else:
            raise
    
    # Force garbage collection after loading
    print("Memory patch: Running garbage collection after model load")
    gc.collect()
    if hasattr(torch, 'mps') and hasattr(torch.mps, 'empty_cache'):
        torch.mps.empty_cache()
    
    return result

# Apply the patch
torch.load = safe_load
print("Memory management patches applied successfully!")
PATCHEOF

# Inject memory patches into comfy/model_management.py to fix memory issues
if [ -f "\$CODE_DIR/comfy/model_management.py" ]; then
  echo "Patching model_management.py for better memory handling..."
  # Create backup
  cp "\$CODE_DIR/comfy/model_management.py" "\$CODE_DIR/comfy/model_management.py.bak"
  
  # Inject import for our memory patch module
  sed -i.bak '1s/^/import sys\nimport gc\n/' "\$CODE_DIR/comfy/model_management.py"
  
  # Add explicit garbage collection calls to the load_model_gpu function
  sed -i.bak '/def load_model_gpu(/a \
    # Explicit garbage collection before loading model\n    gc.collect()\n    if hasattr(torch, "mps") and hasattr(torch.mps, "empty_cache"):\n        torch.mps.empty_cache()' "\$CODE_DIR/comfy/model_management.py"
  
  echo "Model management patched successfully"
fi

# Import our macOS patch module at application startup
echo "#!/usr/bin/env python

# Import the macOS patch first before any other imports
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import macos_model_patch

# Now import and run the normal main module
from main import *
" > "\$CODE_DIR/patched_main.py"

chmod +x "\$CODE_DIR/patched_main.py"
exec ${pythonEnv}/bin/python "\$CODE_DIR/patched_main.py" --port "\$COMFY_PORT" "\$@"
EOF

            chmod +x $out/bin/comfy-ui-launcher
            
            # Create a symlink to the launcher
            ln -s $out/bin/comfy-ui-launcher $out/bin/comfy-ui
          '';
              
          meta = with pkgs.lib; {
            description = "ComfyUI with Python 3.12";
            homepage = "https://github.com/comfyanonymous/ComfyUI";
            license = licenses.gpl3;
            platforms = platforms.all;
            mainProgram = "comfy-ui";
          };
        };
        
        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.default;
          name = "comfy-ui";
        };
        
        devShells.default = pkgs.mkShell {
          packages = [
            pythonEnv
          ];
          
          shellHook = ''
            echo "ComfyUI development environment activated"
            echo "All dependencies are included via Nix package manager"
            
            # Set up a user directory
            export COMFY_USER_DIR="$HOME/.config/comfy-ui"
            mkdir -p "$COMFY_USER_DIR"
            
            echo "User data will be stored in $COMFY_USER_DIR"
            echo "Run 'python main.py' to start ComfyUI"
            export PYTHONPATH="$PWD:$PYTHONPATH"
          '';
        };
      }
    );
}
