# ComfyUI Development Guidelines

## IMPORTANT WORKFLOW RULES
**ALWAYS run `git add` after making file changes!** The Nix flake requires this for proper operation.
**NEVER commit changes unless explicitly requested by the user.**

## Build/Run Commands
- **Run application**: `nix run` (builds and runs the app with Nix)
- **Run with browser**: `nix run -- --open` (automatically opens browser)
- **Build with Nix**: `nix build` (builds the app without running)
- **Develop with Nix**: `nix develop` (opens development shell)
- **Lint**: `ruff check src/` (checks for code issues)

## Project Architecture

### Directory Structure
- **src/custom_nodes/**: Custom node extensions for ComfyUI
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
- **Model Downloader**: Handles downloading missing models from remote sources
- **Persistence Module**: Ensures models and settings persist across runs
- **Nix Integration**: Provides reproducible builds with flake.nix
- **Modular Launcher**: Manages installation, configuration, and runtime with separated concerns
- **Logging System**: Provides consistent, configurable logging across all components

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