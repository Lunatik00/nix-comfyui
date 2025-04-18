"""
Main entry point for the patches module.

This module initializes and loads all patches in the src/patches directory,
ensuring they are properly applied to ComfyUI.
"""

import os
import sys
import importlib

# Import the custom_node_init module
from . import custom_node_init

def initialize_patches():
    """
    Initialize all patches in the module.
    This ensures all patches are properly applied to ComfyUI.
    """
    print("Initializing patches from src/patches...")
    
    # The custom_node_init patch is primarily loaded via its import above
    # Its setup_js_api function will be called by ComfyUI's server when starting
    
    print("Patches initialization complete")

# Run initialization when imported
initialize_patches()
