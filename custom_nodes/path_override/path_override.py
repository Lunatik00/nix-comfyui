import os
import sys
import logging

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('path_override')

# Get the persistent base directory
BASE_DIR = os.environ.get('COMFY_USER_DIR', os.path.join(os.path.expanduser('~'), '.config', 'comfy-ui'))
logger.info(f"Using persistent directory: {BASE_DIR}")

# Override folder_paths before it's imported
def patch_paths():
    logger.info("Patching ComfyUI folder paths")
    
    # Import the original module
    import folder_paths
    
    # Store the original get_folder_paths function
    original_get_folder_paths = folder_paths.get_folder_paths
    
    # Override folder paths with our persistent paths
    def patched_get_folder_paths(folder_name):
        # Get original paths
        original_paths = original_get_folder_paths(folder_name)
        
        # If we have a persistent directory for this folder, use it instead
        persistent_path = os.path.join(BASE_DIR, "models", folder_name)
        if os.path.exists(persistent_path):
            logger.info(f"Using persistent path for {folder_name}: {persistent_path}")
            return ([persistent_path], original_paths[1])
        
        return original_paths
    
    # Replace the function
    folder_paths.get_folder_paths = patched_get_folder_paths
    
    # Also set output and input directories to our persistent directories
    output_dir = os.path.join(BASE_DIR, "output")
    if os.path.exists(output_dir):
        logger.info(f"Setting output directory to: {output_dir}")
        folder_paths.set_output_directory(output_dir)
    
    input_dir = os.path.join(BASE_DIR, "input")
    if os.path.exists(input_dir):
        logger.info(f"Setting input directory to: {input_dir}")
        folder_paths.set_input_directory(input_dir)
    
    # Set the temp directory
    temp_dir = os.path.join(BASE_DIR, "temp")
    if not os.path.exists(temp_dir):
        os.makedirs(temp_dir, exist_ok=True)
    folder_paths.set_temp_directory(temp_dir)
    
    # Set user directory
    user_dir = os.path.join(BASE_DIR, "user")
    if os.path.exists(user_dir):
        logger.info(f"Setting user directory to: {user_dir}")
        folder_paths.set_user_directory(user_dir)
    
    # Override paths in the module
    folder_paths.output_directory = output_dir
    folder_paths.input_directory = input_dir
    folder_paths.temp_directory = temp_dir
    folder_paths.user_directory = user_dir
    
    logger.info("Path patching complete")

# Apply the patch
try:
    patch_paths()
    logger.info("Successfully applied path override patch")
except Exception as e:
    logger.error(f"Error applying path override patch: {e}")
    import traceback
    traceback.print_exc()
