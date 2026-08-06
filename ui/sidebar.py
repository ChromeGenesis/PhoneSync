import customtkinter as ctk
from typing import Callable, List
from core.config import load_saved_paths, save_custom_path, delete_saved_path

# ── Design tokens ─────────────────────────────────────────────────────────────
_SIDEBAR_BG = "#0f1117"
_NAV_HOVER_BG = "#181c27"
_NAV_ACTIVE_BG = "#1e2230"
_NAV_TEXT = "#a0a8c0"
_NAV_ACTIVE_TEXT = "#ffffff"
_NAV_ACCENT = "#3b82f6"
_SECTION_COLOR = "#4a5070"
_BTN_GREEN = "#16a34a"
_BTN_GREEN_HOVER = "#15803d"
_BTN_BLUE = "#2563eb"
_BTN_BLUE_HOVER = "#1d4ed8"
_BTN_GRAY = "#1e2230"
_BTN_GRAY_HOVER = "#252b3b"


class _NavItem(ctk.CTkFrame):
    """Single icon + label navigation row."""

    def __init__(self, master, icon: str, label: str, on_click: Callable):
        super().__init__(
            master, fg_color="transparent", corner_radius=8, cursor="hand2"
        )
        self.grid_columnconfigure(1, weight=1)
        self._on_click = on_click
        self._active = False

        self._icon = ctk.CTkLabel(
            self,
            text=icon,
            font=ctk.CTkFont(size=15),
            text_color=_NAV_TEXT,
            width=26,
            anchor="center",
        )
        self._icon.grid(row=0, column=0, padx=(12, 6), pady=7)

        self._label = ctk.CTkLabel(
            self,
            text=label,
            font=ctk.CTkFont(size=13),
            text_color=_NAV_TEXT,
            anchor="w",
        )
        self._label.grid(row=0, column=1, sticky="ew", padx=(0, 10), pady=7)

        for w in (self, self._icon, self._label):
            w.bind("<Enter>", self._enter)
            w.bind("<Leave>", self._leave)
            w.bind("<Button-1>", self._press)

    def set_active(self, active: bool):
        self._active = active
        if active:
            self.configure(fg_color=_NAV_ACTIVE_BG)
            self._icon.configure(text_color=_NAV_ACCENT)
            self._label.configure(
                text_color=_NAV_ACTIVE_TEXT, font=ctk.CTkFont(size=13, weight="bold")
            )
        else:
            self.configure(fg_color="transparent")
            self._icon.configure(text_color=_NAV_TEXT)
            self._label.configure(text_color=_NAV_TEXT, font=ctk.CTkFont(size=13))

    def _enter(self, _=None):
        if not self._active:
            self.configure(fg_color=_NAV_HOVER_BG)

    def _leave(self, _=None):
        if not self._active:
            self.configure(fg_color="transparent")

    def _press(self, _=None):
        self._on_click()


class _Section(ctk.CTkLabel):
    def __init__(self, master, text: str):
        super().__init__(
            master,
            text=text.upper(),
            font=ctk.CTkFont(size=9, weight="bold"),
            text_color=_SECTION_COLOR,
            anchor="w",
        )


def _action_btn(
    master, text: str, icon: str = "", fg=_BTN_GRAY, hover=_BTN_GRAY_HOVER, **kw
):
    label = f"{icon}  {text}" if icon else text
    return ctk.CTkButton(
        master,
        text=label,
        fg_color=fg,
        hover_color=hover,
        text_color="#c8d4e8",
        font=ctk.CTkFont(size=12, weight="bold"),
        corner_radius=8,
        height=36,
        anchor="w",
        **kw,
    )


