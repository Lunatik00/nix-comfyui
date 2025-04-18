# Model Downloader Custom Node
import os
import sys
import shutil
import folder_paths
from aiohttp import web
from server import PromptServer

# This node doesn't add any actual nodes to the graph
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

# Import our model downloader patch
from ..custom_nodes.model_downloader import model_downloader_patch

# Register the web extension
WEB_DIRECTORY = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "custom_nodes/model_downloader/js")

# Ensure the js directory exists
if not os.path.exists(WEB_DIRECTORY):
    os.makedirs(WEB_DIRECTORY, exist_ok=True)

# Register the API endpoint
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
        app.router.add_post('/api/download-model', model_downloader_patch.download_model)
        
        print("[MODEL_DOWNLOADER] API endpoint registered at /api/download-model")
        print("[MODEL_DOWNLOADER] All registered routes:")
        for route in app.router.routes():
            print(f"[MODEL_DOWNLOADER]   {route}")
    except Exception as e:
        print(f"[MODEL_DOWNLOADER] Error registering API endpoint: {e}")
        import traceback
        traceback.print_exc()
    
    # Log that the patch has been applied
    print("[MODEL_DOWNLOADER] Model downloader patch applied successfully")
    
    return app

# API endpoints are now registered directly in the model_downloader/__init__.py file
# This file exists only for backwards compatibility and to ensure
# the custom node JS files are correctly served

print(f"Model Downloader patch loaded successfully from {WEB_DIRECTORY}")
