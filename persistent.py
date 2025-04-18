#!/usr/bin/env python3

"""
Persistence module for ComfyUI
This script ensures models and other user data persist across runs
"""

import os
import sys
import logging
import shutil
from pathlib import Path

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('persistence')

# Helper functions
def ensure_dir(path):
    """Ensure a directory exists"""
    os.makedirs(path, exist_ok=True)
    
def create_symlink(source, target):
    """Create a symlink, removing target first if it exists"""
    target_path = Path(target)
    if target_path.exists() or target_path.is_symlink():
        if target_path.is_dir() and not target_path.is_symlink():
            shutil.rmtree(target_path)
        else:
            target_path.unlink()
    
    # Create parent dirs if needed
    target_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Create the symlink
    os.symlink(source, target, target_is_directory=Path(source).is_dir())
    logger.info(f"Created symlink: {source} -> {target}")

# Define paths
def setup_persistence():
    """Set up persistence for ComfyUI"""
    
    # Get base directory from environment or use default
    base_dir = os.environ.get('COMFY_USER_DIR', os.path.join(os.path.expanduser('~'), '.config', 'comfy-ui'))
    logger.info(f"Using persistent directory: {base_dir}")
    
    # Create persistent directories
    ensure_dir(base_dir)
    ensure_dir(os.path.join(base_dir, "models"))
    ensure_dir(os.path.join(base_dir, "output"))
    ensure_dir(os.path.join(base_dir, "input"))
    ensure_dir(os.path.join(base_dir, "temp"))
    ensure_dir(os.path.join(base_dir, "user"))
    
    # Create model subdirectories
    model_types = [
        "checkpoints", "configs", "loras", "vae", "clip", "clip_vision", 
        "unet", "diffusion_models", "controlnet", "embeddings", "diffusers",
        "vae_approx", "gligen", "upscale_models", "hypernetworks",
        "photomaker", "style_models", "text_encoders"
    ]
    
    for model_type in model_types:
        ensure_dir(os.path.join(base_dir, "models", model_type))
    
    # Get ComfyUI path - this is the directory where ComfyUI is installed
    comfy_dir = os.path.dirname(os.path.realpath(__file__))
    
    # Set up environment
    os.environ['COMFY_SAVE_PATH'] = os.path.join(base_dir, "user")
    
    # Create symlinks for model directories
    for model_type in model_types:
        persistent_path = os.path.join(base_dir, "models", model_type)
        app_path = os.path.join(comfy_dir, "models", model_type)
        create_symlink(persistent_path, app_path)
    
    # Create symlinks for other directories
    create_symlink(os.path.join(base_dir, "output"), os.path.join(comfy_dir, "output"))
    create_symlink(os.path.join(base_dir, "input"), os.path.join(comfy_dir, "input"))
    create_symlink(os.path.join(base_dir, "temp"), os.path.join(comfy_dir, "temp"))
    create_symlink(os.path.join(base_dir, "user"), os.path.join(comfy_dir, "user"))
    
    # Set command line args
    if '--base-directory' not in sys.argv:
        sys.argv.extend(['--base-directory', base_dir])
    
    return base_dir

# This allows direct import
if __name__ == "__main__":
    setup_persistence()
    print("Persistence setup complete")
