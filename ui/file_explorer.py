import os
import threading
import queue
import customtkinter as ctk
from PIL import Image
from typing import List, Callable, Dict
from core.adb_client import FileInfo, pull_file

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
        # Empty the queue
        while not self.queue.empty():
            try:
                self.queue.get_nowait()
            except queue.Empty:
                break

    def _worker(self):
        valid_exts = ('.jpg', '.jpeg', '.png', '.heic', '.webp', '.gif')
        while True:
            file_info, remote_base_path = self.queue.get()
            f_name = file_info['name']
            
            if not f_name.lower().endswith(valid_exts):
                self.queue.task_done()
                continue
                
            remote_file = os.path.join(remote_base_path, f_name).replace('\\', '/')
            local_file = os.path.join(self.temp_dir, f_name)
            
            try:
                # Try pulling and resizing
                if not os.path.exists(local_file):
                    pull_file(remote_file, local_file)
                
                img = Image.open(local_file)
                img.thumbnail((50, 50), Image.Resampling.LANCZOS)
                ctk_img = ctk.CTkImage(light_image=img, dark_image=img, size=img.size)
                
                self.on_thumbnail_ready(f_name, ctk_img)
            except Exception:
                pass
            
            self.queue.task_done()

class FileExplorer(ctk.CTkFrame):
    def __init__(self, master, temp_dir: str, on_preview: Callable, on_selection_change: Callable):
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
        self.file_widgets: Dict[str, Dict[str, ctk.CTkBaseClass]] = {}
        self.header_widgets: List[ctk.CTkLabel] = []
        self._f_info_map = {}
        
        self.page = 0
        self.page_size = 50
        
        self._render_queue = []
        self._is_rendering = False
        
        # Tools bar
        self.tools_bar = ctk.CTkFrame(self, fg_color="transparent")
        self.tools_bar.grid(row=0, column=0, sticky="ew", pady=(0, 10))
        
        ctk.CTkLabel(self.tools_bar, text="Sort by:").pack(side="left", padx=(0, 5))
        self.sort_var = ctk.StringVar(value="Date (Newest)")
        self.sort_menu = ctk.CTkOptionMenu(self.tools_bar, variable=self.sort_var, 
                                           values=["Date (Newest)", "Date (Oldest)", "Name (A-Z)", "Size (Largest)"],
                                           command=self._on_sort_group_change)
        self.sort_menu.pack(side="left", padx=(0, 20))
        
        ctk.CTkLabel(self.tools_bar, text="Group by:").pack(side="left", padx=(0, 5))
        self.group_var = ctk.StringVar(value="Date (Day)")
        self.group_menu = ctk.CTkOptionMenu(self.tools_bar, variable=self.group_var, 
                                            values=["None", "Date (Day)", "Extension"],
                                            command=self._on_sort_group_change)
        self.group_menu.pack(side="left")

        # Scrollable list
        self.scroll_frame = ctk.CTkScrollableFrame(self)
        self.scroll_frame.grid(row=1, column=0, sticky="nsew")
        self.scroll_frame.grid_columnconfigure(2, weight=1)

        # Bottom selection tools
        self.bottom_bar = ctk.CTkFrame(self, fg_color="transparent")
        self.bottom_bar.grid(row=2, column=0, sticky="ew", pady=(10, 0))
        
        self.btn_select_all = ctk.CTkButton(self.bottom_bar, text="Select All", width=100, command=self.select_all)
        self.btn_select_all.pack(side="left", padx=(0, 10))
        
        self.btn_deselect_all = ctk.CTkButton(self.bottom_bar, text="Deselect All", width=100, command=self.deselect_all)
        self.btn_deselect_all.pack(side="left")

        # Thumbnail Loader
        self.thumbnail_loader = ThumbnailLoader(self.temp_dir, self._on_thumbnail_ready)

    def _bind_scrolling(self, widget):
        def _on_mousewheel(event):
            try:
                canvas = self.scroll_frame._parent_canvas
                if event.num == 4 or getattr(event, 'delta', 0) > 0:
                    canvas.yview_scroll(-1, "units")
                elif event.num == 5 or getattr(event, 'delta', 0) < 0:
                    canvas.yview_scroll(1, "units")
            except Exception:
                pass
        
        # Bind to standard tk events
        widget.bind("<MouseWheel>", _on_mousewheel, add="+")
        widget.bind("<Button-4>", _on_mousewheel, add="+")
        widget.bind("<Button-5>", _on_mousewheel, add="+")
        
        # Also bind on the inner tk widget if it's a CTk widget
        if hasattr(widget, '_canvas'):
            widget._canvas.bind("<MouseWheel>", _on_mousewheel, add="+")
            widget._canvas.bind("<Button-4>", _on_mousewheel, add="+")
            widget._canvas.bind("<Button-5>", _on_mousewheel, add="+")
        if hasattr(widget, '_label'):
            widget._label.bind("<MouseWheel>", _on_mousewheel, add="+")
            widget._label.bind("<Button-4>", _on_mousewheel, add="+")
            widget._label.bind("<Button-5>", _on_mousewheel, add="+")

    def _on_thumbnail_ready(self, f_name: str, ctk_img):
        # Must be called from main thread ideally, but CTkImage seems mostly thread-safe if applied in after()
        # We'll use after from the master
        self.master.after(0, lambda: self._apply_thumbnail(f_name, ctk_img))

    def _apply_thumbnail(self, f_name, ctk_img):
        if f_name in self.thumbnail_labels:
            lbl = self.thumbnail_labels[f_name]
            lbl.configure(text="", image=ctk_img, fg_color="transparent")

    def _on_sort_group_change(self, _=None):
        self.page = 0
        self._render()

    def set_files(self, files: List[FileInfo], remote_base_path: str):
        self.files = files
        self.remote_base_path = remote_base_path
        self._f_info_map = {f['name']: f for f in files}
        self.page = 0
        self._render()

    def update_files(self, new_files: List[FileInfo], remote_base_path: str):
        self.files = new_files
        self.remote_base_path = remote_base_path
        self._f_info_map = {f['name']: f for f in new_files}
        
        # Soft render to reuse widgets and keep scroll
        sort_val = self.sort_var.get()
        if sort_val == "Date (Newest)":
            sorted_files = sorted(self.files, key=lambda x: x['mod_time'], reverse=True)
        elif sort_val == "Date (Oldest)":
            sorted_files = sorted(self.files, key=lambda x: x['mod_time'])
        elif sort_val == "Name (A-Z)":
            sorted_files = sorted(self.files, key=lambda x: x['name'].lower())
        elif sort_val == "Size (Largest)":
            sorted_files = sorted(self.files, key=lambda x: x['size'], reverse=True)
        else:
            sorted_files = self.files

        end_idx = (self.page + 1) * self.page_size
        paginated_files = sorted_files[:end_idx]

        group_val = self.group_var.get()
        groups = {}
        if group_val == "None":
            groups["All Files"] = paginated_files
        elif group_val == "Date (Day)":
            for f in paginated_files:
                g = f['mod_time'].strftime('%Y-%m-%d')
                groups.setdefault(g, []).append(f)
        elif group_val == "Extension":
            for f in paginated_files:
                ext = os.path.splitext(f['name'])[1].lower() or "Unknown"
                groups.setdefault(ext, []).append(f)

        for w in self.header_widgets:
            w.destroy()
        self.header_widgets.clear()
        
        if hasattr(self, 'btn_load_more') and self.btn_load_more.winfo_exists():
            self.btn_load_more.destroy()

        rendered_names = set()
        row_idx = 0
        valid_exts = ('.jpg', '.jpeg', '.png', '.heic', '.webp', '.gif')

        for group_name, g_files in groups.items():
            if group_val != "None":
                lbl_group = ctk.CTkLabel(self.scroll_frame, text=group_name, font=ctk.CTkFont(size=14, weight="bold"))
                lbl_group.grid(row=row_idx, column=0, columnspan=4, sticky="w", pady=(15, 5))
                self._bind_scrolling(lbl_group)
                self.header_widgets.append(lbl_group)
                row_idx += 1
                
            for f_info in g_files:
                f_name = f_info['name']
                rendered_names.add(f_name)
                
                if f_name in self.file_widgets:
                    widgets = self.file_widgets[f_name]
                    widgets['chk'].grid(row=row_idx, column=0, padx=5, pady=5, sticky="w")
                    widgets['thumb'].grid(row=row_idx, column=1, padx=10, pady=5)
                    
                    details = f"{f_name}\nSize: {f_info['size'] // 1024} KB  |  {f_info['mod_time'].strftime('%Y-%m-%d %H:%M')}"
                    widgets['lbl'].configure(text=details)
                    widgets['lbl'].grid(row=row_idx, column=2, padx=5, pady=5, sticky="we")
                    
                    widgets['btn'].grid(row=row_idx, column=3, padx=15, pady=5, sticky="e")
                else:
                    chk_var = ctk.StringVar(value="off")
                    chk = ctk.CTkCheckBox(self.scroll_frame, text="", variable=chk_var, onvalue="on", offvalue="off", width=20, command=self.on_selection_change)
                    chk.grid(row=row_idx, column=0, padx=5, pady=5, sticky="w")
                    self._bind_scrolling(chk)
                    self.checkboxes[f_name] = chk_var

                    if f_name.lower().endswith(valid_exts):
                        thumb_lbl = ctk.CTkLabel(self.scroll_frame, text="[IMG]", width=50, height=50, fg_color="gray20", corner_radius=5)
                        self.thumbnail_loader.load(f_info, self.remote_base_path)
                    else:
                        ext = os.path.splitext(f_name)[1].lower()
                        ext_text = f"[{ext[1:].upper()}]" if ext else "[FILE]"
                        thumb_lbl = ctk.CTkLabel(self.scroll_frame, text=ext_text, width=50, height=50, fg_color="gray30", corner_radius=5)
                    
                    thumb_lbl.grid(row=row_idx, column=1, padx=10, pady=5)
                    self._bind_scrolling(thumb_lbl)
                    self.thumbnail_labels[f_name] = thumb_lbl

                    details = f"{f_name}\nSize: {f_info['size'] // 1024} KB  |  {f_info['mod_time'].strftime('%Y-%m-%d %H:%M')}"
                    lbl = ctk.CTkLabel(self.scroll_frame, text=details, anchor="w", justify="left")
                    lbl.grid(row=row_idx, column=2, padx=5, pady=5, sticky="we")
                    self._bind_scrolling(lbl)

                    full_path = f_info.get('full_path', self.remote_base_path + f_name)
                    btn_prev = ctk.CTkLabel(self.scroll_frame, text="[ Preview ]", text_color="blue", cursor="hand2")
                    btn_prev.bind("<Button-1>", lambda e, p=full_path: self.on_preview(p))
                    btn_prev.grid(row=row_idx, column=3, padx=15, pady=5, sticky="e")
                    self._bind_scrolling(btn_prev)
                    
                    self.file_widgets[f_name] = {
                        'chk': chk,
                        'thumb': thumb_lbl,
                        'lbl': lbl,
                        'btn': btn_prev
                    }
                row_idx += 1
                
        for f_name in list(self.file_widgets.keys()):
            if f_name not in rendered_names:
                widgets = self.file_widgets.pop(f_name)
                for w in widgets.values():
                    w.destroy()
                self.checkboxes.pop(f_name, None)
                self.thumbnail_labels.pop(f_name, None)

        if end_idx < len(sorted_files):
            remaining = len(sorted_files) - end_idx
            self.btn_load_more = ctk.CTkButton(self.scroll_frame, text=f"Load More ({remaining} remaining)", command=self.load_more)
            self.btn_load_more.grid(row=row_idx, column=0, columnspan=4, pady=10)
            self._bind_scrolling(self.btn_load_more)

    def append_files(self, new_files: List[FileInfo], remote_base_path: str):
        self.remote_base_path = remote_base_path
        self.files.extend(new_files)
        for f in new_files:
            self._f_info_map[f['name']] = f
        # Stream the current page (up to page_size) without duplicating
        if self.page == 0:
            if len(self.files) == len(new_files):
                # First chunk: clear and render
                self._render()
            elif len(self.files) <= self.page_size:
                # Subsequent chunks on the first page: append only the new files
                # Fake paginated_files to be just the new_files
                self._incremental_render(new_files)
        elif self.page > 0:
            # We don't want to disrupt the user's view while they are scrolling
            pass

    def load_more(self):
        self.page += 1
        self._render(append=True)

    def _incremental_render(self, new_files):
        group_val = self.group_var.get()
        items_to_render = []
        
        for f in new_files:
            if group_val == "Date (Day)":
                g = f['mod_time'].strftime('%Y-%m-%d')
            elif group_val == "Extension":
                g = os.path.splitext(f['name'])[1].lower() or "Unknown"
            else:
                g = None
                
            if g and g != getattr(self, '_last_rendered_group', None):
                items_to_render.append(("header", g))
                self._last_rendered_group = g
                
            items_to_render.append(("file", f))
            
        self._render_queue.extend(items_to_render)
        if not self._is_rendering:
            self._process_render_queue()

    def _render(self, append=False):
        # Clear existing if not appending
        if not append:
            self._render_queue.clear()
            self._is_rendering = False
            for widget in self.scroll_frame.winfo_children():
                widget.destroy()
            self.checkboxes.clear()
            self.thumbnail_labels.clear()
            self.thumbnail_loader.clear()
            self.file_widgets.clear()
            self.header_widgets.clear()
        
        if not self.files:
            ctk.CTkLabel(self.scroll_frame, text="No files found.").grid(row=0, column=0, pady=20)
            return

        # Sort
        sort_val = self.sort_var.get()
        if sort_val == "Date (Newest)":
            sorted_files = sorted(self.files, key=lambda x: x['mod_time'], reverse=True)
        elif sort_val == "Date (Oldest)":
            sorted_files = sorted(self.files, key=lambda x: x['mod_time'])
        elif sort_val == "Name (A-Z)":
            sorted_files = sorted(self.files, key=lambda x: x['name'].lower())
        elif sort_val == "Size (Largest)":
            sorted_files = sorted(self.files, key=lambda x: x['size'], reverse=True)
        else:
            sorted_files = self.files

        # Pagination
        start_idx = self.page * self.page_size
        end_idx = start_idx + self.page_size
        paginated_files = sorted_files[start_idx:end_idx]

        # Group
        group_val = self.group_var.get()
        groups = {}
        if group_val == "None":
            groups["All Files"] = paginated_files
        elif group_val == "Date (Day)":
            for f in paginated_files:
                g = f['mod_time'].strftime('%Y-%m-%d')
                groups.setdefault(g, []).append(f)
        elif group_val == "Extension":
            for f in paginated_files:
                ext = os.path.splitext(f['name'])[1].lower() or "Unknown"
                groups.setdefault(ext, []).append(f)
                
        # Render
        # Render items incrementally
        row_idx = len(self.checkboxes) * 2 + 1000 * self.page  # Safe offset for row index
        thumb_count = 0
        
        items_to_render = []
        last_group = None
        for group_name, g_files in groups.items():
            if group_val != "None":
                items_to_render.append(("header", group_name))
                last_group = group_name
            for f in g_files:
                items_to_render.append(("file", f))
                
        self._last_rendered_group = last_group
                
        if end_idx < len(sorted_files):
            items_to_render.append(("load_more", len(sorted_files) - end_idx))
            
        # Store state for chunk rendering
        self._render_queue.extend(items_to_render)
        self._current_row_idx = row_idx
        self._current_thumb_count = thumb_count
        
        if not self._is_rendering:
            self._process_render_queue()

    def _process_render_queue(self):
        if not self._render_queue:
            self._is_rendering = False
            return
            
        self._is_rendering = True
        chunk = self._render_queue[:10]
        self._render_queue = self._render_queue[10:]
        
        valid_exts = ('.jpg', '.jpeg', '.png', '.heic', '.webp', '.gif')
        
        for item in chunk:
            item_type = item[0]
            if item_type == "header":
                group_name = item[1]
                lbl_group = ctk.CTkLabel(self.scroll_frame, text=group_name, font=ctk.CTkFont(size=14, weight="bold"))
                lbl_group.grid(row=self._current_row_idx, column=0, columnspan=4, sticky="w", pady=(15, 5))
                self._bind_scrolling(lbl_group)
                self._current_row_idx += 1
            elif item_type == "file":
                f_info = item[1]
                f_name = f_info['name']
                
                chk_var = ctk.StringVar(value="off")
                chk = ctk.CTkCheckBox(self.scroll_frame, text="", variable=chk_var, onvalue="on", offvalue="off", width=20, command=self.on_selection_change)
                chk.grid(row=self._current_row_idx, column=0, padx=5, pady=5, sticky="w")
                self._bind_scrolling(chk)
                self.checkboxes[f_name] = chk_var

                if f_name.lower().endswith(valid_exts):
                    thumb_lbl = ctk.CTkLabel(self.scroll_frame, text="[IMG]", width=50, height=50, fg_color="gray20", corner_radius=5)
                    if self._current_thumb_count < 30:
                        self.thumbnail_loader.load(f_info, self.remote_base_path)
                        self._current_thumb_count += 1
                else:
                    ext = os.path.splitext(f_name)[1].lower()
                    ext_text = f"[{ext[1:].upper()}]" if ext else "[FILE]"
                    thumb_lbl = ctk.CTkLabel(self.scroll_frame, text=ext_text, width=50, height=50, fg_color="gray30", corner_radius=5)
                
                thumb_lbl.grid(row=self._current_row_idx, column=1, padx=10, pady=5)
                self._bind_scrolling(thumb_lbl)
                self.thumbnail_labels[f_name] = thumb_lbl

                details = f"{f_name}\nSize: {f_info['size'] // 1024} KB  |  {f_info['mod_time'].strftime('%Y-%m-%d %H:%M')}"
                lbl = ctk.CTkLabel(self.scroll_frame, text=details, anchor="w", justify="left")
                lbl.grid(row=self._current_row_idx, column=2, padx=5, pady=5, sticky="we")
                self._bind_scrolling(lbl)

                full_path = f_info.get('full_path', self.remote_base_path + f_name)
                btn_prev = ctk.CTkLabel(self.scroll_frame, text="[ Preview ]", text_color="blue", cursor="hand2")
                btn_prev.bind("<Button-1>", lambda e, p=full_path: self.on_preview(p))
                btn_prev.grid(row=self._current_row_idx, column=3, padx=15, pady=5, sticky="e")
                self._bind_scrolling(btn_prev)
                
                self.file_widgets[f_name] = {
                    'chk': chk,
                    'thumb': thumb_lbl,
                    'lbl': lbl,
                    'btn': btn_prev
                }
                
                self._current_row_idx += 1
            elif item_type == "load_more":
                remaining = item[1]
                if hasattr(self, 'btn_load_more') and self.btn_load_more.winfo_exists():
                    self.btn_load_more.destroy()
                self.btn_load_more = ctk.CTkButton(self.scroll_frame, text=f"Load More ({remaining} remaining)", command=self.load_more)
                self.btn_load_more.grid(row=self._current_row_idx + 1, column=0, columnspan=4, pady=10)
                self._bind_scrolling(self.btn_load_more)
                
        # Schedule next chunk
        if self._render_queue:
            self.after(5, self._process_render_queue)
        else:
            self._is_rendering = False

    def select_all(self):
        for var in self.checkboxes.values():
            var.set("on")
        self.on_selection_change()
            
    def deselect_all(self):
        for var in self.checkboxes.values():
            var.set("off")
        self.on_selection_change()

    def get_selected_files(self) -> List[str]:
        selected = []
        for f_name, var in self.checkboxes.items():
            if var.get() == "on":
                f_info = self._f_info_map.get(f_name)
                if f_info and 'full_path' in f_info:
                    selected.append(f_info['full_path'])
                else:
                    selected.append(self.remote_base_path + f_name)
        return selected