class PathsManagerDialog(ctk.CTkToplevel):
    """Modal dialog for managing saved custom paths (add / delete) with phone folder auto-suggestions."""

    def __init__(self, master, saved_paths: List[str], on_change: Callable, discovered_paths: List[str] | None = None):
        super().__init__(master)
        self.title("Manage Saved Paths")
        self.geometry("540x520")
        self.resizable(False, False)
        self.configure(fg_color="#0f1117")

        self.on_change = on_change
        self.paths: List[str] = list(saved_paths)
        self.discovered_paths: List[str] = list(discovered_paths) if discovered_paths else [
            "/sdcard/DCIM/", "/sdcard/Download/", "/sdcard/Pictures/",
            "/sdcard/Music/", "/sdcard/Movies/", "/sdcard/Documents/", "/sdcard/WhatsApp/"
        ]

        self.grid_rowconfigure(1, weight=1)
        self.grid_columnconfigure(0, weight=1)

        # ── Header ────────────────────────────────────────────────────────────
        header = ctk.CTkFrame(self, fg_color="#141824", corner_radius=0, height=52)
        header.grid(row=0, column=0, sticky="ew")
        header.grid_propagate(False)
        header.grid_columnconfigure(0, weight=1)
        header.grid_rowconfigure(0, weight=1)

        ctk.CTkLabel(
            header,
            text="📁  Manage Phone Paths",
            font=ctk.CTkFont(size=15, weight="bold"),
            text_color="#e8edf5",
        ).grid(row=0, column=0, padx=20, sticky="w")

        # ── Middle scrollable container ───────────────────────────────────────
        self.main_scroll = ctk.CTkScrollableFrame(
            self, fg_color="transparent", scrollbar_button_color="#1e2540"
        )
        self.main_scroll.grid(row=1, column=0, sticky="nsew", padx=16, pady=12)
        self.main_scroll.grid_columnconfigure(0, weight=1)

        # Discovered Folders Section
        _Section(self.main_scroll, "Detected Phone Folders (/sdcard/)").grid(
            row=0, column=0, sticky="w", pady=(4, 6)
        )
        
        disc_frame = ctk.CTkFrame(self.main_scroll, fg_color="#141824", corner_radius=8)
        disc_frame.grid(row=1, column=0, sticky="ew", pady=(0, 16))
        disc_frame.grid_columnconfigure(0, weight=1)

        chips_inner = ctk.CTkFrame(disc_frame, fg_color="transparent")
        chips_inner.pack(fill="x", padx=10, pady=10)

        # Render chips for discovered folders
        chips_inner.grid_columnconfigure((0, 1, 2), weight=1)
        r, c = 0, 0
        for dp in self.discovered_paths:
            short_name = dp.rstrip("/").split("/")[-1]
            btn = ctk.CTkButton(
                chips_inner,
                text=f"+ {short_name}",
                font=ctk.CTkFont(size=11, weight="bold"),
                fg_color="#1e293b",
                hover_color="#334155",
                text_color="#38bdf8",
                height=28,
                corner_radius=14,
                command=lambda p=dp: self._quick_add_path(p),
            )
            btn.grid(row=r, column=c, padx=4, pady=4, sticky="ew")
            c += 1
            if c > 2:
                c = 0
                r += 1

        # Saved Paths Section
        _Section(self.main_scroll, "Saved Custom Paths").grid(
            row=2, column=0, sticky="w", pady=(4, 6)
        )

        self.list_frame = ctk.CTkFrame(self.main_scroll, fg_color="transparent")
        self.list_frame.grid(row=3, column=0, sticky="ew")
        self.list_frame.grid_columnconfigure(0, weight=1)

        self._row_widgets: List[dict] = []
        self._rebuild_list()

        # ── Add new path footer ───────────────────────────────────────────────
        add_frame = ctk.CTkFrame(self, fg_color="#141824", corner_radius=0, height=70)
        add_frame.grid(row=2, column=0, sticky="ew")
        add_frame.grid_propagate(False)
        add_frame.grid_rowconfigure(0, weight=1)
        add_frame.grid_columnconfigure(0, weight=1)

        self.entry = ctk.CTkEntry(
            add_frame,
            placeholder_text="/sdcard/YourFolder/",
            fg_color="#151929",
            border_color="#1e2540",
            text_color="#e8edf5",
            placeholder_text_color="#4a5070",
            font=ctk.CTkFont(size=13),
            height=38,
            corner_radius=8,
        )
        self.entry.insert(0, "/sdcard/")
        self.entry.grid(row=0, column=0, padx=(16, 8), sticky="ew")
        self.entry.bind("<Return>", lambda _: self._add_path())

        ctk.CTkButton(
            add_frame,
            text="Add Path",
            width=80,
            height=38,
            fg_color="#1e3a5f",
            hover_color="#1e4976",
            text_color="#7dd3fc",
            font=ctk.CTkFont(size=13, weight="bold"),
            corner_radius=8,
            command=self._add_path,
        ).grid(row=0, column=1, padx=(0, 16))

    def _quick_add_path(self, path: str):
        if not path.endswith("/"):
            path += "/"
        if path not in self.paths:
            save_custom_path(path)
            self.paths.append(path)
            self._rebuild_list()
            self.on_change(self.paths, path)

    def _rebuild_list(self):
        for w in self._row_widgets:
            w["frame"].destroy()
        self._row_widgets.clear()

        if not self.paths:
            msg = ctk.CTkLabel(
                self.list_frame,
                text="No custom paths added yet.\nClick a detected folder above or type a new path below.",
                font=ctk.CTkFont(size=12),
                text_color="#4a5070",
                justify="center",
            )
            msg.grid(row=0, column=0, pady=16)
            self._row_widgets.append({"frame": msg})
            return

        for i, path in enumerate(self.paths):
            row = ctk.CTkFrame(
                self.list_frame,
                fg_color="#151929",
                corner_radius=8,
                border_width=1,
                border_color="#1e2540",
            )
            row.grid(row=i, column=0, sticky="ew", pady=4)
            row.grid_columnconfigure(0, weight=1)

            ctk.CTkLabel(
                row,
                text=path,
                font=ctk.CTkFont(size=12),
                text_color="#94a3b8",
                anchor="w",
            ).grid(row=0, column=0, padx=14, pady=10, sticky="w")

            ctk.CTkButton(
                row,
                text="✕",
                width=30,
                height=28,
                fg_color="#1a0a0a",
                hover_color="#3b0f0f",
                text_color="#ef4444",
                font=ctk.CTkFont(size=12),
                corner_radius=6,
                command=lambda p=path: self._delete_path(p),
            ).grid(row=0, column=1, padx=(0, 10))

            self._row_widgets.append({"frame": row})

    def _add_path(self):
        path = self.entry.get().strip()
        if not path or path == "/sdcard/":
            return
        if not path.endswith("/"):
            path += "/"
        if path not in self.paths:
            save_custom_path(path)
            self.paths.append(path)
            self._rebuild_list()
            self.on_change(self.paths, path)
        self.entry.delete(0, "end")
        self.entry.insert(0, "/sdcard/")

    def _delete_path(self, path: str):
        self.paths = delete_saved_path(path)
        self._rebuild_list()
        self.on_change(self.paths, None)


