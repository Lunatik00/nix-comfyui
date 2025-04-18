# Model Downloader Custom Node
import os
import sys
import logging
import importlib.util
import traceback

# Setup logging
logger = logging.getLogger('model_downloader')

# This node doesn't add any actual nodes to the graph
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

# Register the web extension directory for ComfyUI to find the JavaScript files
WEB_DIRECTORY = os.path.join(os.path.dirname(os.path.realpath(__file__)), "js")

# First, try to import the model_downloader_patch module
try:
    # Try to import from the current directory
    from .model_downloader_patch import download_model, get_download_progress, list_downloads
    logger.info("Imported model_downloader_patch from custom node directory")
except ImportError:
    # If that fails, try to import from the main app directory
    try:
        # Get the app directory
        app_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
        # Add the app directory to the Python path
        if app_dir not in sys.path:
            sys.path.insert(0, app_dir)
        # Import the module from the app directory
        import model_downloader_patch
        download_model = model_downloader_patch.download_model
        get_download_progress = model_downloader_patch.get_download_progress
        list_downloads = model_downloader_patch.list_downloads
        logger.info("Imported model_downloader_patch from app directory")
    except ImportError as e:
        logger.error(f"Error importing model_downloader_patch: {e}")
        traceback.print_exc()
        # Define dummy functions to avoid errors
        async def download_model(request):
            return web.json_response({"error": "Model downloader not available"})
        async def get_download_progress(request):
            return web.json_response({"error": "Model downloader not available"})
        async def list_downloads(request):
            return web.json_response({"error": "Model downloader not available"})

# Register the API endpoints
try:
    # Import aiohttp web components for response handling
    from aiohttp import web
    from server import PromptServer
    
    # Get the app instance
    app = PromptServer.instance.app
    
    # Define route patterns to check for
    route_patterns = [
        '/api/download-model',
        '/api/download-progress/',
        '/api/downloads'
    ]
    
    # Check if any of our routes already exist
    existing_routes = set()
    for route in app.router.routes():
        route_str = str(route)
        for pattern in route_patterns:
            if pattern in route_str:
                existing_routes.add(pattern)
                logger.info(f"Found existing route matching {pattern}: {route}")
                print(f"[MODEL_DOWNLOADER] Found existing route: {route}")
    
    # Register each endpoint if it doesn't already exist
    if '/api/download-model' not in existing_routes:
        app.router.add_post('/api/download-model', download_model)
        print("[MODEL_DOWNLOADER] Registered /api/download-model endpoint")
    
    if '/api/download-progress/' not in existing_routes:
        app.router.add_get('/api/download-progress/{download_id}', get_download_progress)
        print("[MODEL_DOWNLOADER] Registered /api/download-progress endpoint")
    
    if '/api/downloads' not in existing_routes:
        app.router.add_get('/api/downloads', list_downloads)
        print("[MODEL_DOWNLOADER] Registered /api/downloads endpoint")
    
    # Log success message
    if len(existing_routes) < len(route_patterns):
        logger.info("Model downloader API endpoints registered successfully")
        print("[MODEL_DOWNLOADER] API endpoints successfully registered")
    else:
        logger.info("All model downloader API endpoints were already registered")
        print("[MODEL_DOWNLOADER] All API endpoints were already registered")
    
    # List the registered routes related to downloads
    for route in app.router.routes():
        if 'download' in str(route):
            logger.info(f"Registered route: {route}")
            print(f"[MODEL_DOWNLOADER] Registered route: {route}")
except Exception as e:
    logger.error(f"Error registering API endpoints: {e}")
    print(f"[MODEL_DOWNLOADER] Error registering API endpoints: {e}")
    traceback.print_exc()

print(f"Model Downloader module registered with web directory: {WEB_DIRECTORY}")
