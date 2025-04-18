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
from aiohttp import web, ClientSession, ClientTimeout
import concurrent.futures
from server import PromptServer

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('model_downloader')

# Try to import PromptServer
try:
    from server import PromptServer
except Exception as e:
    logger.error(f"Error importing PromptServer: {e}")
    traceback.print_exc()
    
# Store active downloads with their progress information
active_downloads = {}

# Define the download model endpoint
async def download_model(request):
    """
    Handle POST requests to download models
    This function returns IMMEDIATELY after starting a background download
    """
    try:
        # Try to parse as JSON first
        try:
            data = await request.json()
        except:
            # If JSON parsing fails, try to parse as form data
            data = await request.post()
            
        url = data.get('url')
        folder = data.get('folder')
        filename = data.get('filename')
        
        logger.info(f"Received download request for {filename} in folder {folder}")
        
        if not url or not folder or not filename:
            logger.error(f"Missing required parameters: url={url}, folder={folder}, filename={filename}")
            return web.json_response({"success": False, "error": "Missing required parameters"})
        
        # Get the model folder path
        folder_path = folder_paths.get_folder_paths(folder)
        
        if not folder_path:
            logger.error(f"Invalid folder: {folder}")
            return web.json_response({"success": False, "error": f"Invalid folder: {folder}"})
        
        # Create the full path for the file
        full_path = os.path.join(folder_path[0], filename)
        
        logger.info(f"Will download model to {full_path}")
        
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
            'status': 'downloading',
            'error': None,
            'start_time': time.time(),
            'download_id': download_id
        }
        
        # Create a separate async task for the download
        # This allows us to return to the client immediately
        async def start_download():
            try:
                # Start the actual download
                await download_file(download_id, url, full_path)
                
            except Exception as e:
                logger.error(f"Error in start_download: {e}")
                if download_id in active_downloads:
                    active_downloads[download_id]['status'] = 'error'
                    active_downloads[download_id]['error'] = str(e)
                    await send_download_update(download_id)
        
        # Start the download as a separate task
        # We don't await this!
        PromptServer.instance.loop.create_task(start_download())
        
        # Immediately return a response to the client
        logger.info(f"Download {download_id} queued, returning immediately to client")
        return web.json_response({
            "success": True, 
            "download_id": download_id,
            "status": "queued",
            "message": "Download has been queued and will start automatically"
        })
        
    except Exception as e:
        error_details = traceback.format_exc()
        logger.error(f"Error starting model download: {str(e)}")
        return web.json_response({"success": False, "error": str(e)})

