import os
import sys
import requests
import json
import logging
import traceback
from pathlib import Path
import folder_paths
from aiohttp import web
import asyncio
from concurrent.futures import ThreadPoolExecutor

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('model_downloader')

# Print debug information
print("[MODEL_DOWNLOADER] Loading model downloader patch...")
print(f"[MODEL_DOWNLOADER] Python version: {sys.version}")
print(f"[MODEL_DOWNLOADER] Current working directory: {os.getcwd()}")

# Try to import PromptServer
try:
    from server import PromptServer
    print("[MODEL_DOWNLOADER] Successfully imported PromptServer")
except Exception as e:
    print(f"[MODEL_DOWNLOADER] Error importing PromptServer: {e}")
    traceback.print_exc()
    
# This will be imported by the custom node's __init__.py

def download_model_to_correct_location(url, model_name, directory):
    """
    Download a model from a URL to the correct location based on the directory type.
    
    Args:
        url (str): URL to download the model from
        model_name (str): Filename to save the model as
        directory (str): Directory type (e.g., 'checkpoints', 'loras', etc.)
        
    Returns:
        bool: True if download was successful, False otherwise
    """
    try:
        # Get the appropriate folder based on directory type
        folders = folder_paths.get_folder_paths(directory)
        if not folders:
            logger.error(f"Invalid directory '{directory}'")
            return False
            
        target_dir = folders[0]
        os.makedirs(target_dir, exist_ok=True)
        
        target_path = os.path.join(target_dir, model_name)
        logger.info(f"Downloading model from {url} to {target_path}")
        
        with requests.get(url, stream=True) as r:
            r.raise_for_status()
            total_size = int(r.headers.get('content-length', 0))
            with open(target_path, 'wb') as f:
                downloaded = 0
                for chunk in r.iter_content(chunk_size=8192):
                    f.write(chunk)
                    downloaded += len(chunk)
                    percent = int(100 * downloaded / total_size) if total_size > 0 else 0
                    sys.stdout.write(f"\rDownloading: {percent}% [{downloaded}/{total_size}]")
                    sys.stdout.flush()
        
        logger.info(f"Download complete: {target_path}")
        return True
    except Exception as e:
        logger.error(f"Error downloading model: {e}")
        return False

# Define the download model endpoint
async def download_model(request):
    """
    Handle POST requests to download models
    """
    try:
        data = await request.json()
        url = data.get('url')
        folder = data.get('folder')
        filename = data.get('filename')
        
        print(f"[MODEL_DOWNLOADER] Received download request for {filename} in folder {folder} from {url}")
        
        if not url or not folder or not filename:
            print(f"[MODEL_DOWNLOADER] Missing required parameters: url={url}, folder={folder}, filename={filename}")
            return web.json_response({"success": False, "error": "Missing required parameters"})
        
        # Get the model folder path
        folder_path = folder_paths.get_folder_paths(folder)
        
        if not folder_path:
            print(f"[MODEL_DOWNLOADER] Invalid folder: {folder}")
            return web.json_response({"success": False, "error": f"Invalid folder: {folder}"})
        
        # Create the full path for the file
        full_path = os.path.join(folder_path[0], filename)
        
        print(f"[MODEL_DOWNLOADER] Downloading model to {full_path}")
        
        # Create a thread pool executor to handle the download in the background
        with ThreadPoolExecutor() as executor:
            # Run the download in a separate thread to avoid blocking the event loop
            future = executor.submit(download_model_to_correct_location, url, filename, folder)
            success = future.result()
        
        if success:
            print(f"[MODEL_DOWNLOADER] Model downloaded successfully to {full_path}")
            return web.json_response({"success": True, "path": full_path})
        else:
            print(f"[MODEL_DOWNLOADER] Failed to download model to {full_path}")
            return web.json_response({"success": False, "error": "Failed to download model"})
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"[MODEL_DOWNLOADER] Error downloading model: {str(e)}")
        print(f"[MODEL_DOWNLOADER] Error details: {error_details}")
        return web.json_response({"success": False, "error": str(e)})

def setup_js_api(app, *args, **kwargs):
    """
    Set up the JavaScript API for the model downloader.
    
    Args:
        app: The aiohttp application
        
    Returns:
        The modified app
    """
    print("[MODEL_DOWNLOADER] setup_js_api called with app:", app)
    print("[MODEL_DOWNLOADER] args:", args)
    print("[MODEL_DOWNLOADER] kwargs:", kwargs)
    
    # Register the API endpoint
    try:
        # Directly add the route to the app router
        app.router.add_post('/api/download-model', download_model)
        
        print("[MODEL_DOWNLOADER] API endpoint registered at /api/download-model")
        print("[MODEL_DOWNLOADER] All registered routes:")
        for route in app.router.routes():
            print(f"[MODEL_DOWNLOADER]   {route}")
    except Exception as e:
        print(f"[MODEL_DOWNLOADER] Error registering API endpoint: {e}")
        traceback.print_exc()
    
    # Log that the patch has been applied
    print("[MODEL_DOWNLOADER] Model downloader patch applied successfully")
    
    return app

# Log that the patch has been applied
logger.info("Model downloader patch applied successfully")
