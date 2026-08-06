import os
import subprocess
import threading

import customtkinter as ctk
from PIL import Image

_MAIN_BG = "#0f1117"
_TEXT_MUTED = "#6b7280"


def show_file_preview(parent: ctk.CTk, full_remote_path: str, temp_dir: str) -> None:
    """Download and preview an image file from the connected device."""
    filename = full_remote_path.split("/")[-1]
    local_file = os.path.join(temp_dir, filename)

    prev_win = ctk.CTkToplevel(parent)
    prev_win.title(f"Preview \u2014 {filename}")
    prev_win.geometry("640x640")
    prev_win.configure(fg_color=_MAIN_BG)

    spinner = ctk.CTkLabel(
        prev_win,
        text="Fetching preview\u2026",
        font=ctk.CTkFont(size=14),
        text_color=_TEXT_MUTED,
    )
    spinner.pack(expand=True)

    def _show_img(ctk_img: ctk.CTkImage) -> None:
        if prev_win.winfo_exists():
            spinner.destroy()
            ctk.CTkLabel(prev_win, text="", image=ctk_img).pack(
                expand=True, padx=16, pady=16
            )

    def _pull_and_show() -> None:
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
            parent.after(0, lambda: _show_img(ctk_img))
        except Exception as err:
            if prev_win.winfo_exists():
                parent.after(
                    0,
                    lambda err=err: spinner.configure(
                        text=f"Preview unavailable\n{err}"
                    ),
                )

    threading.Thread(target=_pull_and_show, daemon=True).start()
