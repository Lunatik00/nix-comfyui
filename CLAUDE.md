# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## IMPORTANT WORKFLOW RULES
**ALWAYS run `git add` after making file changes!** The Nix flake requires this for proper operation.
**NEVER commit changes unless explicitly requested by the user.**

## Build/Run Commands
- **Run application**: `nix run` (builds and runs the app with Nix)
- **Run with browser**: `nix run -- --open` (automatically opens browser)
- **Run with custom port**: `nix run -- --port=8080` (specify custom port)
- **Run with debug logging**: `nix run -- --debug` or `nix run -- --verbose`
- **Build with Nix**: `nix build` (builds the app without running)
- **Build Docker image**: `nix run .#buildDocker` (creates `comfy-ui:latest` image)
- **Build CUDA Docker**: `nix run .#buildDockerCuda` (creates `comfy-ui:cuda` image)
- **Run Docker container**: `docker run -p 8188:8188 -v $PWD/data:/data comfy-ui:latest`
- **Run CUDA Docker**: `docker run --gpus all -p 8188:8188 -v $PWD/data:/data comfy-ui:cuda`
- **Develop with Nix**: `nix develop` (opens development shell)
- **Lint**: `ruff check src/` (checks for code issues)

## Project Architecture

### Directory Structure
- **src/custom_nodes/**: Custom node extensions for ComfyUI
  - **model_downloader/**: Non-blocking async model download system with WebSocket progress updates
- **src/patches/**: Runtime patches for ComfyUI behavior
- **src/persistence/**: Data persistence module handling settings and models
- **scripts/**: Modular launcher scripts:
  - **launcher.sh**: Main entry point that orchestrates the launching process
  - **config.sh**: Configuration variables and settings
  - **logger.sh**: Logging utilities with different verbosity levels
  - **install.sh**: Installation and setup procedures
  - **persistence.sh**: Symlink creation and data persistence management
  - **runtime.sh**: Runtime execution and process management

### Key Components
- **Model Downloader**: Non-blocking async download system using aiohttp with WebSocket progress updates
- **Persistence Module**: Patches `folder_paths` module at runtime to redirect all model/data directories to `~/.config/comfy-ui/`
- **Nix Integration**: Provides reproducible builds with Python 3.12 environment
- **Modular Launcher**: Manages installation, configuration, and runtime with separated concerns
- **Logging System**: Provides consistent, configurable logging across all components

### Important Environment Variables
- `COMFY_USER_DIR`: Persistent storage directory (default: `~/.config/comfy-ui`)
- `COMFY_APP_DIR`: ComfyUI application directory
- `COMFY_SAVE_PATH`: User save path for outputs
- `LD_LIBRARY_PATH`: (Linux) Set automatically to include system libraries and NVIDIA drivers
- `DYLD_LIBRARY_PATH`: (macOS) Set if needed for dynamic libraries

### Platform-Specific Configuration
- **Linux**: Automatically detects NVIDIA GPUs and configures CUDA support
- **macOS**: Detects Apple Silicon and configures MPS acceleration
- **Library Paths**: Automatically includes `/run/opengl-driver/lib` on Linux for NVIDIA drivers

### Persisted Model Directories
The following directories are automatically persisted across runs:
- checkpoints, loras, vae, controlnet, embeddings, upscale_models, clip, diffusers

## Code Style Guidelines

### Python
- **Indentation**: 4 spaces
- **Imports**: Standard library first, third-party second, local imports last
- **Error Handling**: Use specific exceptions with logging; configure loggers at module level
- **Naming**: Use `snake_case` for functions/variables, `PascalCase` for classes
- **Logging**: Configure with `logging.basicConfig` and create module-level loggers
- **Module Structure**: For custom nodes, follow ComfyUI's extension system with proper `__init__.py` and `setup_js_api` function

### Frontend (Vue 3)
- **Component Order**: Organize in `<template>`, `<script>`, `<style>` order
- **Props**: Use Vue 3.5 default prop declaration style with TypeScript
- **Composition API**: Use `setup()`, `ref`, `reactive`, `computed`, and lifecycle hooks
- **Styling**: Use Tailwind CSS for styling and responsive design
- **i18n**: Use vue-i18n in composition API for string literals

### Custom Node Development
- Install custom nodes to the persistent location (`~/.config/comfy-ui/custom_nodes/`)
- Create symlinks from the app directory to the persistent location
- Register API endpoints in the `setup_js_api` function
- Frontend JavaScript should be placed in the node's `js/` directory
- Use proper route checking to avoid duplicate endpoint registration

### Bash Scripts
- **Modularity**: Each script should have a single responsibility
- **Function-Based**: Organize code into functions rather than procedural scripts
- **Error Handling**: Use proper traps and error reporting
- **Logging**: Use the logging functions from logger.sh instead of direct echo statements
- **Configuration**: Keep all configurable variables in config.sh
- **Documentation**: Include clear comments and function documentation
- **Strict Mode**: Use appropriate strictness flags (set -u -o pipefail)