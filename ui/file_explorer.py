import os
import threading
import queue
import customtkinter as ctk
from PIL import Image
from typing import List, Callable, Dict
from core.adb_client import FileInfo, pull_file

# ── Design tokens ─────────────────────────────────────────────────────────────
_CARD_BG = ("#ffffff", "#05080f")
_CARD_BG_HOVER = ("#f8fafc", "#090d18")
_CARD_BG_SELECTED = ("#f0f9ff", "#0c1a36")
_CARD_BORDER = ("#e2e8f0", "#111d30")
_CARD_BORDER_HOVER = ("#cbd5e1", "#1a2d48")
_CARD_BORDER_SELECTED = ("#3b82f6", "#2563eb")
_CARD_BORDER_SELECTED_HOVER = ("#60a5fa", "#60a5fa")
_THUMB_BG = ("#f1f5f9", "#0d1524")
_THUMB_IMG_BG = ("#e2e8f0", "#080c14")
_EXT_COLORS = {
    "mp4": "#7c3aed",
    "mov": "#7c3aed",
    "avi": "#7c3aed",
    "mp3": "#0891b2",
    "aac": "#0891b2",
    "flac": "#0891b2",
    "pdf": "#dc2626",
    "doc": "#2563eb",
    "docx": "#2563eb",
    "xls": "#16a34a",
    "xlsx": "#16a34a",
    "zip": "#d97706",
    "rar": "#d97706",
    "tar": "#d97706",
    "apk": "#059669",
}
_EXT_ICONS = {
    "mp4": "▶",
    "mov": "▶",
    "avi": "▶",
    "mp3": "♫",
    "aac": "♫",
    "flac": "♫",
    "pdf": "◉",
    "doc": "▣",
    "docx": "▣",
    "xls": "▤",
    "xlsx": "▤",
    "zip": "◫",
    "rar": "◫",
    "tar": "◫",
    "apk": "⚙",
}


def _fmt_size(size_bytes: int) -> str:
    if size_bytes >= 1_048_576:
        return f"{size_bytes / 1_048_576:.1f} MB"
    if size_bytes >= 1024:
        return f"{size_bytes / 1024:.0f} KB"
    return f"{size_bytes} B"


class ThumbnailLoader:
    def __init__(self, temp_dir: str, on_thumbnail_ready: Callable):
        self.temp_dir = temp_dir
        self.queue = queue.Queue()
        self.on_thumbnail_ready = on_thumbnail_ready
        self.worker_thread = threading.Thread(target=self._worker, daemon=True)
        self.worker_thread.start()

    def load(self, file_info: FileInfo, remote_base_path: str):
        self.queue.put((file_info, remote_base_path))

    def clear(self):
        while not self.queue.empty():
            try:
                self.queue.get_nowait()
            except queue.Empty:
                break

    def _worker(self):
        valid_exts = (".jpg", ".jpeg", ".png", ".heic", ".webp", ".gif")
        while True:
            file_info, remote_base_path = self.queue.get()
            f_name = file_info["name"]
            if not f_name.lower().endswith(valid_exts):
                self.queue.task_done()
                continue

            remote_file = os.path.join(remote_base_path, f_name).replace("\\", "/")
            local_file = os.path.join(self.temp_dir, f_name)

            try:
                if not os.path.exists(local_file):
                    pull_file(remote_file, local_file)

                img = Image.open(local_file)
                img.thumbnail((54, 54), Image.Resampling.LANCZOS)
                ctk_img = ctk.CTkImage(light_image=img, dark_image=img, size=img.size)
                self.on_thumbnail_ready(f_name, ctk_img)
            except Exception:
                pass

            self.queue.task_done()


