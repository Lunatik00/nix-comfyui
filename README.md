# ComfyUI Nix Flake

**⚠️ NOTE: Model persistence across runs is not yet fully configured - this feature is in progress.**

A Nix flake for installing and running [ComfyUI](https://github.com/comfyanonymous/ComfyUI) with Python 3.12, optimized for Apple Silicon.

![ComfyUI Demo](comfyui-demo.gif)

> **Note:** Pull requests are more than welcome! Contributions to this open project are appreciated.

## Quick Start

```bash
nix run github:jamesbrink/nix-comfyui -- --open
```

## Features

- Provides ComfyUI packaged with Python 3.12
- Reproducible environment through Nix flakes
- Hybrid approach: Nix for environment management, pip for Python dependencies
- Optimized for Apple Silicon with PyTorch nightly builds
- Persistent user data directory
- Includes ComfyUI-Manager for easy extension installation
- Improved model download experience with automatic backend downloads

## Additional Options

```bash
# Run a specific version using a commit hash
nix run github:jamesbrink/nix-comfyui/[commit-hash] -- --open
```

### Command Line Options

- `--open`: Automatically opens ComfyUI in your browser when the server is ready

### Development Shell

```bash
# Enter a development shell with all dependencies
nix develop
```

### Installation

You can install ComfyUI to your profile:

```bash
nix profile install github:jamesbrink/nix-comfyui
```

## Customization

The flake is designed to be simple and extensible. You can customize it by:

1. Adding Python packages in the `pythonEnv` definition
2. Modifying the launcher script in `scripts/launcher.sh`
3. Pinning to a specific ComfyUI version by changing the `rev` in `fetchFromGitHub`

### Project Structure

This flake uses a multi-file approach for better maintainability:

- `flake.nix` - Main flake definition and package configuration
- `scripts/launcher.sh` - The launcher script that sets up the environment and runs ComfyUI

This structure makes it easier to maintain and extend the flake as more features are added.

## Data Persistence

User data is stored in `~/.config/comfy-ui` with the following structure:

- `app/` - ComfyUI application code (auto-updated when flake changes)
- `models/` - Stable Diffusion models and other model files
- `output/` - Generated images and other outputs
- `user/` - User configuration and custom nodes
- `input/` - Input files for processing

This structure ensures your models, outputs, and custom nodes persist between application updates.

## Apple Silicon Support

This flake is specifically optimized for Apple Silicon Macs:

- Uses PyTorch nightly builds with improved MPS (Metal Performance Shaders) support
- Enables FP16 precision mode for better performance
- Sets optimal memory management parameters for macOS

## Version Information

This flake currently provides:

- ComfyUI v0.3.28
- Python 3.12.9
- PyTorch nightly builds with Apple Silicon optimizations
- ComfyUI Frontend Package 1.17.0
- ComfyUI-Manager for extension management

## Model Downloading Patch

This flake includes a custom patch for the model downloading experience. Unlike the default ComfyUI implementation, our patch ensures that when models are selected in the UI, they are automatically downloaded in the background without requiring manual intervention. This significantly improves the user experience by eliminating the need to manually manage model downloads, especially for new users who may not be familiar with the process of obtaining and placing model files.

## License

This flake is provided under the MIT license. ComfyUI itself is licensed under GPL-3.0.
