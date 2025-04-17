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
          };
        };

        # Basic Python interpreter
        python = pkgs.python312;
        
        # Comprehensive Python environment with all required dependencies
        pythonEnv = pkgs.python312.buildEnv.override {
          extraLibs = with pkgs.python312Packages; [
            # Core Python tools
            pip
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
            torchsde          # Found in nixpkgs
            transformers
            tokenizers
            sentencepiece
            safetensors
            kornia
            opencv4  # Nix equivalent of opencv-python
            
            # Additional dependencies that might be needed
            matplotlib
            jsonschema
          ];
          ignoreCollisions = true;
        };
        
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "comfy-ui";
          version = "0.1.0";
          
          src = pkgs.fetchFromGitHub {
            owner = "comfyanonymous";
            repo = "ComfyUI";
            rev = "master"; # Consider pinning to a specific commit/tag for reproducibility
            sha256 = "sha256-QTik5CjpvZsVwQtHkKVOV2D9QpwCtZcJipgPZbJGwFo=";
          };
          
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
            mkdir -p $out/bin
            mkdir -p $out/share/comfy-ui
            
            # Copy ComfyUI files
            cp -r ./* $out/share/comfy-ui/
            
            # Create a launcher script that sets up a writable environment
            cat > $out/bin/comfy-ui-launcher << EOF
#!/usr/bin/env bash
set -e

# Set up writable directories
USER_DIR="\$HOME/.config/comfy-ui"
mkdir -p "\$USER_DIR"
mkdir -p "\$USER_DIR/user"
mkdir -p "\$USER_DIR/input"
mkdir -p "\$USER_DIR/input/3d"

# Create a fresh temporary directory to work in
TMP_DIR=\$(mktemp -d)
chmod 755 "\$TMP_DIR"

# Copy ComfyUI files to the temporary directory with proper permissions
cd "$out/share/comfy-ui"
cp -r "$out/share/comfy-ui"/* "\$TMP_DIR"/

# Ensure everything in the temp directory is writable
find "\$TMP_DIR" -type d -exec chmod 755 {} \;
find "\$TMP_DIR" -type f -exec chmod 644 {} \;

# Set up input and user directories
mkdir -p "\$TMP_DIR/input"
mkdir -p "\$TMP_DIR/input/3d"
mkdir -p "\$TMP_DIR/user"

# Remove the temporary directories and create symlinks to persistent storage
rm -rf "\$TMP_DIR/user"
rm -rf "\$TMP_DIR/input"
ln -sf "\$USER_DIR/user" "\$TMP_DIR/user"
ln -sf "\$USER_DIR/input" "\$TMP_DIR/input"

# Create and activate a Python venv for additional packages
PIP_VENV="\$USER_DIR/venv"
if [ ! -d "\$PIP_VENV" ]; then
  echo "Creating virtual environment for additional packages at \$PIP_VENV"
  ${pythonEnv}/bin/python -m venv "\$PIP_VENV"
  echo "Installing required packages..."
  # Only install non-torch packages through pip to avoid version conflicts
  "\$PIP_VENV/bin/pip" install comfyui-frontend-package spandrel av
else
  # Check if packages are installed and install them if needed
  if ! "\$PIP_VENV/bin/pip" show spandrel &>/dev/null; then
    echo "Installing missing package: spandrel"
    "\$PIP_VENV/bin/pip" install spandrel
  fi
  if ! "\$PIP_VENV/bin/pip" show av &>/dev/null; then
    echo "Installing missing package: av"
    "\$PIP_VENV/bin/pip" install av
  fi
  if ! "\$PIP_VENV/bin/pip" show comfyui-frontend-package &>/dev/null; then
    echo "Installing missing package: comfyui-frontend-package"
    "\$PIP_VENV/bin/pip" install comfyui-frontend-package
  fi
fi

# Install the packages into the temporary ComfyUI directory to ensure they're found
echo "Ensuring dependencies are available in the ComfyUI environment..."
cp -r "\$PIP_VENV/lib/python3.12/site-packages/"* "\$TMP_DIR/"

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

# Run ComfyUI from the temporary directory with the venv activated
cd "\$TMP_DIR"
export PYTHONPATH="\$PIP_VENV/lib/python3.12/site-packages:\$PYTHONPATH"
echo "\033[1;32mStarting ComfyUI...\033[0m"
echo "Once the server starts, you can access ComfyUI at: http://127.0.0.1:\$COMFY_PORT"
echo "Press Ctrl+C to exit"
exec ${pythonEnv}/bin/python "\$TMP_DIR/main.py" --port "\$COMFY_PORT" "\$@"
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
