import subprocess
import sys

_original_run = subprocess.run
_original_popen = subprocess.Popen


def patch_subprocess():
    """
    Monkey-patch subprocess on Windows to append CREATE_NO_WINDOW
    to prevent command prompt spamming.
    """
    if sys.platform == "win32":
        CREATE_NO_WINDOW = 0x08000000

        def _run(*args, **kwargs):
            if "creationflags" not in kwargs:
                kwargs["creationflags"] = CREATE_NO_WINDOW
            return _original_run(*args, **kwargs)

        def _popen(*args, **kwargs):
            if "creationflags" not in kwargs:
                kwargs["creationflags"] = CREATE_NO_WINDOW
            return _original_popen(*args, **kwargs)

        subprocess.run = _run
        subprocess.Popen = _popen
