#!/bin/bash

# ==========================================
# ADB Phone Sync Utility
# ==========================================

# Check if ADB is connected
adb devices | grep -qw "device"
if [ $? -ne 0 ]; then
    echo "Error: No Android device connected via ADB."
    echo "Please ensure you are connected (e.g., adb connect <IP>:5555)."
    exit 1
fi

function show_help() {
    echo "Usage:"
    echo "  $0 push [file_path]    - Send a file/folder to phone (/sdcard/Download/)"
    echo "  $0 pull              - Interactively pull files from phone (supports PREVIEW)"
    echo "  $0 help              - Show this message"
}

function do_push() {
    file_path="$1"
    
    if [ -z "$file_path" ]; then
        read -e -p "Enter the path of the file or folder to send: " file_path
    fi
    
    # Expand tilde
    file_path="${file_path/#\~/$HOME}"
    
    if [ -z "$file_path" ] || [ ! -e "$file_path" ]; then
        echo "Error: File or folder does not exist."
        exit 1
    fi

    dest_path="/sdcard/Download/"
    echo "Sending '$file_path' to phone's Download folder..."
    adb push "$file_path" "$dest_path"
    
    if [ $? -eq 0 ]; then
        echo "✅ Push complete!"
    else
        echo "❌ Push failed."
    fi
}

function do_pull() {
    echo "What would you like to pull from your phone?"
    echo "1) Camera Photos/Videos (/sdcard/DCIM/Camera/)"
    echo "2) Screenshots (/sdcard/Pictures/Screenshots/)"
    echo "3) Downloads (/sdcard/Download/)"
    echo "4) Custom path"
    read -p "Enter your choice (1-4): " choice

    src_path=""
    case $choice in
        1) src_path="/sdcard/DCIM/Camera/" ;;
        2) 
           # Most modern phones use Pictures/Screenshots. Fallback in case.
           src_path="/sdcard/Pictures/Screenshots/" 
           ;;
        3) src_path="/sdcard/Download/" ;;
        4) read -p "Enter the exact path on your phone: " src_path ;;
        *) echo "Invalid choice."; exit 1 ;;
    esac
    
    # Ensure src_path ends with /
    [[ "${src_path}" != */ ]] && src_path="${src_path}/"

    # Preview logic
    read -p "Do you want to preview the latest files before saving? (y/n): " preview_choice
    
    if [[ "$preview_choice" == "y" || "$preview_choice" == "Y" ]]; then
        read -p "How many recent files to preview? (default: 10): " num_files
        num_files=${num_files:-10}
        
        echo "Fetching the $num_files most recent files..."
        tmp_dir=$(mktemp -d /tmp/adb_preview_XXXXXX)
        
        # Get latest files, handling spaces safely
        adb shell "ls -1t \"$src_path\"" | tr -d '\r' | head -n "$num_files" | while IFS= read -r filename; do
            if [ -n "$filename" ]; then
                echo "Pulling $filename for preview..."
                adb pull "$src_path$filename" "$tmp_dir/" >/dev/null 2>&1
            fi
        done
        
        echo "Opening preview folder. Please view the files."
        xdg-open "$tmp_dir" >/dev/null 2>&1
        
        echo ""
        read -p "Press Enter when you are done reviewing..."
        
        echo "Do you want to keep these files?"
        echo "1) Keep All"
        echo "2) Keep None (Cancel)"
        read -p "Choice (1-2): " keep_choice
        
        if [ "$keep_choice" == "1" ]; then
            dest_dir="$HOME/Downloads/PhoneTransfer"
            mkdir -p "$dest_dir"
            mv "$tmp_dir"/* "$dest_dir"/ 2>/dev/null
            echo "✅ Files saved to $dest_dir"
        else
            echo "❌ Canceled. Files discarded."
        fi
        
        # Clean up
        rm -rf "$tmp_dir"
        exit 0
    fi

    # Normal full pull
    dest_dir="$HOME/Downloads/PhoneTransfer"
    read -e -p "Enter destination on PC (default: $dest_dir): " custom_dest
    
    if [ -n "$custom_dest" ]; then
        dest_dir="${custom_dest/#\~/$HOME}"
    fi

    mkdir -p "$dest_dir"
    echo "Pulling all files from '$src_path' to '$dest_dir'..."
    adb pull "$src_path" "$dest_dir"

    if [ $? -eq 0 ]; then
        echo "✅ Pull complete!"
    else
        echo "❌ Pull failed."
    fi
}

# Main routing based on argument
case "$1" in
    push)
        do_push "$2"
        ;;
    pull)
        do_pull
        ;;
    *)
        show_help
        ;;
esac