async def download_file(download_id, url, full_path):
    """
    Background task to download a file and update progress.
    Uses aiohttp for non-blocking downloads that won't starve the event loop.
    """
    try:
        logger.info(f"Starting download task for {download_id} from {url} to {full_path}")
        
        # First verify the destination directory exists and is writable
        try:
            target_directory = os.path.dirname(full_path)
            if not os.path.exists(target_directory):
                os.makedirs(target_directory, exist_ok=True)
                logger.info(f"Created directory: {target_directory}")
            
            # Check if the file already exists - if so, add timestamp to avoid conflicts
            if os.path.exists(full_path):
                logger.warning(f"File already exists at {full_path}. Adding timestamp to avoid conflicts.")
                filename_parts = os.path.splitext(os.path.basename(full_path))
                timestamped_filename = f"{filename_parts[0]}_{int(time.time())}{filename_parts[1]}"
                full_path = os.path.join(target_directory, timestamped_filename)
                
                # Update the download entry with the new path
                if download_id in active_downloads:
                    active_downloads[download_id]['path'] = full_path
                    active_downloads[download_id]['filename'] = timestamped_filename
                    logger.info(f"Updated download path to: {full_path}")
        except Exception as e:
            logger.error(f"Error preparing download directory: {e}")
            if download_id in active_downloads:
                active_downloads[download_id]['status'] = 'error'
                active_downloads[download_id]['error'] = f"Failed to create download directory: {str(e)}"
                await send_download_update(download_id)
            return
        
        # Create ClientTimeout with reasonable values
        timeout = ClientTimeout(total=None, connect=30, sock_connect=30, sock_read=30)
        
        # Use aiohttp for fully non-blocking IO
        async with ClientSession(timeout=timeout) as session:
            # First do a HEAD request to get the content length and verify URL
            try:
                async with session.head(url, allow_redirects=True) as head_response:
                    if head_response.status == 200:
                        content_length = head_response.headers.get('content-length')
                        if content_length:
                            total_size = int(content_length)
                            content_type = head_response.headers.get('content-type', '')
                            
                            logger.info(f"File size from HEAD: {total_size} bytes ({total_size / (1024 * 1024):.2f} MB)")
                            
                            # Update the download entry with the total size
                            if download_id in active_downloads:
                                active_downloads[download_id]['total_size'] = total_size
                                active_downloads[download_id]['content_type'] = content_type
                    else:
                        logger.warning(f"HEAD request returned status {head_response.status}")
            except Exception as e:
                logger.warning(f"HEAD request failed: {e}")
            
            # Start the actual download
            async with session.get(url, allow_redirects=True) as response:
                if response.status != 200:
                    raise Exception(f"HTTP error {response.status}: {response.reason}")
                
                # Get file size if not already determined
                total_size = 0
                if download_id in active_downloads:
                    total_size = active_downloads[download_id].get('total_size', 0)
                
                if total_size == 0:
                    content_length = response.headers.get('content-length')
                    if content_length:
                        total_size = int(content_length)
                        # Update the download entry with the total size
                        if download_id in active_downloads:
                            active_downloads[download_id]['total_size'] = total_size
                            active_downloads[download_id]['content_type'] = response.headers.get('content-type', '')
                
                logger.info(f"Starting download of {total_size / (1024 * 1024):.2f} MB file")
                
                # Use a large chunk size (1MB) to reduce overhead
                downloaded = 0
                update_interval = 1.0  # Only send updates every 1 second
                last_update_time = 0
                percent_logged = -1  # Track last logged percentage
                logger.info(f"[{download_id}] Beginning data transfer for {filename}")
                
                with open(full_path, 'wb') as f:
                    async for chunk in response.content.iter_chunked(1024 * 1024):
                        if not chunk:
                            break
                            
                        f.write(chunk)
                        downloaded += len(chunk)
                        
                        # Update progress in memory
                        if download_id in active_downloads:
                            active_downloads[download_id]['downloaded'] = downloaded
                            current_percent = 0
                            if total_size > 0:
                                current_percent = int((downloaded / total_size) * 100)
                                active_downloads[download_id]['percent'] = current_percent
                            
                            # Log progress at 10% increments
                            if current_percent > 0 and current_percent % 10 == 0 and current_percent != percent_logged:
                                percent_logged = current_percent
                                logger.info(f"[{download_id}] Download progress: {current_percent}% ({downloaded/(1024*1024):.2f} MB of {total_size/(1024*1024):.2f} MB)")
                            
                            # Only send throttled updates
                            current_time = time.time()
                            if current_time - last_update_time >= update_interval:
                                last_update_time = current_time
                                await send_download_update(download_id)
        
        # Download completed successfully
        elapsed_time = time.time() - active_downloads[download_id]['start_time'] if download_id in active_downloads else 0
        download_speed = (downloaded / elapsed_time) / (1024 * 1024) if elapsed_time > 0 else 0  # MB/s
        
        logger.info(f"[{download_id}] Download completed: {downloaded / (1024 * 1024):.2f} MB in {elapsed_time:.1f} seconds ({download_speed:.2f} MB/s)")
        
        # Update status to completed
        if download_id in active_downloads:
            active_downloads[download_id]['status'] = 'completed'
            active_downloads[download_id]['end_time'] = time.time()
            active_downloads[download_id]['downloaded'] = downloaded
            active_downloads[download_id]['percent'] = 100 if total_size > 0 else 0
            await send_download_update(download_id)
        
        logger.info(f"[{download_id}] Model downloaded successfully to {full_path}")
        
        # Keep the download info for 60 seconds so the frontend can see it completed
        await asyncio.sleep(60)
        if download_id in active_downloads:
            del active_downloads[download_id]
            
    except Exception as e:
        error_details = traceback.format_exc()
        logger.error(f"Error downloading file: {e}")
        
        # Update status to error
        if download_id in active_downloads:
            active_downloads[download_id]['status'] = 'error'
            active_downloads[download_id]['error'] = str(e)
            active_downloads[download_id]['end_time'] = time.time()
            
            # Send update
            await send_download_update(download_id)

async def send_download_update(download_id):
    """
    Send a progress update via websocket
    """
    if download_id in active_downloads:
        download_info = active_downloads[download_id]

        # Create the progress data
        progress_data = {
            'download_id': download_id,
            'filename': download_info['filename'],
            'folder': download_info['folder'],
            'total_size': download_info['total_size'],
            'downloaded': download_info['downloaded'],
            'percent': download_info['percent'],
            'status': download_info['status'],
            'error': download_info['error'],
            'timestamp': time.time()
        }
        
        # Log important status changes
        if download_info['status'] == 'completed':
            logger.info(f"Download complete: {download_info['filename']}")
        elif download_info['status'] == 'error':
            logger.info(f"Download error: {download_info['error']}")
        
        # Send websocket message
        try:
            PromptServer.instance.send_sync("model_download_progress", progress_data)
        except Exception as e:
            logger.error(f"WebSocket error: {e}")

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
    logger.info("Setting up JavaScript API and registering endpoints")
    
    # Register the API endpoints
    try:
        app.router.add_post('/api/download-model', download_model)
        app.router.add_get('/api/download-progress/{download_id}', get_download_progress)
        app.router.add_get('/api/downloads', list_downloads)
        logger.info("API endpoints registered")
    except Exception as e:
        logger.error(f"Error registering API endpoints: {e}")
        traceback.print_exc()
    
    logger.info("Model downloader patch applied successfully")
    
    return app