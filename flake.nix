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
        
        # Custom derivations for the additional packages we need
        comfyui-frontend-package = pkgs.python312Packages.buildPythonPackage rec {
          pname = "comfyui-frontend-package";
          version = "1.17.0";
          format = "wheel";
          
          src = pkgs.fetchPypi {
            inherit pname version format;
            python = "py3";
            platform = "any";
            hash = "sha256-mKZXIaAA5Io09HdJvNCCF9H60NL4RlSWvVBj6rxQIzA=";
          };
          
          propagatedBuildInputs = with pkgs.python312Packages; [
            # Avoid torch dependencies to prevent version conflicts
          ];
          
          doCheck = false;
        };
        
        # PyAV package for audio/video processing
        python-av = pkgs.python312Packages.buildPythonPackage rec {
          pname = "av";
          version = "14.3.0";
          format = "setuptools";
          
          src = pkgs.fetchPypi {
            inherit pname version;
            hash = "sha256-XN7NitZwLFUg/O0MLlYAR7fZ+I/2e5WKq/rxV+C4uOY=";
          };
          
          nativeBuildInputs = [
            pkgs.pkg-config
          ];
          
          buildInputs = [
            pkgs.ffmpeg
          ];
          
          propagatedBuildInputs = with pkgs.python312Packages; [
            numpy
          ];
          
          # Disable tests that require internet access
          doCheck = false;
          
          # Patch to work with newer FFmpeg versions
          postPatch = ''
            substituteInPlace setup.py \
              --replace 'ffmpeg_version = "55.110.100"' 'ffmpeg_version = "60.3.100"'
          '';
        };
        
        # Spandrel package for model loading
        spandrel = pkgs.python312Packages.buildPythonPackage rec {
          pname = "spandrel";
          version = "0.4.1";
          format = "wheel";
          
          src = pkgs.fetchPypi {
            inherit pname version format;
            python = "py3";
            platform = "any";
            hash = "sha256-tDZCXihEgDtDgO8UeK1wInjmpLU7B3WsUcfsMWlBP64=";
          };
          
          propagatedBuildInputs = with pkgs.python312Packages; [
            torch-bin
            torchvision-bin
            numpy
            safetensors
            einops
          ];
          
          doCheck = false;
        };
        
        # Comprehensive Python environment with all required dependencies
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
            
            # Custom packages
            comfyui-frontend-package
            python-av
            spandrel
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

# No longer need Python venv for additional packages as everything is handled by Nix
echo "Using Nix-provided packages, no additional pip installation needed"

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
