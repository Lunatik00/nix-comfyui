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

        python = pkgs.python312;
        
        # Define the Python packages we need
        pythonPackages = ps: with ps; [
          # Core dependencies
          pip
          setuptools
          wheel
          
          # Basic dependencies
          numpy
          pillow
          pyyaml
          requests
          einops
          kornia
          typing-extensions
          psutil
          aiohttp
          scipy
          tqdm
        ];
        
        # Create a Python environment with the base packages
        baseEnv = python.withPackages pythonPackages;
        
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
          ];
          
          buildInputs = [
            baseEnv
            # Add ML packages separately to avoid collisions
            python.pkgs.torch-bin
            python.pkgs.torchvision
            python.pkgs.safetensors
            python.pkgs.transformers
            python.pkgs.opencv4
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
            
            # Create wrapper script with proper PYTHONPATH
            makeWrapper ${python}/bin/python $out/bin/comfy-ui \
              --prefix PYTHONPATH : "${baseEnv}/${python.sitePackages}" \
              --prefix PYTHONPATH : "${python.pkgs.torch-bin}/${python.sitePackages}" \
              --prefix PYTHONPATH : "${python.pkgs.torchvision}/${python.sitePackages}" \
              --prefix PYTHONPATH : "${python.pkgs.safetensors}/${python.sitePackages}" \
              --prefix PYTHONPATH : "${python.pkgs.transformers}/${python.sitePackages}" \
              --prefix PYTHONPATH : "${python.pkgs.opencv4}/${python.sitePackages}" \
              --prefix PYTHONPATH : "$out/share/comfy-ui" \
              --run "cd $out/share/comfy-ui" \
              --add-flags "main.py"
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
            baseEnv
            python.pkgs.torch-bin
            python.pkgs.torchvision
            python.pkgs.safetensors
            python.pkgs.transformers
            python.pkgs.opencv4
          ];
          
          shellHook = ''
            echo "ComfyUI development environment activated"
            echo "Run 'python main.py' to start ComfyUI"
            export PYTHONPATH="$PWD:$PYTHONPATH"
          '';
        };
      }
    );
}
