import time
import sys
from core.adb_client import list_files_stream

def test_stream():
    start = time.time()
    first_chunk_time = None
    
    def on_chunk(chunk):
        nonlocal first_chunk_time
        if first_chunk_time is None:
            first_chunk_time = time.time()
            print(f"Time to first chunk: {first_chunk_time - start:.3f} seconds")
            print(f"First chunk size: {len(chunk)}")
            sys.exit(0)

    print("Starting stream...")
    list_files_stream("/sdcard/DCIM/Camera/", on_chunk)
    
if __name__ == "__main__":
    test_stream()
