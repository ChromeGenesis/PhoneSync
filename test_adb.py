import subprocess

cmd = "find /sdcard/DCIM /sdcard/Pictures /sdcard/Download -maxdepth 3 -type f -mtime -14 2>/dev/null | head -n 200"
proc = subprocess.Popen(
    ["adb", "shell", cmd], stdout=subprocess.PIPE, text=True, bufsize=1
)
chunk_names = []
for line in proc.stdout:
    path = line.strip()
    if path:
        chunk_names.append(path)
print("Got total paths:", len(chunk_names))
