import time
from core.adb_client import list_files_stream, list_recents_stream

def test_camera_latency():
    print("Testing latency for /sdcard/DCIM/Camera/ ...")
    start = time.time()
    first_chunk_time = None
    total_files = 0
    
    def on_chunk(chunk):
        nonlocal first_chunk_time, total_files
        if first_chunk_time is None:
            first_chunk_time = time.time()
            print(f"Time to first 50 files: {first_chunk_time - start:.3f} seconds!")
        total_files += len(chunk)

    list_files_stream("/sdcard/DCIM/Camera/", on_chunk)
    print(f"Total files processed: {total_files}")
    print(f"Total time for all files: {time.time() - start:.3f} seconds\n")

def test_recents_latency():
    print("Testing latency for RECENTS (global search) ...")
    start = time.time()
    first_chunk_time = None
    total_files = 0
    
    def on_chunk(chunk):
        nonlocal first_chunk_time, total_files
        if first_chunk_time is None:
            first_chunk_time = time.time()
            print(f"Time to first 50 recent files: {first_chunk_time - start:.3f} seconds!")
        total_files += len(chunk)

    list_recents_stream(on_chunk)
    print(f"Total recent files: {total_files}")
    print(f"Total time for recents: {time.time() - start:.3f} seconds")

if __name__ == "__main__":
    test_camera_latency()
    test_recents_latency()