class FileExplorer(ctk.CTkFrame):
    def __init__(
        self,
        master,
        temp_dir: str,
        on_preview: Callable,
        on_selection_change: Callable,
    ):
        super().__init__(master, fg_color="transparent")
        self.grid_rowconfigure(1, weight=1)
        self.grid_columnconfigure(0, weight=1)

        self.temp_dir = temp_dir
        self.on_preview = on_preview
        self.on_selection_change = on_selection_change

        self.files: List[FileInfo] = []
        self.remote_base_path = ""
        self.checkboxes: Dict[str, ctk.StringVar] = {}
        self.thumbnail_labels: Dict[str, ctk.CTkLabel] = {}
        self.file_widgets: Dict[str, dict] = {}
        self.header_widgets: List[ctk.CTkLabel] = []
        self._f_info_map: Dict[str, FileInfo] = {}

        self.page = 0
        self.page_size = 50

        self._render_queue: list = []
        self._is_rendering = False
        self._current_row_idx = 0
        self._current_thumb_count = 0
        self._last_rendered_group = None

        # ── Toolbar ───────────────────────────────────────────────────────────
        toolbar = ctk.CTkFrame(self, fg_color="transparent")
        toolbar.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        toolbar.grid_columnconfigure(4, weight=1)  # Spacer column

        # Sort
        ctk.CTkLabel(
            toolbar,
            text="⇅  Sort",
            font=ctk.CTkFont(size=12),
            text_color="#6b7280",
        ).grid(row=0, column=0, padx=(2, 4))

        self.sort_var = ctk.StringVar(value="Date (Newest)")
        ctk.CTkOptionMenu(
            toolbar,
            variable=self.sort_var,
            values=["Date (Newest)", "Date (Oldest)", "Name (A-Z)", "Size (Largest)"],
            command=self._on_sort_group_change,
            fg_color="#1a1f2e",
            button_color="#252b3b",
            button_hover_color="#2e3650",
            dropdown_fg_color="#1a1f2e",
            text_color="#cbd5e1",
            font=ctk.CTkFont(size=12),
            corner_radius=8,
            height=32,
            width=140,
        ).grid(row=0, column=1, padx=(0, 16))

        # Group
        ctk.CTkLabel(
            toolbar,
            text="▤  Group",
            font=ctk.CTkFont(size=12),
            text_color="#6b7280",
        ).grid(row=0, column=2, padx=(0, 4))

        self.group_var = ctk.StringVar(value="Date (Day)")
        ctk.CTkOptionMenu(
            toolbar,
            variable=self.group_var,
            values=["None", "Date (Day)", "Extension"],
            command=self._on_sort_group_change,
            fg_color="#1a1f2e",
            button_color="#252b3b",
            button_hover_color="#2e3650",
            dropdown_fg_color="#1a1f2e",
            text_color="#cbd5e1",
            font=ctk.CTkFont(size=12),
            corner_radius=8,
            height=32,
            width=120,
        ).grid(row=0, column=3, padx=(0, 0))

        # Select All / Deselect — pushed to the right
        sel_frame = ctk.CTkFrame(toolbar, fg_color="transparent")
        sel_frame.grid(row=0, column=5, sticky="e")

        ctk.CTkButton(
            sel_frame,
            text="Select All",
            width=90,
            height=32,
            fg_color="#1e2230",
            hover_color="#252b3b",
            text_color="#cbd5e1",
            font=ctk.CTkFont(size=12),
            corner_radius=8,
            command=self.select_all,
        ).pack(side="left", padx=(0, 6))

        ctk.CTkButton(
            sel_frame,
            text="Deselect All",
            width=100,
            height=32,
            fg_color="#1e2230",
            hover_color="#252b3b",
            text_color="#cbd5e1",
            font=ctk.CTkFont(size=12),
            corner_radius=8,
            command=self.deselect_all,
        ).pack(side="left")

        # ── Scrollable list ───────────────────────────────────────────────────
        self.scroll_frame = ctk.CTkScrollableFrame(
            self, fg_color="transparent", scrollbar_button_color="#252b3b"
        )
        self.scroll_frame.grid(row=1, column=0, sticky="nsew")
        self.scroll_frame.grid_columnconfigure(0, weight=1)

        # Build the single reusable scroll handler and wire it to the canvas
        self._scroll_handler = (
            None  # placeholder; set after _make_scroll_handler exists
        )
        # We can't call _make_scroll_handler yet (scroll_frame may not be fully init)
        # So defer to first use via a property-like pattern:
        self.after(100, self._init_scroll)

        # Thumbnail Loader
        self.thumbnail_loader = ThumbnailLoader(self.temp_dir, self._on_thumbnail_ready)

    def _init_scroll(self):
        """Deferred scroll setup so CTkScrollableFrame canvas is ready."""
        self._scroll_handler = self._make_scroll_handler()
        self._bind_scrolling(self.scroll_frame._parent_canvas)
        # Also bind on the scrollable frame's inner frame
        self._bind_scrolling(self.scroll_frame)

    # ── Scroll binding ────────────────────────────────────────────────────────
    def _make_scroll_handler(self):
        """Return a scroll handler that always routes to the canvas."""

        def _handler(event):
            try:
                canvas = self.scroll_frame._parent_canvas
                num = getattr(event, "num", 0)
                delta = getattr(event, "delta", 0)
                if num == 4 or delta > 0:
                    canvas.yview_scroll(-1, "units")
                elif num == 5 or delta < 0:
                    canvas.yview_scroll(1, "units")
                # Do NOT return "break" — let event propagate so the canvas
                # also receives it and we don't double-scroll.
            except Exception:
                pass

        return _handler

    def _bind_scroll_recursive(self, widget):
        """Recursively bind scroll events to every descendant of widget.

        This is the only reliable way to catch trackpad (Button-4/5)
        events regardless of which child widget the pointer is hovering over.
        """
        h = self._scroll_handler
        for ev in ("<MouseWheel>", "<Button-4>", "<Button-5>"):
            widget.bind(ev, h, add="+")
        for child in widget.winfo_children():
            self._bind_scroll_recursive(child)

    def _bind_scrolling(self, widget):
        """Legacy single-widget bind — kept for the canvas itself."""
        h = self._scroll_handler
        for ev in ("<MouseWheel>", "<Button-4>", "<Button-5>"):
            widget.bind(ev, h, add="+")

    # ── Thumbnail ─────────────────────────────────────────────────────────────
    def _on_thumbnail_ready(self, f_name: str, ctk_img):
        self.master.after(0, lambda: self._apply_thumbnail(f_name, ctk_img))

    def _apply_thumbnail(self, f_name: str, ctk_img):
        if f_name in self.thumbnail_labels:
            self.thumbnail_labels[f_name].configure(
                text="", image=ctk_img, fg_color="transparent"
            )

    # ── Card factory ──────────────────────────────────────────────────────────
    def _create_file_card(self, f_info: FileInfo, row_idx: int) -> dict:
        f_name = f_info["name"]
        valid_img = (".jpg", ".jpeg", ".png", ".heic", ".webp", ".gif")
        ext = os.path.splitext(f_name)[1].lower().lstrip(".")
        is_image = f_name.lower().endswith(valid_img)

        # ── Card container ────────────────────────────────────────────────────
        card = ctk.CTkFrame(
            self.scroll_frame,
            fg_color=_CARD_BG,
            corner_radius=10,
            border_width=1,
            border_color=_CARD_BORDER,
        )
        card.grid(row=row_idx, column=0, sticky="ew", padx=4, pady=3)
        card.grid_columnconfigure(2, weight=1)

        # ── Checkbox ──────────────────────────────────────────────────────────
        chk_var = ctk.StringVar(value="off")
        chk = ctk.CTkCheckBox(
            card,
            text="",
            variable=chk_var,
            onvalue="on",
            offvalue="off",
            width=20,
            checkbox_width=18,
            checkbox_height=18,
            border_color="#1e2d45",
            hover_color=_CARD_BORDER_SELECTED,
            checkmark_color="#ffffff",
        )
        chk.grid(row=0, column=0, padx=(14, 4), pady=12, sticky="w")
        self.checkboxes[f_name] = chk_var

        # ── Thumbnail / Icon badge ─────────────────────────────────────────────
        thumb_color = _EXT_COLORS.get(ext, _THUMB_BG) if not is_image else _THUMB_IMG_BG
        thumb_icon = _EXT_ICONS.get(ext, "▪") if not is_image else "⬡"

        thumb_lbl = ctk.CTkLabel(
            card,
            text=thumb_icon,
            width=54,
            height=54,
            fg_color=thumb_color,
            corner_radius=8,
            font=ctk.CTkFont(size=18),
            text_color="#94a3b8",
        )
        thumb_lbl.grid(row=0, column=1, padx=(4, 12), pady=10)
        self.thumbnail_labels[f_name] = thumb_lbl

        if is_image:
            self.thumbnail_loader.load(f_info, self.remote_base_path)

        # ── File info (name + meta) ───────────────────────────────────────────
        info_frame = ctk.CTkFrame(card, fg_color="transparent")
        info_frame.grid(row=0, column=2, sticky="ew", padx=(0, 8), pady=10)
        info_frame.grid_columnconfigure(0, weight=1)

        name_lbl = ctk.CTkLabel(
            info_frame,
            text=f_name,
            anchor="w",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color=("#1e293b", "#dde4f0"),
            wraplength=0,
        )
        name_lbl.grid(row=0, column=0, sticky="ew")

        size_str = _fmt_size(f_info["size"])
        date_str = f_info["mod_time"].strftime("%b %d, %Y  %H:%M")
        meta_lbl = ctk.CTkLabel(
            info_frame,
            text=f"{size_str}  ·  {date_str}",
            anchor="w",
            font=ctk.CTkFont(size=11),
            text_color=("#64748b", "#3d4f6a"),
        )
        meta_lbl.grid(row=1, column=0, sticky="ew")

        # ── Preview button ────────────────────────────────────────────────────
        full_path = f_info.get("full_path", self.remote_base_path + f_name)
        preview_btn = ctk.CTkButton(
            card,
            text="Preview",
            width=68,
            height=30,
            fg_color=("#e0f2fe", "#0b1830"),
            hover_color=("#bae6fd", "#112240"),
            text_color=("#0284c7", "#4d8fcc"),
            font=ctk.CTkFont(size=11, weight="bold"),
            corner_radius=6,
            command=lambda p=full_path: self.on_preview(p),
        )
        preview_btn.grid(row=0, column=3, padx=(0, 14), pady=12)

        # ── Hover + click-to-select ───────────────────────────────────────────
        def _update_style(selected: bool):
            if selected:
                card.configure(
                    fg_color=_CARD_BG_SELECTED, border_color=_CARD_BORDER_SELECTED
                )
            else:
                card.configure(fg_color=_CARD_BG, border_color=_CARD_BORDER)

        def _toggle(event=None):
            new = "on" if chk_var.get() == "off" else "off"
            chk_var.set(new)
            _update_style(new == "on")
            self.on_selection_change()

        chk.configure(
            command=lambda: [
                _update_style(chk_var.get() == "on"),
                self.on_selection_change(),
            ]
        )

        def _on_enter(event=None):
            if chk_var.get() == "on":
                card.configure(
                    fg_color=_CARD_BG_SELECTED, border_color=_CARD_BORDER_SELECTED_HOVER
                )
            else:
                card.configure(fg_color=_CARD_BG_HOVER, border_color=_CARD_BORDER_HOVER)

        def _on_leave(event=None):
            _update_style(chk_var.get() == "on")

        for w in (card, thumb_lbl, info_frame, name_lbl, meta_lbl):
            w.bind("<Enter>", _on_enter)
            w.bind("<Leave>", _on_leave)
            w.bind("<Button-1>", _toggle)

        chk.bind("<Enter>", _on_enter)
        chk.bind("<Leave>", _on_leave)

        # ── Bind scrolling to EVERY descendant (reliable trackpad fix) ─────────
        if self._scroll_handler:
            self._bind_scroll_recursive(card)

        return {
            "card": card,
            "chk": chk,
            "chk_var": chk_var,
            "thumb": thumb_lbl,
            "name": name_lbl,
            "meta": meta_lbl,
            "preview": preview_btn,
            "update_style": _update_style,
        }

    # ── Rendering pipeline ────────────────────────────────────────────────────
    def _on_sort_group_change(self, _=None):
        self.page = 0
        self._render()

    def _sorted_files(self) -> List[FileInfo]:
        v = self.sort_var.get()
        if v == "Date (Newest)":
            return sorted(self.files, key=lambda x: x["mod_time"], reverse=True)
        if v == "Date (Oldest)":
            return sorted(self.files, key=lambda x: x["mod_time"])
        if v == "Name (A-Z)":
            return sorted(self.files, key=lambda x: x["name"].lower())
        if v == "Size (Largest)":
            return sorted(self.files, key=lambda x: x["size"], reverse=True)
        return list(self.files)

    def _grouped(self, files: List[FileInfo]) -> dict:
        g_val = self.group_var.get()
        groups: dict = {}
        if g_val == "None":
            groups["All Files"] = files
        elif g_val == "Date (Day)":
            for f in files:
                k = f["mod_time"].strftime("%A, %B %d %Y")
                groups.setdefault(k, []).append(f)
        elif g_val == "Extension":
            for f in files:
                k = os.path.splitext(f["name"])[1].lower() or "Unknown"
                groups.setdefault(k, []).append(f)
        return groups

    def _build_render_queue(
        self, sorted_files: List[FileInfo], start: int, end: int
    ) -> list:
        paginated = sorted_files[start:end]
        groups = self._grouped(paginated)
        items = []
        last_g = None
        for g_name, g_files in groups.items():
            if self.group_var.get() != "None":
                items.append(("header", g_name))
                last_g = g_name
            for f in g_files:
                items.append(("file", f))
        self._last_rendered_group = last_g
        if end < len(sorted_files):
            items.append(("load_more", len(sorted_files) - end))
        return items

    def _render(self, append=False):
        if not append:
            self._render_queue.clear()
            self._is_rendering = False
            for w in self.scroll_frame.winfo_children():
                w.destroy()
            self.checkboxes.clear()
            self.thumbnail_labels.clear()
            self.thumbnail_loader.clear()
            self.file_widgets.clear()
            self.header_widgets.clear()

        if not self.files:
            ctk.CTkLabel(
                self.scroll_frame,
                text="No files found.",
                text_color="#4b5563",
                font=ctk.CTkFont(size=14),
            ).grid(row=0, column=0, pady=40)
            return

        sorted_files = self._sorted_files()
        start = self.page * self.page_size
        end = start + self.page_size
        row_offset = len(self.checkboxes) * 2 + 1000 * self.page

        self._render_queue.extend(self._build_render_queue(sorted_files, start, end))
        self._current_row_idx = row_offset
        self._current_thumb_count = 0

        if not self._is_rendering:
            self._process_render_queue()

    def _process_render_queue(self):
        if not self._render_queue:
            self._is_rendering = False
            return

        self._is_rendering = True
        chunk = self._render_queue[:10]
        self._render_queue = self._render_queue[10:]

        for item in chunk:
            kind = item[0]
            if kind == "header":
                lbl = ctk.CTkLabel(
                    self.scroll_frame,
                    text=item[1],
                    font=ctk.CTkFont(size=11, weight="bold"),
                    text_color="#4b5570",
                    anchor="w",
                )
                lbl.grid(
                    row=self._current_row_idx,
                    column=0,
                    sticky="ew",
                    padx=8,
                    pady=(18, 4),
                )
                self._bind_scrolling(lbl)
                self.header_widgets.append(lbl)
                self._current_row_idx += 1
            elif kind == "file":
                f_info = item[1]
                f_name = f_info["name"]
                if f_name in self.file_widgets:
                    self.file_widgets[f_name]["card"].grid(
                        row=self._current_row_idx, column=0, sticky="ew", padx=4, pady=3
                    )
                else:
                    self.file_widgets[f_name] = self._create_file_card(
                        f_info, self._current_row_idx
                    )
                self._current_row_idx += 1
            elif kind == "load_more":
                if hasattr(self, "btn_load_more") and self.btn_load_more.winfo_exists():
                    self.btn_load_more.destroy()
                self.btn_load_more = ctk.CTkButton(
                    self.scroll_frame,
                    text=f"Load {item[1]} more…",
                    height=36,
                    fg_color="#1e2230",
                    hover_color="#252b3b",
                    text_color="#94a3b8",
                    font=ctk.CTkFont(size=12),
                    corner_radius=8,
                    command=self.load_more,
                )
                self.btn_load_more.grid(
                    row=self._current_row_idx + 1,
                    column=0,
                    pady=12,
                    padx=4,
                    sticky="ew",
                )
                self._bind_scrolling(self.btn_load_more)

        if self._render_queue:
            self.after(5, self._process_render_queue)
        else:
            self._is_rendering = False

    def _incremental_render(self, new_files: List[FileInfo]):
        g_val = self.group_var.get()
        items = []
        for f in new_files:
            if g_val == "Date (Day)":
                g = f["mod_time"].strftime("%A, %B %d %Y")
            elif g_val == "Extension":
                g = os.path.splitext(f["name"])[1].lower() or "Unknown"
            else:
                g = None
            if g and g != self._last_rendered_group:
                items.append(("header", g))
                self._last_rendered_group = g
            items.append(("file", f))
        self._render_queue.extend(items)
        if not self._is_rendering:
            self._process_render_queue()

    # ── Public API ────────────────────────────────────────────────────────────
    def set_files(self, files: List[FileInfo], remote_base_path: str):
        self.files = files
        self.remote_base_path = remote_base_path
        self._f_info_map = {f["name"]: f for f in files}
        self.page = 0
        self._render()

    def update_files(self, new_files: List[FileInfo], remote_base_path: str):
        self.files = new_files
        self.remote_base_path = remote_base_path
        self._f_info_map = {f["name"]: f for f in new_files}

        sorted_files = self._sorted_files()
        end = (self.page + 1) * self.page_size
        groups = self._grouped(sorted_files[:end])

        for w in self.header_widgets:
            w.destroy()
        self.header_widgets.clear()
        if hasattr(self, "btn_load_more") and self.btn_load_more.winfo_exists():
            self.btn_load_more.destroy()

        rendered = set()
        row = 0
        for g_name, g_files in groups.items():
            if self.group_var.get() != "None":
                lbl = ctk.CTkLabel(
                    self.scroll_frame,
                    text=g_name,
                    font=ctk.CTkFont(size=11, weight="bold"),
                    text_color="#4b5570",
                    anchor="w",
                )
                lbl.grid(row=row, column=0, sticky="ew", padx=8, pady=(18, 4))
                self._bind_scrolling(lbl)
                self.header_widgets.append(lbl)
                row += 1
            for f_info in g_files:
                n = f_info["name"]
                rendered.add(n)
                if n in self.file_widgets:
                    self.file_widgets[n]["card"].grid(
                        row=row, column=0, sticky="ew", padx=4, pady=3
                    )
                    # Refresh meta text
                    self.file_widgets[n]["meta"].configure(
                        text=f"{_fmt_size(f_info['size'])}  ·  {f_info['mod_time'].strftime('%b %d, %Y  %H:%M')}"
                    )
                else:
                    self.file_widgets[n] = self._create_file_card(f_info, row)
                row += 1

        for n in list(self.file_widgets.keys()):
            if n not in rendered:
                self.file_widgets.pop(n)["card"].destroy()
                self.checkboxes.pop(n, None)
                self.thumbnail_labels.pop(n, None)

        if end < len(sorted_files):
            remaining = len(sorted_files) - end
            self.btn_load_more = ctk.CTkButton(
                self.scroll_frame,
                text=f"Load {remaining} more…",
                height=36,
                fg_color="#1e2230",
                hover_color="#252b3b",
                text_color="#94a3b8",
                font=ctk.CTkFont(size=12),
                corner_radius=8,
                command=self.load_more,
            )
            self.btn_load_more.grid(row=row, column=0, pady=12, padx=4, sticky="ew")
            self._bind_scrolling(self.btn_load_more)

    def append_files(self, new_files: List[FileInfo], remote_base_path: str):
        self.remote_base_path = remote_base_path
        self.files.extend(new_files)
        for f in new_files:
            self._f_info_map[f["name"]] = f
        if self.page == 0:
            if len(self.files) == len(new_files):
                self._render()
            elif len(self.files) <= self.page_size:
                self._incremental_render(new_files)

    def load_more(self):
        self.page += 1
        self._render(append=True)

    def select_all(self):
        for n, var in self.checkboxes.items():
            var.set("on")
            if n in self.file_widgets:
                self.file_widgets[n]["update_style"](True)
        self.on_selection_change()

    def deselect_all(self):
        for n, var in self.checkboxes.items():
            var.set("off")
            if n in self.file_widgets:
                self.file_widgets[n]["update_style"](False)
        self.on_selection_change()

    def get_selected_files(self) -> List[str]:
        selected = []
        for n, var in self.checkboxes.items():
            if var.get() == "on":
                f_info = self._f_info_map.get(n)
                if f_info and "full_path" in f_info:
                    selected.append(f_info["full_path"])
                else:
                    selected.append(self.remote_base_path + n)
        return selected
