# ComfyUI Nix Flake

A Nix flake for installing and running [ComfyUI](https://github.com/comfyanonymous/ComfyUI) with Python 3.12.

## Features

- Provides ComfyUI packaged with Python 3.12
- Reproducible environment through Nix flakes
- Hybrid dependency management to avoid package collisions
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

1. Adding Python packages in the `pythonEnv` definition or in requirements files
2. Modifying runtime parameters in the `installPhase`
3. Pinning to a specific ComfyUI version by changing the `rev` in `fetchFromGitHub`

## First-time Setup

When first building the flake, you'll need to replace the `fakeSha256` with the actual hash:

1. Run `nix build` and it will fail with the correct hash
2. Replace `pkgs.lib.fakeSha256` with the provided hash
3. Run `nix build` again to complete the build

## License

This flake is provided under the MIT license. ComfyUI itself is licensed under GPL-3.0.