class Sidebar(ctk.CTkFrame):
    def __init__(
        self,
        master,
        on_path_select: Callable[[str], None],
        on_push_file: Callable[[], None],
        on_push_folder: Callable[[], None],
        saved_paths: List[str],
        on_ask_custom_path: Callable[[], None],
        on_change_dest: Callable[[], None],
    ):
        super().__init__(master, width=232, corner_radius=0, fg_color=_SIDEBAR_BG)
        self.grid_propagate(False)
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(1, weight=1)

        self.on_path_select = on_path_select
        self._nav_items: dict[str, _NavItem] = {}
        self._active_key = ""
        self._saved_paths: List[str] = list(saved_paths)
        self._master = master

        # ── Logo ──────────────────────────────────────────────────────────────
        logo = ctk.CTkFrame(self, fg_color="transparent")
        logo.grid(row=0, column=0, sticky="ew", padx=16, pady=(18, 12))

        ctk.CTkLabel(
            logo, text="⬡", font=ctk.CTkFont(size=20), text_color=_NAV_ACCENT
        ).pack(side="left", padx=(0, 8))
        ctk.CTkLabel(
            logo,
            text="PhoneSync",
            font=ctk.CTkFont(size=16, weight="bold"),
            text_color="#e8edf5",
        ).pack(side="left")

        # ── Scrollable Sidebar Content ────────────────────────────────────────
        scroll = ctk.CTkScrollableFrame(
            self,
            fg_color="transparent",
            scrollbar_button_color="#1e2540",
            scrollbar_button_hover_color="#2d3558",
        )
        scroll.grid(row=1, column=0, sticky="nsew", padx=2, pady=0)
        scroll.grid_columnconfigure(0, weight=1)

        # ── Browse nav ────────────────────────────────────────────────────────
        _Section(scroll, "Browse").grid(
            row=0, column=0, sticky="ew", padx=12, pady=(4, 4)
        )

        nav_defs = [
            ("recents", "🕐", "Recent Files", "RECENTS"),
            ("screenshots", "📸", "Screenshots", "SCREENSHOTS"),
            ("downloads", "📥", "Downloads", "/sdcard/Download/"),
            ("camera", "📷", "Camera", "/sdcard/DCIM/Camera/"),
            ("custom", "📁", "Custom Path…", None),
        ]
        for i, (key, icon, label, path) in enumerate(nav_defs):
            cmd = (
                (lambda p=path: self._nav_click(key, p)) if path else on_ask_custom_path
            )
            item = _NavItem(scroll, icon, label, cmd)
            item.grid(row=1 + i, column=0, sticky="ew", padx=4, pady=1)
            self._nav_items[key] = item

        # ── Saved Paths block ─────────────────────────────────────────────────
        saved_block = ctk.CTkFrame(scroll, fg_color="transparent")
        saved_block.grid(row=6, column=0, sticky="ew", padx=4, pady=(14, 0))
        saved_block.grid_columnconfigure(0, weight=1)

        # Section header with Manage button inline
        sh = ctk.CTkFrame(saved_block, fg_color="transparent")
        sh.grid(row=0, column=0, sticky="ew", padx=8, pady=(0, 4))
        sh.grid_columnconfigure(0, weight=1)

        _Section(sh, "Saved Paths").grid(row=0, column=0, sticky="w")

        ctk.CTkButton(
            sh,
            text="Manage",
            width=56,
            height=20,
            fg_color="transparent",
            hover_color="#0f1520",
            text_color="#3b82f6",
            font=ctk.CTkFont(size=11),
            corner_radius=4,
            command=self._open_paths_manager,
        ).grid(row=0, column=1, sticky="e")

        opts = self._saved_paths if self._saved_paths else ["No saved paths"]
        self.saved_paths_menu = ctk.CTkOptionMenu(
            saved_block,
            values=opts,
            command=self._on_saved_path_select,
            fg_color="#141824",
            button_color="#1e2540",
            button_hover_color="#2d3558",
            dropdown_fg_color="#141824",
            text_color="#a0a8c0",
            font=ctk.CTkFont(size=12),
            corner_radius=8,
            height=34,
            dynamic_resizing=False,
        )
        self.saved_paths_menu.grid(row=1, column=0, sticky="ew", padx=4, pady=(0, 4))

        # ── Transfer section ──────────────────────────────────────────────────
        transfer = ctk.CTkFrame(scroll, fg_color="transparent")
        transfer.grid(row=7, column=0, sticky="ew", padx=4, pady=(16, 16))
        transfer.grid_columnconfigure(0, weight=1)

        _Section(transfer, "Transfer").grid(
            row=0, column=0, sticky="ew", padx=8, pady=(0, 6)
        )

        self.btn_push = _action_btn(
            transfer,
            "Push Files",
            "⬆",
            fg=_BTN_GREEN,
            hover=_BTN_GREEN_HOVER,
            command=on_push_file,
        )
        self.btn_push.grid(row=1, column=0, sticky="ew", padx=4, pady=3)

        self.btn_push_folder = _action_btn(
            transfer,
            "Push Folder",
            "📂",
            fg="#0a2e1a",
            hover=_BTN_GREEN_HOVER,
            command=on_push_folder,
        )
        self.btn_push_folder.grid(row=2, column=0, sticky="ew", padx=4, pady=3)

        self.btn_send_text = _action_btn(
            transfer,
            "Send Text / Link",
            "✉",
            fg=_BTN_BLUE,
            hover=_BTN_BLUE_HOVER,
            command=lambda: getattr(master, "send_text_or_link", lambda: None)(),
        )
        self.btn_send_text.grid(row=3, column=0, sticky="ew", padx=4, pady=3)

        self.btn_change_dest = _action_btn(
            transfer,
            "Set Save Folder",
            "📌",
            command=on_change_dest,
        )
        self.btn_change_dest.grid(row=4, column=0, sticky="ew", padx=4, pady=(3, 0))

    # ── Nav helpers ───────────────────────────────────────────────────────────
    def _nav_click(self, key: str, path: str):
        self._set_active(key)
        self.on_path_select(path)

    def _set_active(self, key: str):
        if self._active_key and self._active_key in self._nav_items:
            self._nav_items[self._active_key].set_active(False)
        self._active_key = key
        if key in self._nav_items:
            self._nav_items[key].set_active(True)

    def _on_saved_path_select(self, path: str):
        if path != "No saved paths":
            self._set_active("")
            self.on_path_select(path)

    def update_saved_paths(self, new_paths: List[str], current_path: str | None):
        self._saved_paths = list(new_paths)
        opts = new_paths if new_paths else ["No saved paths"]
        self.saved_paths_menu.configure(values=opts)
        if current_path and current_path in new_paths:
            self.saved_paths_menu.set(current_path)
        elif not new_paths:
            self.saved_paths_menu.set("No saved paths")

    def _open_paths_manager(self):
        discovered = getattr(self._master, "sdcard_dirs", [])
        dlg = PathsManagerDialog(
            self._master,
            saved_paths=self._saved_paths,
            on_change=self._on_paths_changed,
            discovered_paths=discovered,
        )
        dlg.transient(self._master)

    def _on_paths_changed(self, new_paths: List[str], last_added: str | None):
        self.update_saved_paths(new_paths, last_added)

