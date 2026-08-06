import json
import os

CONFIG_FILE = os.path.expanduser("~/.config/phone_sync_paths.json")


def load_saved_paths() -> list[str]:
    """Load previously saved custom paths from config."""
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return []


def save_custom_path(path: str) -> list[str]:
    """Save a new custom path to the config and return the updated list."""
    paths = load_saved_paths()
    if path not in paths:
        paths.append(path)
        _write(paths)
    return paths


def delete_saved_path(path: str) -> list[str]:
    """Remove a path from the config and return the updated list."""
    paths = [p for p in load_saved_paths() if p != path]
    _write(paths)
    return paths


def _write(paths: list[str]) -> None:
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    with open(CONFIG_FILE, "w") as f:
        json.dump(paths, f)
