import subprocess
from datetime import datetime
from typing import TypedDict


class FileInfo(TypedDict):
    name: str
    size: int
    mod_time: datetime
    is_dir: bool


def is_connected() -> bool:
    """Check if an ADB device is connected."""
    try:
        res = subprocess.run(["adb", "devices"], capture_output=True, text=True)
        lines = res.stdout.strip().split("\n")[1:]
        return any(line.strip().endswith("device") for line in lines if line.strip())
    except Exception:
        return False


import concurrent.futures


def auto_connect(progress_callback=None) -> bool:
    """Attempt to connect to known IPs simultaneously if not connected."""
    if is_connected():
        return True

    ips_to_try = ["192.168.0.2", "192.168.0.4", "192.168.0.1", "192.168.0.3"]
    if progress_callback:
        progress_callback("Scanning local IPs...")

    def try_connect(ip):
        subprocess.run(["adb", "connect", f"{ip}:5555"], capture_output=True)
        return is_connected()

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(ips_to_try)) as executor:
        futures = {executor.submit(try_connect, ip): ip for ip in ips_to_try}
        for future in concurrent.futures.as_completed(futures):
            if future.result():
                # We found a connection, cancel others if possible (not strictly supported in ThreadPoolExecutor,
                # but they will finish quickly in the background)
                return True

    return False


def get_device_name() -> str:
    """Fetch the device name via ADB."""
    try:
        res = subprocess.run(
            ["adb", "shell", "getprop", "ro.product.model"],
            capture_output=True,
            text=True,
            check=True,
        )
        name = res.stdout.strip()
        return name if name else "Unknown Device"
    except Exception:
        return "Unknown Device"


def _process_stat_chunk(remote_path, names, chunk_callback):
    safe_paths = []
    for name in names:
        safe_name = name.replace("'", "'\\''")
        if remote_path == "RECENTS":
            full_path = safe_name
        elif remote_path.endswith("/"):
            full_path = f"{remote_path}{safe_name}"
        else:
            full_path = f"{remote_path}/{safe_name}"
        safe_paths.append(f"'{full_path}'")

    cmd = "stat -c '%Y:%s:%F:%n' " + " ".join(safe_paths)
    res = subprocess.run(["adb", "shell", cmd], capture_output=True, text=True)

    chunk = []
    for line in res.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split(":", 3)
        if len(parts) == 4:
            ts_str, size_str, type_str, fpath = parts
            is_dir = "directory" in type_str.lower()
            try:
                mod_time = datetime.fromtimestamp(int(ts_str))
            except ValueError:
                mod_time = datetime.now()
            try:
                size = int(size_str)
            except ValueError:
                size = 0

            fname = fpath.split("/")[-1]
            chunk.append(
                {
                    "name": fname,
                    "size": size,
                    "mod_time": mod_time,
                    "is_dir": is_dir,
                    "full_path": fpath,
                }
            )

    if chunk:
        chunk_callback(chunk)


def list_files_stream(remote_path: str, chunk_callback):
    """
    Fetch files from a remote path using `adb shell ls -1t` (fast stream) and stat them in batches.
    """
    try:
        paths_to_scan = [remote_path]
        if remote_path == "SCREENSHOTS":
            paths_to_scan = [
                "/sdcard/DCIM/Screenshots/",
                "/sdcard/Pictures/Screenshots/",
                "/sdcard/DCIM/VideoCaptures/",
            ]

        for path in paths_to_scan:
            proc = subprocess.Popen(
                ["adb", "shell", f"ls -1t '{path}' 2>/dev/null"],
                stdout=subprocess.PIPE,
                text=True,
                bufsize=1,
            )
            chunk_names = []

            for line in proc.stdout:
                name = line.strip()
                if (
                    not name
                    or name.startswith("ls: ")
                    or "No such file" in name
                    or name.startswith("total ")
                ):
                    continue

                chunk_names.append(name)
                if len(chunk_names) >= 5:
                    _process_stat_chunk(path, chunk_names, chunk_callback)
                    chunk_names = []

            if chunk_names:
                _process_stat_chunk(path, chunk_names, chunk_callback)

            proc.wait()
    except Exception as e:
        print(f"Error streaming files: {e}")


def list_recents_stream(chunk_callback):
    """
    Fetch recent files globally.
    """
    try:
        # Use content query to get all recently modified files instantly, fallback to find if needed
        cmd = 'content query --uri content://media/external/file --projection _data --sort "date_modified DESC" | head -n 200'
        proc = subprocess.Popen(
            ["adb", "shell", cmd], stdout=subprocess.PIPE, text=True, bufsize=1
        )

        chunk_names = []
        for line in proc.stdout:
            if "_data=" in line:
                path = line.split("_data=")[-1].strip()
                if path and not path.endswith("/"):
                    path = path.replace("/storage/emulated/0", "/sdcard")
                    chunk_names.append(path)
                    if len(chunk_names) >= 10:
                        _process_stat_chunk("RECENTS", chunk_names, chunk_callback)
                        chunk_names = []

        if chunk_names:
            _process_stat_chunk("RECENTS", chunk_names, chunk_callback)

        proc.wait()
    except Exception as e:
        print(f"Error streaming recents: {e}")


def pull_file(remote_path: str, local_path: str) -> bool:
    try:
        subprocess.run(
            ["adb", "pull", remote_path, local_path], check=True, capture_output=True
        )
        return True
    except subprocess.CalledProcessError:
        return False


def push_file(local_path: str, remote_path: str) -> bool:
    try:
        subprocess.run(
            ["adb", "push", local_path, remote_path], check=True, capture_output=True
        )
        return True
    except subprocess.CalledProcessError:
        return False


def get_sdcard_subdirs() -> list[str]:
    """Fetch 1st-level directories under /sdcard/ on the connected phone."""
    try:
        res = subprocess.run(
            ["adb", "shell", "ls -d /sdcard/*/ 2>/dev/null"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if res.returncode == 0 and res.stdout.strip():
            dirs = []
            for line in res.stdout.splitlines():
                line = line.strip()
                if line.startswith("/sdcard/") and line.endswith("/"):
                    dirs.append(line)
            if dirs:
                return sorted(dirs)
    except Exception:
        pass

    return [
        "/sdcard/DCIM/",
        "/sdcard/Download/",
        "/sdcard/Pictures/",
        "/sdcard/Music/",
        "/sdcard/Movies/",
        "/sdcard/Documents/",
        "/sdcard/WhatsApp/",
        "/sdcard/Android/",
    ]
