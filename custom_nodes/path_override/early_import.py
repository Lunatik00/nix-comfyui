"""
Early import module for ComfyUI path persistence.
This must be imported BEFORE folder_paths or any other ComfyUI modules.
"""
import os
import sys
import logging

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('path_override')

# Get the persistent base directory
BASE_DIR = os.environ.get('COMFY_USER_DIR', os.path.join(os.path.expanduser('~'), '.config', 'comfy-ui'))
logger.info(f"Using persistent directory: {BASE_DIR}")

# Create persistent paths if they don't exist
os.makedirs(os.path.join(BASE_DIR, "models"), exist_ok=True)
os.makedirs(os.path.join(BASE_DIR, "output"), exist_ok=True)
os.makedirs(os.path.join(BASE_DIR, "input"), exist_ok=True)
os.makedirs(os.path.join(BASE_DIR, "user"), exist_ok=True)
os.makedirs(os.path.join(BASE_DIR, "temp"), exist_ok=True)

# Monkey patch the os.path module to override the base directories
original_join = os.path.join

def patched_join(*paths):
    """
    Override os.path.join to redirect specific model paths to our persistent directory
    """
    result = original_join(*paths)
    
    # Check if this is a model directory path
    app_dir = os.path.dirname(os.path.realpath(__file__))
    app_dir = os.path.dirname(os.path.dirname(os.path.dirname(app_dir)))
    
    # Map app paths to persistent paths
    if len(paths) >= 2 and paths[0] == app_dir:
        if paths[1] == "models":
            # This is a models directory path, redirect to persistent location
            new_path = original_join(BASE_DIR, *paths[1:])
            logger.info(f"Redirecting model path: {result} -> {new_path}")
            return new_path
        elif paths[1] in ["output", "input", "user", "temp"]:
            # Redirect other special directories
            new_path = original_join(BASE_DIR, *paths[1:])
            return new_path
    
    return result

# Apply the monkey patch
os.path.join = patched_join

# Override CLI args to ensure base directory is set
import sys
if '--base-directory' not in sys.argv:
    sys.argv.extend(['--base-directory', BASE_DIR])

logger.info("Path overrides applied at early import stage")
