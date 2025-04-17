# ComfyUI Nix Flake

A Nix flake for installing and running [ComfyUI](https://github.com/comfyanonymous/ComfyUI) with Python 3.12.

## Features

- Provides ComfyUI packaged with Python 3.12
- Reproducible environment through Nix flakes
- Clean, purely Nix-based dependency management
- Persistent user data directory
- Automatic version matching for PyTorch ecosystem packages
- Development shell for contributing or customizing

## Usage

### Running ComfyUI

```bash
# Run directly from the flake
nix run

# Or if you've cloned the repository
nix run .#
```

### Development Shell

```bash
# Enter a development shell with all dependencies
nix develop
```

### Installation

You can install ComfyUI to your profile:

```bash
nix profile install github:jamesbrink/comfy-ui
```

## Customization

The flake is designed to be simple and extensible. You can customize it by:

1. Adding Python packages in the `pythonEnv` definition
2. Modifying runtime parameters in the `installPhase`
3. Pinning to a specific ComfyUI version by changing the `rev` in `fetchFromGitHub`

## Data Persistence

User data is stored in `~/.config/comfy-ui` with the following structure:

- `app/` - ComfyUI application code (auto-updated when flake changes)
- `models/` - Stable Diffusion models and other model files
- `output/` - Generated images and other outputs
- `user/` - User configuration and custom nodes
- `input/` - Input files for processing

This structure ensures your models, outputs, and custom nodes persist between application updates.

## Current Limitations

- Some optional nodes requiring additional dependencies (`av`, `spandrel`) are disabled
- Audio and video processing nodes are currently disabled 
- Adding custom nodes that need additional PyPi packages requires careful integration

## Version Information

This flake currently provides:

- ComfyUI v0.3.28
- Python 3.12.9
- PyTorch 2.5.1 (with matching torchvision and torchaudio)
- ComfyUI Frontend Package 1.17.0

These versions are carefully matched to ensure compatibility.

## License

This flake is provided under the MIT license. ComfyUI itself is licensed under GPL-3.0.
