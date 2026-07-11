import os
import threading
import tempfile
import subprocess
import customtkinter as ctk
from tkinter import filedialog
from PIL import Image

from core.adb_client import (
    auto_connect,
    get_device_name,
    list_files_stream,
    list_recents_stream,
)
from core.config import load_saved_paths, save_custom_path
from ui.sidebar import Sidebar
from ui.file_explorer import FileExplorer

try:
    import pillow_heif

    pillow_heif.register_heif_opener()
except ImportError:
    pass

# ── Design tokens ─────────────────────────────────────────────────────────────
_APP_BG = "#0f1117"
_MAIN_BG = "#0f1117"
_SURFACE = "#141824"
_BORDER = "#1e2540"

_TEXT_PRIMARY = "#dde4f0"
_TEXT_MUTED = "#6b7280"
_ACCENT = "#3b82f6"
_GREEN = "#16a34a"
_GREEN_HOVER = "#15803d"
_RED = "#ef4444"
_AMBER = "#f59e0b"

# Pull button colors
_PULL_FG = "#1e3a5f"
_PULL_HOVER = "#1e4976"
_PULL_TEXT = "#7dd3fc"


class PhoneSyncApp(ctk.CTk):
    def __init__(self):
        super().__init__(className="PhoneSync")
        ctk.set_appearance_mode("dark")
        ctk.set_default_color_theme("blue")

        self.title("PhoneSync")
        self.geometry("1180x780")
        self.minsize(900, 600)
        self.configure(fg_color=_APP_BG)

        # ── Taskbar icon ──────────────────────────────────────────────────────
        try:
            self.wm_class("PhoneSync", "PhoneSync")
            from PIL import ImageTk, Image as PILImage

            if os.path.exists("icon.png"):
                self.iconphoto(True, ImageTk.PhotoImage(PILImage.open("icon.png")))
        except Exception:
            pass

        self.protocol("WM_DELETE_WINDOW", self.hide_window)

        # ── Root grid: sidebar | main ─────────────────────────────────────────
        self.grid_rowconfigure(0, weight=1)
        self.grid_columnconfigure(1, weight=1)

        self.temp_dir = os.path.join(tempfile.gettempdir(), "adb_gui_preview")
        os.makedirs(self.temp_dir, exist_ok=True)

        self.device_name = ""
        self.is_connected = False
        self.current_remote_path = ""

        self.saved_paths = load_saved_paths()
        self.pull_dest_dir = os.path.expanduser("~/Downloads")

        # ── Sidebar ───────────────────────────────────────────────────────────
        self.sidebar = Sidebar(
            self,
            on_path_select=self.load_path,
            on_push_file=self._on_push_file,
            on_push_folder=self._on_push_folder,
            saved_paths=self.saved_paths,
            on_ask_custom_path=self._on_ask_custom_path,
            on_change_dest=self._on_change_dest,
        )
        self.sidebar.grid(row=0, column=0, sticky="nsew")

        # ── Main content area ─────────────────────────────────────────────────
        self.main_frame = ctk.CTkFrame(self, fg_color=_MAIN_BG, corner_radius=0)
        self.main_frame.grid(row=0, column=1, sticky="nsew")
        self.main_frame.grid_rowconfigure(1, weight=1)
        self.main_frame.grid_columnconfigure(0, weight=1)

        # ── Header bar ────────────────────────────────────────────────────────
        self._header = ctk.CTkFrame(
            self.main_frame, fg_color=_SURFACE, corner_radius=0, height=60
        )
        self._header.grid(row=0, column=0, sticky="ew")
        self._header.grid_propagate(False)
        self._header.grid_rowconfigure(0, weight=1)
        self._header.grid_columnconfigure(1, weight=1)

        # Status dot + label
        status_group = ctk.CTkFrame(self._header, fg_color="transparent")
        status_group.grid(row=0, column=0, padx=(20, 0), sticky="w")

        self.status_dot = ctk.CTkLabel(
            status_group,
            text="\u25cf",
            font=ctk.CTkFont(size=10),
            text_color=_AMBER,
            width=14,
        )
        self.status_dot.pack(side="left", padx=(0, 6))

        self.status_label = ctk.CTkLabel(
            status_group,
            text="Connecting\u2026",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color=_TEXT_MUTED,
        )
        self.status_label.pack(side="left")

        # Right: breadcrumb + controls
        right_group = ctk.CTkFrame(self._header, fg_color="transparent")
        right_group.grid(row=0, column=2, padx=(0, 16), sticky="e")

        self.path_label = ctk.CTkLabel(
            right_group,
            text="",
            font=ctk.CTkFont(size=11),
            text_color=_TEXT_MUTED,
        )
        self.path_label.pack(side="left", padx=(0, 14))

        self.btn_refresh = ctk.CTkButton(
            right_group,
            text="\u27f3  Refresh",
            width=92,
            height=32,
            fg_color="#1e2540",
            hover_color="#2d3558",
            text_color="#60a5fa",
            font=ctk.CTkFont(size=12),
            corner_radius=8,
            command=self._refresh,
        )
        self.btn_refresh.pack(side="left")

        # Header bottom border
        ctk.CTkFrame(self.main_frame, fg_color=_BORDER, height=1).grid(
            row=0, column=0, sticky="sew"
        )

        # ── File explorer ─────────────────────────────────────────────────────
        explorer_wrapper = ctk.CTkFrame(self.main_frame, fg_color="transparent")
        explorer_wrapper.grid(row=1, column=0, sticky="nsew", padx=20, pady=(16, 0))
        explorer_wrapper.grid_rowconfigure(0, weight=1)
        explorer_wrapper.grid_columnconfigure(0, weight=1)

        self.explorer = FileExplorer(
            explorer_wrapper,
            temp_dir=self.temp_dir,
            on_preview=self._show_preview,
            on_selection_change=self._on_selection_change,
        )
        self.explorer.grid(row=0, column=0, sticky="nsew")

        # ── Bottom action bar ─────────────────────────────────────────────────
        self._action_bar = ctk.CTkFrame(
            self.main_frame, fg_color=_SURFACE, corner_radius=0, height=68
        )
        self._action_bar.grid(row=2, column=0, sticky="ew")
        self._action_bar.grid_propagate(False)
        self._action_bar.grid_rowconfigure(0, weight=1)
        self._action_bar.grid_columnconfigure(1, weight=1)

        # Top border
        ctk.CTkFrame(self._action_bar, fg_color=_BORDER, height=1).grid(
            row=0, column=0, columnspan=3, sticky="new"
        )

        # Selection count
        self.lbl_selected = ctk.CTkLabel(
            self._action_bar,
            text="No files selected",
            font=ctk.CTkFont(size=12),
            text_color=_TEXT_MUTED,
        )
        self.lbl_selected.grid(row=0, column=0, padx=24, sticky="w")

        # Pull button
        self.btn_pull = ctk.CTkButton(
            self._action_bar,
            text="\u2b07   Pull to Computer",
            width=190,
            height=40,
            fg_color=_PULL_FG,
            hover_color=_PULL_HOVER,
            text_color=_PULL_TEXT,
            font=ctk.CTkFont(size=13, weight="bold"),
            corner_radius=20,
            state="disabled",
            command=self._pull_selected,
        )
        self.btn_pull.grid(row=0, column=2, padx=24, sticky="e")

        # Enter-key shortcut
        self.bind(
            "<Return>",
            lambda e: (
                self._pull_selected()
                if self.btn_pull.cget("state") == "normal"
                else None
            ),
        )

        # ── Boot ──────────────────────────────────────────────────────────────
        threading.Thread(target=self._init_adb, daemon=True).start()
        self._start_background_sync()

    # ── Connection ────────────────────────────────────────────────────────────
    def _init_adb(self):
        def _progress(msg):
            self.after(
                0, lambda: self.status_label.configure(text=msg, text_color=_TEXT_MUTED)
            )
            self.after(0, lambda: self.status_dot.configure(text_color=_AMBER))

        connected = auto_connect(_progress)

        if connected:
            name = get_device_name()
            self.after(0, lambda: self._on_adb_connected(name))
        else:
            self.after(0, self._set_status_disconnected)

    def _set_status_disconnected(self):
        self.status_dot.configure(text_color=_RED)
        self.status_label.configure(text="No device connected", text_color=_TEXT_MUTED)
        self.path_label.configure(text="")

    def _on_adb_connected(self, name: str):
        self.is_connected = True
        self.device_name = name
        self.status_dot.configure(text_color="#10b981")
        self.status_label.configure(
            text=f"Connected  \u2014  {name}", text_color=_TEXT_PRIMARY
        )
        self.load_path("/sdcard/DCIM/Screenshots/")

    def _start_background_sync(self):
        def _worker():
            import time

            while True:
                time.sleep(5)
                if not self.is_connected or not self.current_remote_path:
                    continue
                path = self.current_remote_path
                fetched: list = []

                try:
                    if path == "RECENTS":
                        list_recents_stream(lambda c: fetched.extend(c))
                    else:
                        list_files_stream(path, lambda c: fetched.extend(c))

                    if self.current_remote_path != path:
                        continue

                    cur = self.explorer._f_info_map
                    new_map = {f["name"]: f for f in fetched}
                    changed = len(cur) != len(new_map) or any(
                        n not in cur
                        or cur[n]["size"] != f["size"]
                        or cur[n]["mod_time"] != f["mod_time"]
                        for n, f in new_map.items()
                    )
                    if changed:
                        self.after(
                            0,
                            lambda p=path, ff=fetched: self.explorer.update_files(
                                ff, p
                            ),
                        )
                except Exception:
                    pass

        threading.Thread(target=_worker, daemon=True).start()

    # ── Navigation ────────────────────────────────────────────────────────────
    def load_path(self, path: str):
        if not self.is_connected:
            return

        self.current_remote_path = path
        display = "Recent Media" if path == "RECENTS" else path
        self.path_label.configure(text=f"Loading  {display} \u2026")
        self.explorer.set_files([], path)

        def _fetch():
            cb = lambda chunk: self.after(
                0, lambda c=chunk: self._on_fetch_chunk(c, path)
            )
            if path == "RECENTS":
                list_recents_stream(cb)
            else:
                list_files_stream(path, cb)
            self.after(0, lambda: self.path_label.configure(text=display))

        threading.Thread(target=_fetch, daemon=True).start()

    def _on_fetch_chunk(self, chunk, path):
        if self.current_remote_path == path:
            self.explorer.append_files(chunk, path)

    def _refresh(self):
        if not self.current_remote_path:
            return
        path = self.current_remote_path
        display = "Recent Media" if path == "RECENTS" else path
        self.path_label.configure(text=f"Refreshing  {display} \u2026")

        def _fetch():
            fetched: list = []
            if path == "RECENTS":
                list_recents_stream(lambda c: fetched.extend(c))
            else:
                list_files_stream(path, lambda c: fetched.extend(c))

            if self.current_remote_path == path:
                self.after(0, lambda: self.explorer.update_files(fetched, path))
                self.after(0, lambda: self.path_label.configure(text=display))

        threading.Thread(target=_fetch, daemon=True).start()

    # ── Selection ─────────────────────────────────────────────────────────────
    def _on_selection_change(self):
        n = len(self.explorer.get_selected_files())
        self.lbl_selected.configure(
            text=(
                f"{n} file{'s' if n != 1 else ''} selected"
                if n
                else "No files selected"
            )
        )
        self.btn_pull.configure(state="normal" if n > 0 else "disabled")

    # ── Toast ─────────────────────────────────────────────────────────────────
    def show_toast(self, message: str, duration: int = 3500):
        toast = ctk.CTkFrame(
            self,
            fg_color="#0d1a2e",
            corner_radius=12,
            border_width=1,
            border_color="#1e2d45",
        )
        ctk.CTkLabel(
            toast,
            text=message,
            font=ctk.CTkFont(size=13),
            text_color=_TEXT_PRIMARY,
            wraplength=320,
            justify="center",
        ).pack(padx=20, pady=14)
        toast.place(relx=0.5, rely=0.94, anchor="center")
        self.after(duration, toast.destroy)

    # ── Custom path ───────────────────────────────────────────────────────────
    def _on_ask_custom_path(self):
        dialog = ctk.CTkInputDialog(
            text="Enter remote path (e.g., /sdcard/Movies/):", title="Custom Path"
        )
        path = dialog.get_input()
        if path:
            if not path.endswith("/"):
                path += "/"
            self.saved_paths = save_custom_path(path)
            self.sidebar.update_saved_paths(self.saved_paths, path)
            self.load_path(path)

    # ── File pickers ──────────────────────────────────────────────────────────
    def _zenity_askopenfilenames(self, title: str):
        try:
            res = subprocess.run(
                [
                    "zenity",
                    "--file-selection",
                    "--multiple",
                    "--separator=|",
                    f"--title={title}",
                ],
                capture_output=True,
                text=True,
            )
            if res.returncode == 0 and res.stdout.strip():
                return res.stdout.strip().split("|")
        except Exception:
            pass
        return filedialog.askopenfilenames(title=title)

    def _zenity_askdirectory(self, title: str, initialdir):
        try:
            cmd = ["zenity", "--file-selection", "--directory", f"--title={title}"]
            if initialdir:
                cmd.append(f"--filename={initialdir}/")
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode == 0 and res.stdout.strip():
                return res.stdout.strip()
        except Exception:
            pass
        return filedialog.askdirectory(title=title, initialdir=initialdir)

    # ── Tray ──────────────────────────────────────────────────────────────────
    def hide_window(self):
        self.withdraw()
        if not hasattr(self, "tray_icon"):
            try:
                import pystray

                img = Image.new("RGB", (64, 64), color=(73, 109, 137))
                if os.path.exists("icon.png"):
                    img = Image.open("icon.png")

                menu = pystray.Menu(
                    pystray.MenuItem("Open Manager", self.show_window, default=True),
                    pystray.MenuItem("Quit", self.quit_app),
                )
                self.tray_icon = pystray.Icon("PhoneSync", img, "PhoneSync", menu)
                threading.Thread(target=self.tray_icon.run, daemon=True).start()
            except ImportError:
                self.destroy()

    def show_window(self, icon, item):
        if hasattr(self, "tray_icon"):
            self.tray_icon.stop()
            delattr(self, "tray_icon")
        self.after(0, self.deiconify)

    def quit_app(self, icon, item):
        if hasattr(self, "tray_icon"):
            self.tray_icon.stop()
        self.after(0, self.destroy)

    # ── Pull ──────────────────────────────────────────────────────────────────
    def _pull_selected(self):
        selected_paths = self.explorer.get_selected_files()
        if not selected_paths:
            return

        dest_dir = self.pull_dest_dir
        self.btn_pull.configure(state="disabled", text="Pulling\u2026")

        def _do():
            ok = 0
            total = len(selected_paths)
            for i, rp in enumerate(selected_paths, 1):
                self.after(
                    0,
                    lambda i=i, t=total: self.btn_pull.configure(
                        text=f"Pulling {i}/{t}\u2026"
                    ),
                )
                try:
                    subprocess.run(
                        ["adb", "pull", rp, dest_dir], check=True, capture_output=True
                    )
                    ok += 1
                except Exception:
                    pass
            self.after(0, lambda: self._pull_done(ok, total, dest_dir))

        threading.Thread(target=_do, daemon=True).start()

    def _pull_done(self, success: int, total: int, dest_dir: str):
        self.btn_pull.configure(state="normal", text="\u2b07   Pull to Computer")
        self.explorer.deselect_all()
        self.show_toast(f"Pulled {success}/{total} files\n\u2192 {dest_dir}", 4000)

    def _on_change_dest(self):
        dest = self._zenity_askdirectory(
            title="Select Save Location", initialdir=self.pull_dest_dir
        )
        if dest:
            self.pull_dest_dir = dest
            self.show_toast(f"Pull destination set to\n{dest}")

    # ── Push ──────────────────────────────────────────────────────────────────
    def _on_push_file(self):
        file_paths = self._zenity_askopenfilenames(title="Select Files to Push")
        if not file_paths:
            return

        dest = "/sdcard/Download/"
        self.sidebar.btn_push.configure(state="disabled", text="Pushing\u2026")

        def _do():
            ok = 0
            total = len(file_paths)
            for i, fp in enumerate(file_paths, 1):
                self.after(
                    0,
                    lambda i=i, t=total: self.sidebar.btn_push.configure(
                        text=f"\u2b06  {i}/{t}\u2026"
                    ),
                )
                try:
                    subprocess.run(
                        ["adb", "push", fp, dest], check=True, capture_output=True
                    )
                    ok += 1
                except Exception:
                    pass
            self.after(0, lambda: self._push_done(ok, total))

        threading.Thread(target=_do, daemon=True).start()

    def _push_done(self, success: int, total: int):
        self.sidebar.btn_push.configure(state="normal", text="\u2b06  Push Files")
        self.show_toast(
            f"Pushed {success}/{total} files\n\u2192 /sdcard/Download/", 4000
        )

    def _on_push_folder(self):
        dir_path = self._zenity_askdirectory(
            title="Select Folder to Push", initialdir=None
        )
        if not dir_path:
            return

        dest = "/sdcard/Download/"
        self.sidebar.btn_push_folder.configure(state="disabled", text="Pushing\u2026")

        def _do():
            try:
                subprocess.run(
                    ["adb", "push", dir_path, dest], check=True, capture_output=True
                )
                ok = True
            except Exception:
                ok = False
            self.after(
                0, lambda: self._push_folder_done(ok, os.path.basename(dir_path))
            )

        threading.Thread(target=_do, daemon=True).start()

    def _push_folder_done(self, success: bool, folder_name: str):
        self.sidebar.btn_push_folder.configure(
            state="normal", text="\U0001f4c2  Push Folder"
        )
        if success:
            self.show_toast(
                f"Pushed folder '{folder_name}'\n\u2192 /sdcard/Download/", 4000
            )
        else:
            self.show_toast(f"Failed to push folder '{folder_name}'", 4000)

    # ── Send text / link ──────────────────────────────────────────────────────
    def send_text_or_link(self):
        dialog = ctk.CTkInputDialog(
            text="Enter text or URL to send to phone:", title="Send to Phone"
        )
        data = dialog.get_input()
        if not data:
            return

        data = data.strip()

        def _task():
            if data.startswith(("http://", "https://", "www.")):
                url = data if data.startswith("http") else "https://" + data
                subprocess.run(
                    [
                        "adb",
                        "shell",
                        "am",
                        "start",
                        "-a",
                        "android.intent.action.VIEW",
                        "-d",
                        url,
                    ],
                    capture_output=True,
                )
                self.after(0, lambda: self.show_toast("Link opened on phone!"))
            else:
                safe = data.replace("'", "'\\''")
                subprocess.run(
                    [
                        "adb",
                        "shell",
                        "am",
                        "start",
                        "-a",
                        "android.intent.action.SEND",
                        "-t",
                        "text/plain",
                        "-e",
                        "android.intent.extra.TEXT",
                        f"'{safe}'",
                    ],
                    capture_output=True,
                )
                self.after(0, lambda: self.show_toast("Share menu opened on phone!"))

        threading.Thread(target=_task, daemon=True).start()

    # ── Preview ───────────────────────────────────────────────────────────────
    def _show_preview(self, full_remote_path: str):
        filename = full_remote_path.split("/")[-1]
        local_file = os.path.join(self.temp_dir, filename)

        prev_win = ctk.CTkToplevel(self)
        prev_win.title(f"Preview \u2014 {filename}")
        prev_win.geometry("640x640")
        prev_win.configure(fg_color=_DARK["main_bg"])

        spinner = ctk.CTkLabel(
            prev_win,
            text="Fetching preview\u2026",
            font=ctk.CTkFont(size=14),
            text_color=_TEXT_MUTED,
        )
        spinner.pack(expand=True)

        def _pull_and_show():
            try:
                if not os.path.exists(local_file):
                    subprocess.run(
                        ["adb", "pull", full_remote_path, local_file],
                        check=True,
                        capture_output=True,
                    )
                img = Image.open(local_file)
                img.thumbnail((600, 600), Image.Resampling.LANCZOS)
                ctk_img = ctk.CTkImage(light_image=img, dark_image=img, size=img.size)
                self.after(0, lambda: _show_img(ctk_img))
            except Exception as e:
                self.after(
                    0, lambda: spinner.configure(text=f"Preview unavailable\n{e}")
                )

        def _show_img(ctk_img):
            spinner.destroy()
            ctk.CTkLabel(prev_win, text="", image=ctk_img).pack(
                expand=True, padx=16, pady=16
            )

        threading.Thread(target=_pull_and_show, daemon=True).start()
