# Model Downloader Custom Node
import os
import sys
import requests
import json
import logging
import traceback
import time
import uuid
from pathlib import Path
import folder_paths
from aiohttp import web
from server import PromptServer

# This node doesn't add any actual nodes to the graph
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

# Register the web extension
WEB_DIRECTORY = os.path.join(os.path.dirname(os.path.realpath(__file__)), "js")

# Storage for active downloads
active_downloads = {}

# Define the download model endpoint
async def download_model(request):
    """
    Handle POST requests to download models
    """
    try:
        # Handle FormData instead of JSON
        data = await request.post()
        url = data.get('url')
        folder = data.get('folder')
        filename = data.get('filename')
        client_id = data.get('client_id', str(uuid.uuid4()))
        
        print(f"[MODEL_DOWNLOADER] Received download request for {filename} in folder {folder}")
        
        if not url or not folder or not filename:
            print(f"[MODEL_DOWNLOADER] Missing required parameters")
            return web.json_response({"success": False, "error": "Missing required parameters"})
        
        # Get the model folder path
        folder_path = folder_paths.get_folder_paths(folder)
        
        if not folder_path:
            print(f"[MODEL_DOWNLOADER] Invalid folder: {folder}")
            return web.json_response({"success": False, "error": f"Invalid folder: {folder}"})
        
        # Create the full path for the file
        full_path = os.path.join(folder_path[0], filename)
        
        print(f"[MODEL_DOWNLOADER] Downloading model to {full_path}")
        
        # Initialize download progress tracking
        download_info = {
            "id": client_id,
            "url": url,
            "folder": folder,
            "filename": filename,
            "path": full_path,
            "start_time": time.time(),
            "total_size": 0,
            "downloaded": 0,
            "percent": 0,
            "status": "starting"
        }
        
        # Store in active downloads
        active_downloads[client_id] = download_info
        
        # Return success immediately so UI can show download has started
        # The actual download will continue in the background
        response = web.json_response({
            "success": True, 
            "id": client_id,
            "filename": filename,
            "folder": folder
        })
        
        # Start background task for download
        request.app.loop.create_task(
            download_in_background(client_id, url, folder, filename, full_path)
        )
        
        return response
    except Exception as e:
        error_details = traceback.format_exc()
        print(f"[MODEL_DOWNLOADER] Error downloading model: {str(e)}")
        return web.json_response({"success": False, "error": str(e)})

async def download_in_background(download_id, url, folder, filename, full_path):
    """
    Background task to download a model and update progress
    """
    try:
        # Create the directory if it doesn't exist
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        
        # Download the file
        with requests.get(url, stream=True) as r:
            r.raise_for_status()
            total_size = int(r.headers.get('content-length', 0))
            downloaded = 0
            last_update_time = 0
            chunk_count = 0
            
            # Update total size in download info
            if download_id in active_downloads:
                active_downloads[download_id]["total_size"] = total_size
                active_downloads[download_id]["status"] = "downloading"
                active_downloads[download_id]["downloaded"] = 0
                active_downloads[download_id]["percent"] = 0
                # Send initial progress update
                send_download_progress(download_id)
            
            # Download with progress updates
            with open(full_path, 'wb') as f:
                # Use smaller chunks for more frequent updates (256KB)
                for chunk in r.iter_content(chunk_size=256 * 1024):
                    if chunk:  # filter out keep-alive chunks
                        f.write(chunk)
                        downloaded += len(chunk)
                        chunk_count += 1
                        
                        # Update progress
                        if download_id in active_downloads:
                            active_downloads[download_id]["downloaded"] = downloaded
                            
                            # Calculate percent
                            if total_size > 0:
                                percent = round((downloaded / total_size) * 100, 2)
                                active_downloads[download_id]["percent"] = percent
                                
                                # Current time
                                current_time = time.time()
                            
                            # Send WebSocket updates more frequently but not too often to avoid flooding
                            # Either every 4 chunks or at least 100ms have passed since the last update
                            if chunk_count % 4 == 0 or (current_time - last_update_time) >= 0.1:
                                send_download_progress(download_id)
                                last_update_time = current_time
        
        # Update status to completed
        if download_id in active_downloads:
            active_downloads[download_id]["status"] = "completed"
            active_downloads[download_id]["end_time"] = time.time()
            send_download_progress(download_id)
            print(f"[MODEL_DOWNLOADER] Model downloaded successfully to {full_path}")
            
            # Clean up after some time to avoid memory leaks
            request_app = PromptServer.instance.app
            request_app.loop.call_later(60, lambda: active_downloads.pop(download_id, None))
    except Exception as e:
        # Update status to error
        if download_id in active_downloads:
            active_downloads[download_id]["status"] = "error"
            active_downloads[download_id]["error"] = str(e)
            active_downloads[download_id]["end_time"] = time.time()
            send_download_progress(download_id)
        print(f"[MODEL_DOWNLOADER] Error downloading file: {e}")

