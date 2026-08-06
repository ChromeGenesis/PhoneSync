import os
import subprocess
import threading
import tkinter as tk

import customtkinter as ctk
from PIL import Image, ImageTk

_MAIN_BG = "#0f1117"
_SURFACE_BG = "#141824"
_BORDER_COLOR = "#1e2540"
_TEXT_PRIMARY = "#dde4f0"
_TEXT_MUTED = "#6b7280"


class ImagePreviewWindow(ctk.CTkToplevel):
    """Interactive top-most preview window supporting drag-to-pan, scroll-to-zoom, and shortcuts."""

    def __init__(self, parent: ctk.CTk, full_remote_path: str, temp_dir: str):
        super().__init__(parent)

        filename = full_remote_path.split("/")[-1]
        self.title(f"Preview \u2014 {filename}")
        self.geometry("740x700")
        self.minsize(420, 420)
        self.configure(fg_color=_MAIN_BG)

        # ── Always on top of main window ──────────────────────────────────────
        self.transient(parent)
        self.attributes("-topmost", True)
        self.lift()
        self.focus_force()

        self.full_remote_path = full_remote_path
        self.temp_dir = temp_dir
        self.filename = filename

        self.pil_image: Image.Image | None = None
        self.tk_image: ImageTk.PhotoImage | None = None
        self.zoom_level = 1.0
        self.fit_scale = 1.0
        self.pan_x = 0.0
        self.pan_y = 0.0
        self.drag_start_x = 0
        self.drag_start_y = 0

        # Layout: row 0 = Canvas, row 1 = Toolbar
        self.grid_rowconfigure(0, weight=1)
        self.grid_columnconfigure(0, weight=1)

        # Loading Spinner
        self.spinner = ctk.CTkLabel(
            self,
            text="Fetching preview from phone\u2026",
            font=ctk.CTkFont(size=14),
            text_color=_TEXT_MUTED,
        )
        self.spinner.grid(row=0, column=0, sticky="center")

        # Fetch image in background thread
        threading.Thread(target=self._fetch_and_load, daemon=True).start()

        # Keyboard Shortcuts
        self.bind("<Escape>", lambda e: self.destroy())
        self.bind("<plus>", lambda e: self.zoom_by(1.25))
        self.bind("<equal>", lambda e: self.zoom_by(1.25))
        self.bind("<minus>", lambda e: self.zoom_by(1 / 1.25))
        self.bind("0", lambda e: self.reset_zoom())

    def _fetch_and_load(self) -> None:
        local_file = os.path.join(self.temp_dir, self.filename)
        try:
            if not os.path.exists(local_file):
                subprocess.run(
                    ["adb", "pull", self.full_remote_path, local_file],
                    check=True,
                    capture_output=True,
                )
            img = Image.open(local_file)
            img.load()
            if img.mode not in ("RGB", "RGBA"):
                img = img.convert("RGBA")
            self.pil_image = img
            self.after(0, self._build_canvas_ui)
        except Exception as err:
            if self.winfo_exists():
                self.after(
                    0,
                    lambda err=err: self.spinner.configure(
                        text=f"Preview unavailable\n{err}"
                    ),
                )

    def _build_canvas_ui(self) -> None:
        if not self.winfo_exists() or self.pil_image is None:
            return

        self.spinner.destroy()

        # Canvas container
        canvas_frame = ctk.CTkFrame(self, fg_color=_MAIN_BG, corner_radius=0)
        canvas_frame.grid(row=0, column=0, sticky="nsew")
        canvas_frame.grid_rowconfigure(0, weight=1)
        canvas_frame.grid_columnconfigure(0, weight=1)

        # Smooth Pan/Zoom Canvas
        self.canvas = tk.Canvas(
            canvas_frame,
            bg=_MAIN_BG,
            highlightthickness=0,
            bd=0,
            cursor="fleur",
        )
        self.canvas.grid(row=0, column=0, sticky="nsew")

        # Bottom Floating Control Toolbar
        toolbar = ctk.CTkFrame(
            self,
            fg_color=_SURFACE_BG,
            corner_radius=12,
            border_width=1,
            border_color=_BORDER_COLOR,
            height=44,
        )
        toolbar.grid(row=1, column=0, pady=(0, 14), padx=20)
        toolbar.grid_propagate(False)

        btn_out = ctk.CTkButton(
            toolbar,
            text="\u2212",
            width=32,
            height=28,
            fg_color="#1e2540",
            hover_color="#2d3558",
            text_color="#e8edf5",
            font=ctk.CTkFont(size=16, weight="bold"),
            corner_radius=6,
            command=lambda: self.zoom_by(1 / 1.25),
        )
        btn_out.pack(side="left", padx=(10, 4), pady=8)

        self.lbl_zoom = ctk.CTkLabel(
            toolbar,
            text="100%",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color=_TEXT_PRIMARY,
            width=54,
        )
        self.lbl_zoom.pack(side="left", padx=4)

        btn_in = ctk.CTkButton(
            toolbar,
            text="+",
            width=32,
            height=28,
            fg_color="#1e2540",
            hover_color="#2d3558",
            text_color="#e8edf5",
            font=ctk.CTkFont(size=16, weight="bold"),
            corner_radius=6,
            command=lambda: self.zoom_by(1.25),
        )
        btn_in.pack(side="left", padx=(4, 10), pady=8)

        btn_fit = ctk.CTkButton(
            toolbar,
            text="Fit",
            width=46,
            height=28,
            fg_color="#1e2540",
            hover_color="#2d3558",
            text_color="#38bdf8",
            font=ctk.CTkFont(size=11, weight="bold"),
            corner_radius=6,
            command=self.reset_zoom,
        )
        btn_fit.pack(side="left", padx=(0, 10), pady=8)

        btn_actual = ctk.CTkButton(
            toolbar,
            text="1:1",
            width=40,
            height=28,
            fg_color="#1e2540",
            hover_color="#2d3558",
            text_color="#a7f3d0",
            font=ctk.CTkFont(size=11, weight="bold"),
            corner_radius=6,
            command=self.set_actual_size,
        )
        btn_actual.pack(side="left", padx=(0, 10), pady=8)

        # Mouse & Trackpad bindings
        self.canvas.bind("<ButtonPress-1>", self._on_drag_start)
        self.canvas.bind("<B1-Motion>", self._on_drag_motion)
        self.canvas.bind("<MouseWheel>", self._on_mouse_wheel)  # Win / macOS
        self.canvas.bind("<Button-4>", self._on_mouse_wheel)  # Linux scroll up
        self.canvas.bind("<Button-5>", self._on_mouse_wheel)  # Linux scroll down
        self.canvas.bind("<Configure>", self._on_canvas_resize)

        self.update_idletasks()
        self._calculate_fit_scale()
        self.zoom_level = self.fit_scale
        self.redraw()

    def _calculate_fit_scale(self) -> None:
        if self.pil_image is None or not hasattr(self, "canvas"):
            return
        cw = max(self.canvas.winfo_width(), self.winfo_width(), 400)
        ch = max(self.canvas.winfo_height(), self.winfo_height() - 60, 400)
        iw, ih = self.pil_image.size
        scale_w = cw / iw
        scale_h = ch / ih
        self.fit_scale = min(scale_w, scale_h, 1.0)

    def _on_canvas_resize(self, _event: tk.Event) -> None:
        old_fit = self.fit_scale
        self._calculate_fit_scale()
        if self.zoom_level == old_fit:
            self.zoom_level = self.fit_scale
        self.redraw()

    def _on_drag_start(self, event: tk.Event) -> None:
        self.drag_start_x = event.x
        self.drag_start_y = event.y

    def _on_drag_motion(self, event: tk.Event) -> None:
        dx = event.x - self.drag_start_x
        dy = event.y - self.drag_start_y
        self.drag_start_x = event.x
        self.drag_start_y = event.y

        self.pan_x += dx
        self.pan_y += dy
        self.redraw()

    def _on_mouse_wheel(self, event: tk.Event) -> None:
        if event.num == 4 or (hasattr(event, "delta") and event.delta > 0):
            factor = 1.15
        elif event.num == 5 or (hasattr(event, "delta") and event.delta < 0):
            factor = 1 / 1.15
        else:
            return

        self.zoom_at(factor, event.x, event.y)

    def zoom_by(self, factor: float) -> None:
        cw = self.canvas.winfo_width() / 2
        ch = self.canvas.winfo_height() / 2
        self.zoom_at(factor, cw, ch)

    def zoom_at(self, factor: float, focus_x: float, focus_y: float) -> None:
        new_zoom = max(0.05, min(self.zoom_level * factor, 20.0))
        if new_zoom == self.zoom_level:
            return

        cw = self.canvas.winfo_width()
        ch = self.canvas.winfo_height()
        cx = cw / 2 + self.pan_x
        cy = ch / 2 + self.pan_y

        rel_x = focus_x - cx
        rel_y = focus_y - cy

        scale_change = new_zoom / self.zoom_level
        self.pan_x -= rel_x * (scale_change - 1)
        self.pan_y -= rel_y * (scale_change - 1)

        self.zoom_level = new_zoom
        self.redraw()

    def reset_zoom(self) -> None:
        self._calculate_fit_scale()
        self.zoom_level = self.fit_scale
        self.pan_x = 0
        self.pan_y = 0
        self.redraw()

    def set_actual_size(self) -> None:
        self.zoom_level = 1.0
        self.pan_x = 0
        self.pan_y = 0
        self.redraw()

    def redraw(self) -> None:
        if self.pil_image is None or not hasattr(self, "canvas"):
            return

        cw = self.canvas.winfo_width()
        ch = self.canvas.winfo_height()
        if cw < 10 or ch < 10:
            self.after(40, self.redraw)
            return

        iw, ih = self.pil_image.size
        nw = max(int(iw * self.zoom_level), 1)
        nh = max(int(ih * self.zoom_level), 1)

        resample_mode = (
            Image.Resampling.LANCZOS
            if self.zoom_level <= 2.0
            else Image.Resampling.NEAREST
        )
        resized_img = self.pil_image.resize((nw, nh), resample_mode)
        self.tk_image = ImageTk.PhotoImage(resized_img)

        self.canvas.delete("all")

        pos_x = (cw / 2) + self.pan_x
        pos_y = (ch / 2) + self.pan_y

        self.canvas.create_image(pos_x, pos_y, image=self.tk_image, anchor="center")

        pct = int((self.zoom_level / self.fit_scale) * 100)
        self.lbl_zoom.configure(text=f"{pct}%")


def show_file_preview(parent: ctk.CTk, full_remote_path: str, temp_dir: str) -> None:
    """Open top-most interactive image preview window with pan & zoom capability."""
    ImagePreviewWindow(parent, full_remote_path, temp_dir)
