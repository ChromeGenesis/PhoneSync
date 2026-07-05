import time
import sys

start_time = time.time()

def log_time(msg):
    print(f"[{time.time() - start_time:.3f}s] {msg}")

log_time("Starting imports...")
import tkinter as tk
import customtkinter as ctk
import os
import threading
import subprocess

from core.adb_client import auto_connect, get_device_name, list_files_stream, list_recents_stream
from core.config import load_saved_paths, save_custom_path
from ui.sidebar import Sidebar
from ui.file_explorer import FileExplorer

log_time("Imports finished.")

class PerfTestApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        log_time("App initialized. Building UI...")
        
        self.sidebar = Sidebar(self, lambda p: None, lambda: None, [], lambda: None, lambda: None)
        self.explorer = FileExplorer(self, lambda n: None, lambda: None, lambda: None)
        
        log_time("UI built. Starting auto_connect...")
        self.is_connected = False
        threading.Thread(target=self._init_adb, daemon=True).start()

    def _init_adb(self):
        self.is_connected = auto_connect()
        log_time(f"auto_connect finished. Connected: {self.is_connected}")
        
        if self.is_connected:
            self.device_name = get_device_name()
            log_time(f"Got device name: {self.device_name}")
            self.after(0, lambda: self.load_path("RECENTS"))

    def load_path(self, path):
        log_time(f"load_path called with {path}")
        
        def fetch():
            log_time(f"Starting fetch stream for {path}...")
            list_recents_stream(lambda chunk: self.after(0, lambda: self._on_fetch_chunk(chunk, path)))
            
        threading.Thread(target=fetch, daemon=True).start()

    def _on_fetch_chunk(self, chunk, path):
        log_time(f"Got first chunk of size {len(chunk)}!")
        sys.exit(0)

if __name__ == "__main__":
    app = PerfTestApp()
    app.mainloop()
