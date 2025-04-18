# Path override custom node
# This node ensures proper path persistence

import os
import importlib
import logging

logger = logging.getLogger("path_override")

# Import our path override patch
from . import path_override

# No need to define NODE_CLASS_MAPPINGS since this is just a utility module
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

__all__ = ['NODE_CLASS_MAPPINGS', 'NODE_DISPLAY_NAME_MAPPINGS']

logger.info("Path override module initialized")