def send_download_progress(download_id):
    """
    Send progress update via WebSocket
    """
    if download_id in active_downloads:
        try:
            download = active_downloads[download_id]
            # Calculate speed if we have enough information
            current_time = time.time()
            start_time = download.get("start_time", current_time)
            downloaded = download.get("downloaded", 0)
            elapsed = max(0.001, current_time - start_time) # Avoid division by zero
            
            # Calculate speed in bytes per second
            speed = downloaded / elapsed if elapsed > 0 else 0
            
            # Format speed for display
            speed_text = ""
            if speed > 1024 * 1024:
                speed_text = f"{speed / (1024 * 1024):.2f} MB/s"
            elif speed > 1024:
                speed_text = f"{speed / 1024:.2f} KB/s"
            else:
                speed_text = f"{speed:.0f} B/s"
                
            # Add estimated time remaining if we have percent and total size
            eta_text = ""
            percent = download.get("percent", 0)
            total_size = download.get("total_size", 0)
            
            if percent > 0 and percent < 100 and total_size > 0 and speed > 0:
                remaining_bytes = total_size - downloaded
                eta_seconds = remaining_bytes / speed
                
                if eta_seconds < 60:
                    eta_text = f"{eta_seconds:.0f} seconds"
                elif eta_seconds < 3600:
                    eta_text = f"{eta_seconds / 60:.1f} minutes"
                else:
                    eta_text = f"{eta_seconds / 3600:.1f} hours"
            
            # Send via WebSocket with additional information
            PromptServer.instance.send_sync("model_download_progress", {
                "download_id": download_id,
                "filename": download.get("filename"),
                "folder": download.get("folder"),
                "total_size": download.get("total_size"),
                "downloaded": download.get("downloaded"),
                "percent": download.get("percent"),
                "status": download.get("status"),
                "error": download.get("error"),
                "speed": speed_text,
                "eta": eta_text
            })
        except Exception as e:
            print(f"[MODEL_DOWNLOADER] Error sending WebSocket update: {e}")

async def get_download_progress(request):
    """
    Handle GET requests for download progress
    """
    try:
        download_id = request.match_info.get('download_id')
        if download_id and download_id in active_downloads:
            return web.json_response({
                "success": True,
                "download": active_downloads[download_id]
            })
        else:
            return web.json_response({
                "success": False,
                "error": f"Download with ID {download_id} not found"
            }, status=404)
    except Exception as e:
        return web.json_response({
            "success": False,
            "error": str(e)
        }, status=500)

async def get_all_downloads(request):
    """
    Handle GET requests for all downloads
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
        }, status=500)

# Register the API endpoints when the server starts
try:
    app = PromptServer.instance.app
    app.router.add_post('/api/download-model', download_model)
    app.router.add_get('/api/download-progress/{download_id}', get_download_progress)
    app.router.add_get('/api/downloads', get_all_downloads)
    print("[MODEL_DOWNLOADER] API endpoints registered for model downloader")
except Exception as e:
    print(f"[MODEL_DOWNLOADER] Error registering API endpoints: {e}")
    traceback.print_exc()

print(f"Model Downloader patch loaded successfully from {WEB_DIRECTORY}")
