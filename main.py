#!/usr/bin/env python3
import os

# Change to the directory of the script to ensure imports work correctly when double-clicked from anywhere
os.chdir(os.path.dirname(os.path.abspath(__file__)))

from utils.subprocess_wrapper import patch_subprocess

patch_subprocess()

from ui.app import PhoneSyncApp

if __name__ == "__main__":
    app = PhoneSyncApp()
    app.mainloop()
