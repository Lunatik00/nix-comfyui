# Path override custom node
# This node ensures proper path persistence

import logging
from . import path_override

logger = logging.getLogger("path_override")
logger.info("Path override module initialized")

# Required for custom nodes in ComfyUI
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

__all__ = ['NODE_CLASS_MAPPINGS', 'NODE_DISPLAY_NAME_MAPPINGS']
