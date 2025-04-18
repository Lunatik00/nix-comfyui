#!/usr/bin/env python3
"""
Persistence package for ComfyUI
This package handles persistence of models, outputs, and other user data
"""

from .persistence import setup_persistence, patch_folder_paths

__all__ = ['setup_persistence', 'patch_folder_paths']
