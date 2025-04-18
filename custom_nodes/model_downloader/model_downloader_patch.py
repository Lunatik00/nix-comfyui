import os
import sys
import time
import asyncio
import requests
import json
import logging
import traceback
from pathlib import Path
import folder_paths
from aiohttp import web
import concurrent.futures
from server import PromptServer

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

# Store active downloads with their progress information
active_downloads = {}

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
        
        # Generate a unique download ID
        download_id = f"{folder}_{filename}_{int(time.time())}"
        
        # Create a download entry
        active_downloads[download_id] = {
            'url': url,
            'folder': folder,
            'filename': filename,
            'path': full_path,
            'total_size': 0,
            'downloaded': 0,
            'percent': 0,
            'status': 'starting',
            'error': None
        }
        
        # Get the file size if possible before starting the download
        try:
            # Send a HEAD request to get the content length without downloading the file
            head_response = requests.head(url, allow_redirects=True, timeout=10)
            total_size = int(head_response.headers.get('content-length', 0))
            print(f"[MODEL_DOWNLOADER] File size from HEAD request: {total_size} bytes")
            
            # Update the download entry with the total size
            active_downloads[download_id]['total_size'] = total_size
        except Exception as e:
            print(f"[MODEL_DOWNLOADER] Error getting file size: {e}")
            # If we can't get the size, we'll just use 0 and update it during download
            total_size = 0
        
        # Start download in background task
        PromptServer.instance.loop.create_task(download_file(download_id, url, full_path))
        
        # Return the download ID and total size so the frontend can track progress
        return web.json_response({
            "success": True, 
            "download_id": download_id,
            "total_size": total_size,
            "path": full_path,
            "status": "started"
        })
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"[MODEL_DOWNLOADER] Error starting model download: {str(e)}")
        print(f"[MODEL_DOWNLOADER] Error details: {error_details}")
        return web.json_response({"success": False, "error": str(e)})

async def download_file(download_id, url, full_path):
    """
    Background task to download a file and update progress
    """
    try:
        # Create the directory if it doesn't exist
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        
        # Update status
        active_downloads[download_id]['status'] = 'downloading'
        
        # Send initial progress update
        await send_download_update(download_id)
        
        # Download the file
        with requests.get(url, stream=True) as r:
            r.raise_for_status()
            total_size = int(r.headers.get('content-length', 0))
            active_downloads[download_id]['total_size'] = total_size
            
            downloaded = 0
            last_update_time = time.time()
            
            with open(full_path, 'wb') as f:
                for chunk in r.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
                        downloaded += len(chunk)
                        active_downloads[download_id]['downloaded'] = downloaded
                        
                        if total_size > 0:
                            percent = (downloaded / total_size) * 100
                            active_downloads[download_id]['percent'] = percent
                            
                            # Update progress every 0.5 seconds or every 5MB, whichever comes first
                            current_time = time.time()
                            if (current_time - last_update_time >= 0.5 or 
                                downloaded % (5 * 1024 * 1024) < 8192):
                                last_update_time = current_time
                                await send_download_update(download_id)
                                
                                # Also log to console occasionally (every 10MB)
                                if downloaded % (10 * 1024 * 1024) < 8192:
                                    print(f"[MODEL_DOWNLOADER] Downloaded {downloaded / (1024 * 1024):.2f} MB of {total_size / (1024 * 1024):.2f} MB ({percent:.2f}%)")
        
        # Update status to completed
        active_downloads[download_id]['status'] = 'completed'
        await send_download_update(download_id)
        
        print(f"[MODEL_DOWNLOADER] Model downloaded successfully to {full_path}")
        
        # Keep the download in active_downloads for a while so the frontend can see it completed
        # then remove it after 30 seconds
        await asyncio.sleep(30)
        if download_id in active_downloads:
            del active_downloads[download_id]
            
    except Exception as e:
        error_details = traceback.format_exc()
        print(f"[MODEL_DOWNLOADER] Error downloading file: {e}")
        print(f"[MODEL_DOWNLOADER] Error details: {error_details}")
        
        # Update status to error
        if download_id in active_downloads:
            active_downloads[download_id]['status'] = 'error'
            active_downloads[download_id]['error'] = str(e)
            await send_download_update(download_id)

async def send_download_update(download_id):
    """
    Send a progress update via websocket
    """
    if download_id in active_downloads:
        download_info = active_downloads[download_id]
        
        # Create a message to send
        message = {
            'type': 'model_download_progress',
            'download_id': download_id,
            'filename': download_info['filename'],
            'folder': download_info['folder'],
            'total_size': download_info['total_size'],
            'downloaded': download_info['downloaded'],
            'percent': download_info['percent'],
            'status': download_info['status'],
            'error': download_info['error']
        }
        
        # Send the message to all connected clients
        await PromptServer.instance.send_json(message)

async def get_download_progress(request):
    """
    Get the progress of a download
    """
    try:
        download_id = request.match_info.get('download_id')
        
        if download_id in active_downloads:
            return web.json_response({
                "success": True,
                "download": active_downloads[download_id]
            })
        else:
            return web.json_response({
                "success": False,
                "error": "Download not found"
            })
    except Exception as e:
        return web.json_response({
            "success": False,
            "error": str(e)
        })

async def list_downloads(request):
    """
    List all active downloads
    """
    try:
        return web.json_response({
            "success": True,
            "downloads": active_downloads
        })
    except Exception as e:
        return web.json_response({
            "success": False,
            "error": str(e)
        })

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
    
    # Register the API endpoints
    try:
        app.router.add_post('/api/download-model', download_model)
        app.router.add_get('/api/download-progress/{download_id}', get_download_progress)
        app.router.add_get('/api/downloads', list_downloads)
        print("[MODEL_DOWNLOADER] API endpoints registered")
    except Exception as e:
        print(f"[MODEL_DOWNLOADER] Error registering API endpoints: {e}")
        traceback.print_exc()
    
    # Log that the patch has been applied
    print("[MODEL_DOWNLOADER] Model downloader patch applied successfully")
    
    return app

# Log that the patch has been applied
logger.info("Model downloader patch applied successfully")
