# Model Downloader Custom Node
import os
import sys
from server import PromptServer
from .model_downloader_patch import download_model, get_download_progress, list_downloads

# This node doesn't add any actual nodes to the graph
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

# Register the web extension directory for ComfyUI to find the JavaScript files
WEB_DIRECTORY = os.path.join(os.path.dirname(os.path.realpath(__file__)), "js")

# Register the API endpoints directly when the module is imported
# This ensures they're available as soon as ComfyUI loads the custom node
try:
    app = PromptServer.instance.app
    # Register API endpoints
    app.router.add_post('/api/download-model', download_model)
    app.router.add_get('/api/download-progress/{download_id}', get_download_progress)
    app.router.add_get('/api/downloads', list_downloads)
    print(f"[MODEL_DOWNLOADER] API endpoints successfully registered")
    # List the registered routes related to downloads
    for route in app.router.routes():
        if 'download' in str(route):
            print(f"[MODEL_DOWNLOADER] Registered route: {route}")
except Exception as e:
    import traceback
    print(f"[MODEL_DOWNLOADER] Error registering API endpoints: {e}")
    traceback.print_exc()

print(f"Model Downloader module registered with web directory: {WEB_DIRECTORY}")
