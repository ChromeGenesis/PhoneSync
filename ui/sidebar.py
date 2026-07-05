import customtkinter as ctk
from typing import Callable, List

class Sidebar(ctk.CTkFrame):
    def __init__(self, master, on_path_select: Callable[[str], None], on_push_file: Callable[[], None], saved_paths: List[str], on_ask_custom_path: Callable[[], None], on_change_dest: Callable[[], None]):
        super().__init__(master, width=220, corner_radius=0)
        self.grid_rowconfigure(9, weight=1)
        
        self.on_path_select = on_path_select
        
        self.logo_label = ctk.CTkLabel(self, text="Phone Sync", font=ctk.CTkFont(size=20, weight="bold"))
        self.logo_label.grid(row=0, column=0, padx=20, pady=(20, 10))

        self.btn_recents = ctk.CTkButton(self, text="Recents", command=lambda: self.on_path_select("RECENTS"))
        self.btn_recents.grid(row=1, column=0, padx=20, pady=(10, 10))

        self.btn_screenshots = ctk.CTkButton(self, text="Screenshots", command=lambda: self.on_path_select("SCREENSHOTS"))
        self.btn_screenshots.grid(row=2, column=0, padx=20, pady=10)

        self.btn_downloads = ctk.CTkButton(self, text="Downloads", command=lambda: self.on_path_select("/sdcard/Download/"))
        self.btn_downloads.grid(row=3, column=0, padx=20, pady=10)

        self.btn_camera = ctk.CTkButton(self, text="Camera", command=lambda: self.on_path_select("/sdcard/DCIM/Camera/"))
        self.btn_camera.grid(row=4, column=0, padx=20, pady=10)
        
        self.btn_custom = ctk.CTkButton(self, text="New Custom Path", command=on_ask_custom_path)
        self.btn_custom.grid(row=5, column=0, padx=20, pady=10)
        
        self.saved_paths_label = ctk.CTkLabel(self, text="Saved Custom Paths:")
        self.saved_paths_label.grid(row=6, column=0, padx=20, pady=(15, 0))
        
        opts = saved_paths if saved_paths else ["No saved paths"]
        self.saved_paths_menu = ctk.CTkOptionMenu(self, values=opts, command=self._on_saved_path_select)
        self.saved_paths_menu.grid(row=7, column=0, padx=20, pady=5)
        
        self.btn_change_dest = ctk.CTkButton(self, text="Set Save Location", fg_color="gray", hover_color="darkgray", command=on_change_dest)
        self.btn_change_dest.grid(row=8, column=0, padx=20, pady=20)

        self.btn_push = ctk.CTkButton(self, text="Push File to Phone", fg_color="green", hover_color="darkgreen", command=on_push_file)
        self.btn_push.grid(row=10, column=0, padx=20, pady=10)
        
        self.btn_send_text = ctk.CTkButton(self, text="Send Text / Link", fg_color="#3b82f6", hover_color="#2563eb", command=lambda: getattr(master, "send_text_or_link", lambda: None)())
        self.btn_send_text.grid(row=11, column=0, padx=20, pady=10)
        
    def _on_saved_path_select(self, path: str):
        if path != "No saved paths":
            self.on_path_select(path)
            
    def update_saved_paths(self, new_paths: List[str], current_path: str):
        self.saved_paths_menu.configure(values=new_paths)
        if current_path in new_paths:
            self.saved_paths_menu.set(current_path)
