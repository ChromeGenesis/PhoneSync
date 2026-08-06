import os
import shutil
import subprocess
import sys
import tempfile

from utils.subprocess_wrapper import patch_subprocess

patch_subprocess()


def check_adb():
    try:
        res = subprocess.run(["adb", "devices"], capture_output=True, text=True)
        if (
            "device\n" not in res.stdout
            and "device\r\n" not in res.stdout
            and "device" not in res.stdout.split()[1:]
        ):
            print("Error: No Android device connected via ADB.")
            print("Please ensure you are connected (e.g., adb connect <IP>:5555).")
            sys.exit(1)
    except FileNotFoundError:
        print("Error: ADB is not installed or not in PATH.")
        sys.exit(1)


def show_help():
    print("Usage:")
    print(
        "  python phone_sync_cli.py push [file_path]    - Send a file/folder to phone (/sdcard/Download/)"
    )
    print(
        "  python phone_sync_cli.py pull              - Interactively pull files from phone (supports PREVIEW)"
    )
    print("  python phone_sync_cli.py help              - Show this message")


def do_push(file_path):
    if not file_path:
        file_path = input("Enter the path of the file or folder to send: ").strip()

    file_path = os.path.expanduser(file_path)

    if not file_path or not os.path.exists(file_path):
        print("Error: File or folder does not exist.")
        sys.exit(1)

    dest_path = "/sdcard/Download/"
    print(f"Sending '{file_path}' to phone's Download folder...")

    res = subprocess.run(["adb", "push", file_path, dest_path])
    if res.returncode == 0:
        print("✅ Push complete!")
    else:
        print("❌ Push failed.")


def open_folder(path):
    if sys.platform == "win32":
        os.startfile(path)
    elif sys.platform == "darwin":
        subprocess.run(["open", path])
    else:
        subprocess.run(["xdg-open", path])


def do_pull():
    print("What would you like to pull from your phone?")
    print("1) Camera Photos/Videos (/sdcard/DCIM/Camera/)")
    print("2) Screenshots (/sdcard/Pictures/Screenshots/)")
    print("3) Downloads (/sdcard/Download/)")
    print("4) Custom path")
    choice = input("Enter your choice (1-4): ").strip()

    src_path = ""
    if choice == "1":
        src_path = "/sdcard/DCIM/Camera/"
    elif choice == "2":
        src_path = "/sdcard/Pictures/Screenshots/"
    elif choice == "3":
        src_path = "/sdcard/Download/"
    elif choice == "4":
        src_path = input("Enter the exact path on your phone: ").strip()
    else:
        print("Invalid choice.")
        sys.exit(1)

    if not src_path.endswith("/"):
        src_path += "/"

    preview_choice = (
        input("Do you want to preview the latest files before saving? (y/n): ")
        .strip()
        .lower()
    )

    if preview_choice == "y":
        num_files_str = input(
            "How many recent files to preview? (default: 10): "
        ).strip()
        num_files = int(num_files_str) if num_files_str.isdigit() else 10

        print(f"Fetching the {num_files} most recent files...")
        tmp_dir = tempfile.mkdtemp(prefix="adb_preview_")

        # Get latest files, handling spaces safely
        cmd = f'adb shell "ls -1t \\"{src_path}\\""'
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if res.returncode == 0:
            lines = [line.strip() for line in res.stdout.split("\n") if line.strip()]
            for filename in lines[:num_files]:
                if filename:
                    print(f"Pulling {filename} for preview...")
                    subprocess.run(
                        ["adb", "pull", f"{src_path}{filename}", tmp_dir],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )

            print("Opening preview folder. Please view the files.")
            open_folder(tmp_dir)

            print()
            input("Press Enter when you are done reviewing...")

            print("Do you want to keep these files?")
            print("1) Keep All")
            print("2) Keep None (Cancel)")
            keep_choice = input("Choice (1-2): ").strip()

            if keep_choice == "1":
                dest_dir = os.path.expanduser("~/Downloads/PhoneTransfer")
                os.makedirs(dest_dir, exist_ok=True)
                for item in os.listdir(tmp_dir):
                    shutil.move(
                        os.path.join(tmp_dir, item), os.path.join(dest_dir, item)
                    )
                print(f"✅ Files saved to {dest_dir}")
            else:
                print("❌ Canceled. Files discarded.")

        shutil.rmtree(tmp_dir, ignore_errors=True)
        sys.exit(0)

    dest_dir = os.path.expanduser("~/Downloads/PhoneTransfer")
    custom_dest = input(f"Enter destination on PC (default: {dest_dir}): ").strip()

    if custom_dest:
        dest_dir = os.path.expanduser(custom_dest)

    os.makedirs(dest_dir, exist_ok=True)
    print(f"Pulling all files from '{src_path}' to '{dest_dir}'...")
    res = subprocess.run(["adb", "pull", src_path, dest_dir])

    if res.returncode == 0:
        print("✅ Pull complete!")
    else:
        print("❌ Pull failed.")


def main():
    check_adb()
    if len(sys.argv) < 2:
        show_help()
        sys.exit(0)

    cmd = sys.argv[1]
    if cmd == "push":
        file_path = sys.argv[2] if len(sys.argv) > 2 else ""
        do_push(file_path)
    elif cmd == "pull":
        do_pull()
    else:
        show_help()


if __name__ == "__main__":
    main()
