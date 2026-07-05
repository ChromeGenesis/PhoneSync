import os
import threading
import tempfile
import subprocess
import customtkinter as ctk
from tkinter import filedialog
from PIL import Image

from core.adb_client import auto_connect, get_device_name, list_files_stream, list_recents_stream
from core.config import load_saved_paths, save_custom_path
from ui.sidebar import Sidebar
from ui.file_explorer import FileExplorer

try:
    import pillow_heif
    pillow_heif.register_heif_opener()
except ImportError:
    pass

class PhoneSyncApp(ctk.CTk):
    def __init__(self):
        super().__init__(className="PhoneSync")

        self.title("Phone Sync Manager")
        self.geometry("1000x700")
        
        # Set Linux taskbar icon and WM_CLASS
        try:
            self.wm_class("PhoneSync", "PhoneSync")
            from PIL import ImageTk, Image
            if os.path.exists("icon.png"):
                img = ImageTk.PhotoImage(Image.open("icon.png"))
                self.iconphoto(True, img)
        except Exception:
            pass
            
        self.protocol("WM_DELETE_WINDOW", self.hide_window)

        self.grid_rowconfigure(0, weight=1)
        self.grid_columnconfigure(1, weight=1)

        self.temp_dir = os.path.join(tempfile.gettempdir(), "adb_gui_preview")
        os.makedirs(self.temp_dir, exist_ok=True)
        
        self.device_name = "Connecting..."
        self.is_connected = False

        # Build UI
        self.saved_paths = load_saved_paths()
        self.pull_dest_dir = os.path.expanduser("~/Downloads")
        
        self.sidebar = Sidebar(self, 
                               on_path_select=self.load_path, 
                               on_push_file=self._on_push_file,
                               saved_paths=self.saved_paths,
                               on_ask_custom_path=self._on_ask_custom_path,
                               on_change_dest=self._on_change_dest)
        self.sidebar.grid(row=0, column=0, sticky="nsew")

        # Main frame wrapper
        self.main_wrapper = ctk.CTkFrame(self)
        self.main_wrapper.grid(row=0, column=1, padx=20, pady=20, sticky="nsew")
        self.main_wrapper.grid_rowconfigure(1, weight=1)
        self.main_wrapper.grid_columnconfigure(0, weight=1)

        # Top Bar (Header)
        self.top_bar = ctk.CTkFrame(self.main_wrapper, fg_color="transparent")
        self.top_bar.grid(row=0, column=0, sticky="ew", pady=(0, 10))
        self.top_bar.grid_columnconfigure(0, weight=1)

        self.path_label = ctk.CTkLabel(self.top_bar, text=f"Path to [{self.device_name}]: None", font=ctk.CTkFont(size=14, weight="bold"))
        self.path_label.grid(row=0, column=0, sticky="w")

        self.btn_refresh = ctk.CTkButton(self.top_bar, text="Refresh", width=80, command=self._refresh)
        self.btn_refresh.grid(row=0, column=1, padx=10)

        # File Explorer Area
        self.explorer = FileExplorer(self.main_wrapper, 
                                     temp_dir=self.temp_dir, 
                                     on_preview=self._show_preview,
                                     on_selection_change=self._on_selection_change)
        self.explorer.grid(row=1, column=0, sticky="nsew")

        self.current_remote_path = ""
        
        # Bottom controls for Pulling
        self.bottom_pull_bar = ctk.CTkFrame(self.main_wrapper, fg_color="transparent")
        self.bottom_pull_bar.grid(row=2, column=0, sticky="ew", pady=(10, 0))
        
        self.lbl_selected = ctk.CTkLabel(self.bottom_pull_bar, text="0 files selected")
        self.lbl_selected.pack(side="left")
        
        self.btn_pull = ctk.CTkButton(self.bottom_pull_bar, text="Pull Selected Files", command=self._pull_selected, state="disabled")
        self.btn_pull.pack(side="right")

        # Start connection in background
        threading.Thread(target=self._init_adb, daemon=True).start()
        self._start_background_sync()

    def _start_background_sync(self):
        def _sync_worker():
            import time
            while True:
                time.sleep(5)
                if not self.is_connected or not self.current_remote_path:
                    continue
                
                path = self.current_remote_path
                fetched_files = []
                
                def _bg_chunk(chunk):
                    fetched_files.extend(chunk)
                    
                try:
                    from core.adb_client import list_files_stream, list_recents_stream
                    if path == "RECENTS":
                        list_recents_stream(_bg_chunk)
                    else:
                        list_files_stream(path, _bg_chunk)
                        
                    if self.current_remote_path == path:
                        # Diff check before updating UI thread
                        current_map = self.explorer._f_info_map
                        new_map = {f['name']: f for f in fetched_files}
                        
                        changed = False
                        if len(current_map) != len(new_map):
                            changed = True
                        else:
                            for name, f in new_map.items():
                                if name not in current_map:
                                    changed = True
                                    break
                                old_f = current_map[name]
                                if f['size'] != old_f['size'] or f['mod_time'] != old_f['mod_time']:
                                    changed = True
                                    break
                                    
                        if changed:
                            self.after(0, lambda p=path, ff=fetched_files: self.explorer.update_files(ff, p))
                except Exception:
                    pass

        threading.Thread(target=_sync_worker, daemon=True).start()

    def _init_adb(self):
        def on_progress(msg):
            self.after(0, lambda: self.path_label.configure(text=msg))
            
        connected = auto_connect(on_progress)
        
        if connected:
            name = get_device_name()
            self.after(0, lambda: self._on_adb_connected(name))
        else:
            self.after(0, lambda: self.path_label.configure(text="Failed to connect to any device."))

    def _on_adb_connected(self, name):
        self.is_connected = True
        self.device_name = name
        self.path_label.configure(text=f"Path to [{self.device_name}]: {self.current_remote_path}")
        # Initial load after connection
        self.load_path("/sdcard/DCIM/Screenshots/")

    def _refresh(self):
        if self.current_remote_path:
            # Doing a background fetch and then update_files to not clear UI
            path = self.current_remote_path
            display_path = "Recent Media" if path == "RECENTS" else path
            self.path_label.configure(text=f"Refreshing [{self.device_name}]: {display_path} ...")
            
            def fetch():
                fetched_files = []
                from core.adb_client import list_files_stream, list_recents_stream
                if path == "RECENTS":
                    list_recents_stream(lambda chunk: fetched_files.extend(chunk))
                else:
                    list_files_stream(path, lambda chunk: fetched_files.extend(chunk))
                
                if self.current_remote_path == path:
                    self.after(0, lambda p=path, ff=fetched_files: self.explorer.update_files(ff, p))
                    self.after(0, lambda dp=display_path: self.path_label.configure(text=f"Path to [{self.device_name}]: {dp}"))
                    
            threading.Thread(target=fetch, daemon=True).start()

    def _on_selection_change(self):
        selected = self.explorer.get_selected_files()
        count = len(selected)
        self.lbl_selected.configure(text=f"{count} files selected")
        self.btn_pull.configure(state="normal" if count > 0 else "disabled")

    def _on_ask_custom_path(self):
        dialog = ctk.CTkInputDialog(text="Enter remote path (e.g., /sdcard/Movies/):", title="Custom Path")
        path = dialog.get_input()
        if path:
            if not path.endswith('/'):
                path += '/'
            
            self.saved_paths = save_custom_path(path)
            self.sidebar.update_saved_paths(self.saved_paths, path)
            self.load_path(path)

    def show_toast(self, message: str, duration: int = 3000):
        toast = ctk.CTkLabel(self, text=message, fg_color="gray30", corner_radius=8, padx=15, pady=10, font=ctk.CTkFont(size=14))
        toast.place(relx=0.5, rely=0.9, anchor="center")
        self.after(duration, toast.destroy)
    def send_text_or_link(self):
        dialog = ctk.CTkInputDialog(text="Enter text or URL to send to phone:", title="Send to Phone")
        data = dialog.get_input()
        if not data:
            return
            
        data = data.strip()
        def _task():
            import subprocess
            if data.startswith("http://") or data.startswith("https://") or data.startswith("www."):
                url = data if data.startswith("http") else "https://" + data
                subprocess.run(["adb", "shell", "am", "start", "-a", "android.intent.action.VIEW", "-d", url], capture_output=True)
                self.after(0, lambda: self.show_toast("Link opened on phone!"))
            else:
                # Need to properly escape single quotes for the shell command
                safe_data = data.replace("'", "'\\''")
                subprocess.run(["adb", "shell", "am", "start", "-a", "android.intent.action.SEND", "-t", "text/plain", "-e", "android.intent.extra.TEXT", f"'{safe_data}'"], capture_output=True)
                self.after(0, lambda: self.show_toast("Share menu opened on phone!"))
                
        threading.Thread(target=_task, daemon=True).start()

    def _zenity_askopenfilenames(self, title):
        try:
            import subprocess
            res = subprocess.run(["zenity", "--file-selection", "--multiple", "--separator=|", f"--title={title}"], capture_output=True, text=True)
            if res.returncode == 0 and res.stdout.strip():
                return res.stdout.strip().split("|")
        except Exception:
            pass
        return filedialog.askopenfilenames(title=title)

    def _zenity_askdirectory(self, title, initialdir):
        try:
            import subprocess
            cmd = ["zenity", "--file-selection", "--directory", f"--title={title}"]
            if initialdir:
                cmd.append(f"--filename={initialdir}/")
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode == 0 and res.stdout.strip():
                return res.stdout.strip()
        except Exception:
            pass
        return filedialog.askdirectory(title=title, initialdir=initialdir)

    def hide_window(self):
        self.withdraw()
        if not hasattr(self, 'tray_icon'):
            try:
                import pystray
                from PIL import Image
                img = Image.new('RGB', (64, 64), color=(73, 109, 137))
                if os.path.exists("icon.png"):
                    img = Image.open("icon.png")
                    
                menu = pystray.Menu(
                    pystray.MenuItem("Open Manager", self.show_window, default=True),
                    pystray.MenuItem("Quit", self.quit_app)
                )
                self.tray_icon = pystray.Icon("PhoneSync", img, "Phone Sync Manager", menu)
                threading.Thread(target=self.tray_icon.run, daemon=True).start()
            except ImportError:
                self.destroy()
        
    def show_window(self, icon, item):
        if hasattr(self, 'tray_icon'):
            self.tray_icon.stop()
            delattr(self, 'tray_icon')
        self.after(0, self.deiconify)
        
    def quit_app(self, icon, item):
        if hasattr(self, 'tray_icon'):
            self.tray_icon.stop()
        self.after(0, self.destroy)



    def _on_change_dest(self):
        dest = self._zenity_askdirectory(title="Select Save Location", initialdir=self.pull_dest_dir)
        if dest:
            self.pull_dest_dir = dest
            self.show_toast(f"Files will now be pulled to:\n{dest}")

    def load_path(self, path: str):
        if not self.is_connected:
            return
            
        self.current_remote_path = path
        display_path = "Recent Media" if path == "RECENTS" else path
        self.path_label.configure(text=f"Loading from [{self.device_name}]: {display_path} ...")
        
        self.explorer.set_files([], path)  # Clear current

        def fetch():
            from core.adb_client import list_files_stream, list_recents_stream
            if path == "RECENTS":
                list_recents_stream(lambda chunk: self.after(0, lambda: self._on_fetch_chunk(chunk, path)))
            else:
                list_files_stream(path, lambda chunk: self.after(0, lambda: self._on_fetch_chunk(chunk, path)))
            
            self.after(0, lambda: self.path_label.configure(text=f"Path to [{self.device_name}]: {display_path}"))
            
        threading.Thread(target=fetch, daemon=True).start()

    def _on_fetch_chunk(self, chunk, path):
        # We append to explorer. Ensure the path matches to prevent race conditions if user clicked another folder quickly
        if self.current_remote_path == path:
            self.explorer.append_files(chunk, path)

    def _show_preview(self, full_remote_path: str):
        filename = full_remote_path.split('/')[-1]
        local_file = os.path.join(self.temp_dir, filename)

        prev_win = ctk.CTkToplevel(self)
        prev_win.title(f"Preview: {filename}")
        prev_win.geometry("600x600")
        
        lbl = ctk.CTkLabel(prev_win, text="Pulling file for full preview...")
        lbl.pack(expand=True)

        def _pull_and_show():
            try:
                if not os.path.exists(local_file):
                    subprocess.run(["adb", "pull", full_remote_path, local_file], check=True, capture_output=True)
                try:
                    img = Image.open(local_file)
                    img.thumbnail((550, 550), Image.Resampling.LANCZOS)
                    ctk_img = ctk.CTkImage(light_image=img, dark_image=img, size=img.size)
                    self.after(0, lambda: _show_img(ctk_img))
                except Exception as e:
                    err_msg = str(e)
                    self.after(0, lambda: _show_error(f"Preview not available for this file type.\n{err_msg}"))
            except Exception as e:
                err_msg = str(e)
                self.after(0, lambda: _show_error(f"Failed to pull file: {err_msg}"))

        def _show_img(ctk_img):
            lbl.destroy()
            img_lbl = ctk.CTkLabel(prev_win, text="", image=ctk_img)
            img_lbl.pack(expand=True, padx=10, pady=10)

        def _show_error(msg):
            lbl.configure(text=msg)

        threading.Thread(target=_pull_and_show, daemon=True).start()

    def _pull_selected(self):
        # selected is now a list of full remote paths
        selected_paths = self.explorer.get_selected_files()
        if not selected_paths:
            return

        dest_dir = self.pull_dest_dir
        self.btn_pull.configure(state="disabled", text="Pulling...")

        def _do_pull():
            success_count = 0
            total = len(selected_paths)
            for idx, remote_file in enumerate(selected_paths, 1):
                self.after(0, lambda i=idx, t=total: self.btn_pull.configure(text=f"Pulling {i}/{t}..."))
                try:
                    subprocess.run(["adb", "pull", remote_file, dest_dir], check=True, capture_output=True)
                    success_count += 1
                except Exception:
                    pass
            self.after(0, lambda: self._pull_done(success_count, total, dest_dir))

        threading.Thread(target=_do_pull, daemon=True).start()

    def _pull_done(self, success: int, total: int, dest_dir: str):
        self.btn_pull.configure(state="normal", text="Pull Selected Files")
        self.explorer.deselect_all()
        self.show_toast(f"Successfully pulled {success}/{total} files to\n{dest_dir}", 4000)

    def _on_push_file(self):
        file_paths = self._zenity_askopenfilenames(title="Select Files to Push")
        if not file_paths:
            return

        dest = "/sdcard/Download/"
        self.sidebar.btn_push.configure(state="disabled", text="Pushing...")

        def _do_push():
            success = 0
            total = len(file_paths)
            for idx, f in enumerate(file_paths, 1):
                self.after(0, lambda i=idx, t=total: self.sidebar.btn_push.configure(text=f"Pushing {i}/{t}..."))
                try:
                    subprocess.run(["adb", "push", f, dest], check=True, capture_output=True)
                    success += 1
                except Exception:
                    pass
            self.after(0, lambda: self._push_done(success, total))
            
        threading.Thread(target=_do_push, daemon=True).start()
        
    def _push_done(self, success: int, total: int):
        self.sidebar.btn_push.configure(state="normal", text="Push File to Phone")
        self.show_toast(f"Successfully pushed {success}/{total} files to /sdcard/Download/", 4000)
