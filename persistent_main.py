#!/usr/bin/env python3
# Custom main.py to ensure path persistence in ComfyUI

import os
import sys
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('persistence')

# Define the persistent base directory - get from environment or use default
PERSISTENT_DIR = os.environ.get('COMFY_USER_DIR', os.path.join(os.path.expanduser('~'), '.config', 'comfy-ui'))
logger.info(f"Using persistent directory: {PERSISTENT_DIR}")

# Ensure all necessary directories exist
os.makedirs(PERSISTENT_DIR, exist_ok=True)
os.makedirs(os.path.join(PERSISTENT_DIR, "models"), exist_ok=True)
os.makedirs(os.path.join(PERSISTENT_DIR, "models/checkpoints"), exist_ok=True)
os.makedirs(os.path.join(PERSISTENT_DIR, "models/loras"), exist_ok=True)
os.makedirs(os.path.join(PERSISTENT_DIR, "models/vae"), exist_ok=True)
os.makedirs(os.path.join(PERSISTENT_DIR, "models/clip"), exist_ok=True)
os.makedirs(os.path.join(PERSISTENT_DIR, "models/controlnet"), exist_ok=True)
os.makedirs(os.path.join(PERSISTENT_DIR, "models/upscale_models"), exist_ok=True)
os.makedirs(os.path.join(PERSISTENT_DIR, "output"), exist_ok=True)
os.makedirs(os.path.join(PERSISTENT_DIR, "input"), exist_ok=True)
os.makedirs(os.path.join(PERSISTENT_DIR, "temp"), exist_ok=True)
os.makedirs(os.path.join(PERSISTENT_DIR, "user"), exist_ok=True)

# Force the base directory in command line arguments
if '--base-directory' not in sys.argv:
    sys.argv.append('--base-directory')
    sys.argv.append(PERSISTENT_DIR)
else:
    # Find the index and replace its value
    index = sys.argv.index('--base-directory')
    if index + 1 < len(sys.argv):
        sys.argv[index + 1] = PERSISTENT_DIR

# Make sure the --persistent flag is set
if '--persistent' not in sys.argv:
    sys.argv.append('--persistent')

# Output current arguments for debugging
logger.info(f"Command line arguments: {sys.argv}")

# Set environment variables
os.environ['COMFY_USER_DIR'] = PERSISTENT_DIR
os.environ['COMFY_SAVE_PATH'] = os.path.join(PERSISTENT_DIR, "user")

# Import and run the original main
app_dir = os.path.dirname(os.path.realpath(__file__))
original_main = os.path.join(app_dir, "main.py")

logger.info(f"Executing original main.py: {original_main}")

# Execute the original main script
with open(original_main) as f:
    code = compile(f.read(), original_main, 'exec')
    exec(code, globals(), locals())
