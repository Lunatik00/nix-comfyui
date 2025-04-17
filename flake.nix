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

# Create symbolic links for writable directories
cd "$out/share/comfy-ui"
TMP_DIR=\$(mktemp -d)
cp -r "$out/share/comfy-ui"/* "\$TMP_DIR"/
rm -rf "\$TMP_DIR/user" || true
rm -rf "\$TMP_DIR/input" || true

# Link user data directories
ln -sf "\$USER_DIR/user" "\$TMP_DIR/user"
ln -sf "\$USER_DIR/input" "\$TMP_DIR/input"

# Create input directories that need to be writable
mkdir -p "\$TMP_DIR/input/3d"

# Create and activate a Python venv for additional packages
PIP_VENV="\$USER_DIR/venv"
if [ ! -d "\$PIP_VENV" ]; then
  echo "Creating virtual environment for additional packages at \$PIP_VENV"
  ${pythonEnv}/bin/python -m venv "\$PIP_VENV"
  echo "Installing required packages..."
  "\$PIP_VENV/bin/pip" install comfyui-frontend-package spandrel av torchvision torch torchaudio
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
fi

# Install the packages into the temporary ComfyUI directory to ensure they're found
echo "Ensuring dependencies are available in the ComfyUI environment..."
cp -r "\$PIP_VENV/lib/python3.12/site-packages/"* "\$TMP_DIR/"

# Check if port 8188 is already in use
if nc -z localhost 8188 2>/dev/null; then
  echo "\033[1;33mPort 8188 is already in use!\033[0m"
  echo "ComfyUI is likely already running. If you want to start a new instance, try:"
  echo "  1. Check if ComfyUI is already running at http://127.0.0.1:8188"
  echo "  2. Stop any running ComfyUI instances"
  echo "  3. Run this command again"
  echo ""
  echo "Would you like to open ComfyUI in your browser? (assuming it's running)"
  read -p "[Y/n]: " response
  if [[ "\$response" != "n" && "\$response" != "N" ]]; then
    open http://127.0.0.1:8188
  fi
  exit 0
fi

# Run ComfyUI from the temporary directory with the venv activated
cd "\$TMP_DIR"
export PYTHONPATH="\$PIP_VENV/lib/python3.12/site-packages:\$PYTHONPATH"
echo "\033[1;32mStarting ComfyUI...\033[0m"
echo "Once the server starts, you can access ComfyUI at: http://127.0.0.1:8188"
echo "Press Ctrl+C to exit"
exec ${pythonEnv}/bin/python "\$TMP_DIR/main.py" "\$@"
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
