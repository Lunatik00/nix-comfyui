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
        
        # Simplified approach - only include the minimum necessary packages
        # directly, and let ComfyUI use pip to install the rest
        pythonEnv = pkgs.python312.buildEnv.override {
          extraLibs = with pkgs.python312Packages; [
            # Core Python tools
            pip
            setuptools
            wheel
            
            # Only include a minimal set of packages to avoid collisions
            # These are the absolute essentials ComfyUI will need to bootstrap
            numpy
            pillow
            requests
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
            cp -r $src/* $out/share/comfy-ui/
            
            # Create requirements-nix.txt without torch-related packages
            cat > $out/share/comfy-ui/requirements-nix.txt << EOL
            pyyaml
            tqdm
            aiohttp
            yarl
            scipy
            psutil
            typing-extensions
            einops
            transformers
            tokenizers
            sentencepiece
            safetensors
            kornia
            opencv-python
            EOL
            
            # Create a wrapper script that sets up the environment and installs dependencies
            makeWrapper ${pythonEnv}/bin/python $out/bin/comfy-ui \
              --add-flags "$out/share/comfy-ui/main.py" \
              --run "cd $out/share/comfy-ui && ${pythonEnv}/bin/pip install torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 torchsde && ${pythonEnv}/bin/pip install -r requirements-nix.txt" \
              --set PYTHONPATH "$out/share/comfy-ui:$PYTHONPATH"
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
            echo "Installing required dependencies..."
            
            # Create a minimal requirements file for pip installation
            cat > requirements-nix.txt << EOL
            torch==2.5.1
            torchvision==0.20.1
            torchaudio==2.5.1
            torchsde
            pyyaml
            tqdm
            aiohttp
            yarl
            scipy
            psutil
            typing-extensions
            einops
            transformers
            tokenizers
            sentencepiece
            safetensors
            kornia
            opencv-python
            EOL
            
            # Install dependencies via pip to avoid Nix collisions
            pip install -r requirements-nix.txt
            
            echo "Run 'python main.py' to start ComfyUI"
            export PYTHONPATH="$PWD:$PYTHONPATH"
          '';
        };
      }
    );
}
