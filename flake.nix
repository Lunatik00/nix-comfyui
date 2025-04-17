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
        
        # ComfyUI source
        comfyui-src = pkgs.fetchFromGitHub {
          owner = "comfyanonymous";
          repo = "ComfyUI";
          rev = "a14c2fc3565277dfe8ab0ecb22a86c1d0a1f72cf"; # v0.3.28
          hash = "sha256-d+RxxBmkwuZwRvPfdHGjZ7pllvbIcoITn9Z/1k3m4KE=";
        };
        
        # ComfyUI frontend package
        comfyui-frontend-package = pkgs.python312Packages.buildPythonPackage {
          pname = "comfyui-frontend-package";
          version = "1.17.0";
          format = "wheel";
          
          src = pkgs.fetchurl {
            url = "https://files.pythonhosted.org/packages/py3/c/comfyui_frontend_package/comfyui_frontend_package-1.17.0-py3-none-any.whl";
            hash = "sha256-g6P84Vkh81SYHkxgsHHSHAgrxV4tIdzcZ1q/PX7rEZE=";
          };
          
          doCheck = false;
        };
        
        # Python environment with minimal dependencies
        # Most dependencies will be installed via pip in the virtual environment
        pythonEnv = pkgs.python312.buildEnv.override {
          extraLibs = with pkgs.python312Packages; [
            setuptools wheel pip virtualenv
            requests rich
            comfyui-frontend-package
          ];
          ignoreCollisions = true;
        };
        
        # Create the launcher script as a separate file
        launcherScript = pkgs.writeTextFile {
          name = "comfy-ui-launcher.sh";
          executable = true;
          text = ''
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

            # Update application code if needed
            if [ -f "$CODE_DIR/VERSION" ] && [ "$(cat "$CODE_DIR/VERSION" 2>/dev/null)" = "$COMFY_VERSION" ]; then
              echo "ComfyUI $COMFY_VERSION already installed in $CODE_DIR"
            else
              echo "Installing/updating ComfyUI $COMFY_VERSION in $CODE_DIR"
              rm -rf "$CODE_DIR"/*
              cp -r "${comfyui-src}"/* "$CODE_DIR/"
              echo "$COMFY_VERSION" > "$CODE_DIR/VERSION"
              chmod -R u+rw "$CODE_DIR"
            fi

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

            # Setup virtual environment if needed
            if [ ! -d "$COMFY_VENV" ]; then
              echo "Creating virtual environment for ComfyUI at $COMFY_VENV"
              ${pythonEnv}/bin/python -m venv "$COMFY_VENV"
              
              # Install dependencies
              "$COMFY_VENV/bin/pip" install --upgrade pip
              "$COMFY_VENV/bin/pip" install pyyaml pillow numpy
              "$COMFY_VENV/bin/pip" install -r "$CODE_DIR/requirements.txt"
              "$COMFY_VENV/bin/pip" install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cpu
              "$COMFY_VENV/bin/pip" install spandrel av GitPython toml rich safetensors
            fi

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
          '';
        };
        
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "comfy-ui";
          version = "0.1.0";
          
          src = comfyui-src;
          
          nativeBuildInputs = [ pkgs.makeWrapper pythonEnv ];
          buildInputs = [ pkgs.libGL pkgs.libGLU ];
          
          # Skip build and configure phases
          dontBuild = true;
          dontConfigure = true;
          
          installPhase = ''
            # Create directories
            mkdir -p "$out/bin"
            mkdir -p "$out/share/comfy-ui"
            
            # Copy ComfyUI files
            cp -r ${comfyui-src}/* "$out/share/comfy-ui/"
            
            # Install the launcher script
            cp ${launcherScript} "$out/bin/comfy-ui-launcher"
            chmod +x "$out/bin/comfy-ui-launcher"
            
            # Create a symlink to the launcher
            ln -s "$out/bin/comfy-ui-launcher" "$out/bin/comfy-ui"
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
          packages = [ pythonEnv ];
          
          shellHook = ''
            echo "ComfyUI development environment activated"
            export COMFY_USER_DIR="$HOME/.config/comfy-ui"
            mkdir -p "$COMFY_USER_DIR"
            echo "User data will be stored in $COMFY_USER_DIR"
            export PYTHONPATH="$PWD:$PYTHONPATH"
          '';
        };
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "comfy-ui";
          version = "0.1.0";
          
          src = comfyui-src;
          
          nativeBuildInputs = [ pkgs.makeWrapper pythonEnv ];
          buildInputs = [ pkgs.libGL pkgs.libGLU ];
          
          # Skip build and configure phases
          dontBuild = true;
          dontConfigure = true;
          
          installPhase = ''
            # Create directories
            mkdir -p "$out/bin"
            mkdir -p "$out/share/comfy-ui"
            
            # Copy ComfyUI files
            cp -r ${comfyui-src}/* "$out/share/comfy-ui/"
            
            # Install the launcher script
            cp ${launcherScript} "$out/bin/comfy-ui-launcher"
            chmod +x "$out/bin/comfy-ui-launcher"
            
            # Create a symlink to the launcher
            ln -s "$out/bin/comfy-ui-launcher" "$out/bin/comfy-ui"
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
          packages = [ pythonEnv ];
          
          shellHook = ''
            echo "ComfyUI development environment activated"
            export COMFY_USER_DIR="$HOME/.config/comfy-ui"
            mkdir -p "$COMFY_USER_DIR"
            echo "User data will be stored in $COMFY_USER_DIR"
            export PYTHONPATH="$PWD:$PYTHONPATH"
          '';
        };
      }
    );
}
