# Model Downloader Custom Node
import os
import sys
import requests
import json
import logging
import traceback
from pathlib import Path
import folder_paths
from aiohttp import web
from server import PromptServer

# This node doesn't add any actual nodes to the graph
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

# Register the web extension
WEB_DIRECTORY = os.path.join(os.path.dirname(os.path.realpath(__file__)), "js")

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
        
        # Download the file
        try:
            # Create the directory if it doesn't exist
            os.makedirs(os.path.dirname(full_path), exist_ok=True)
            
            # Download the file
            with requests.get(url, stream=True) as r:
                r.raise_for_status()
                total_size = int(r.headers.get('content-length', 0))
                downloaded = 0
                with open(full_path, 'wb') as f:
                    for chunk in r.iter_content(chunk_size=8192):
                        if chunk:
                            f.write(chunk)
                            downloaded += len(chunk)
                            if total_size > 0 and downloaded % (1024 * 1024 * 10) == 0:  # Report every 10MB
                                print(f"[MODEL_DOWNLOADER] Downloaded {downloaded / (1024 * 1024):.2f} MB of {total_size / (1024 * 1024):.2f} MB ({(downloaded / total_size) * 100:.2f}%)")
            
            print(f"[MODEL_DOWNLOADER] Model downloaded successfully to {full_path}")
            return web.json_response({"success": True, "path": full_path})
        except Exception as e:
            print(f"[MODEL_DOWNLOADER] Error downloading file: {e}")
            return web.json_response({"success": False, "error": str(e)})
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"[MODEL_DOWNLOADER] Error downloading model: {str(e)}")
        print(f"[MODEL_DOWNLOADER] Error details: {error_details}")
        return web.json_response({"success": False, "error": str(e)})

# Register the API endpoint when the server starts
try:
    app = PromptServer.instance.app
    app.router.add_post('/api/download-model', download_model)
    print("[MODEL_DOWNLOADER] API endpoint registered at /api/download-model")
except Exception as e:
    print(f"[MODEL_DOWNLOADER] Error registering API endpoint: {e}")
    traceback.print_exc()

print(f"Model Downloader patch loaded successfully from {WEB_DIRECTORY}")
