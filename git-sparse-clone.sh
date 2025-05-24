#!/bin/bash

# This script provides a shorthand for cloning a Git repository with sparse checkout,
# including only a specified folder, with an option to include root files.
# It allows interactive folder selection and uses 'q' to quit selection.

# --- Globals ---
ORIGINAL_PWD=$(pwd)
REPO_URL=""
FOLDER_TO_CLONE_ARG=""
REPO_NAME=""
TARGET_CLONE_PATH=""
DEFAULT_BRANCH=""
FOLDER_TO_CLONE=""
TMP_FILES=() # Array to store temp files for cleanup

# --- Helper Functions ---
show_usage() {
    echo "Usage: $0 <repository-url> [folder-to-clone]"
    echo "Clones <repository-url> and sparsely checks out [folder-to-clone]."
    echo "If [folder-to-clone] is omitted, an interactive selector will list top-level directories."
    echo "You will then be asked if you want to include root-level repository items."
    echo ""
    echo "Examples:"
    echo "  $0 https://github.com/nandorojo/solito.git apps"
    echo "  $0 https://github.com/nandorojo/solito.git"
}

cleanup_all_temp_files() {
    # echo "DEBUG: Cleaning up temp files..." # Optional for debugging
    for tmp_file in "${TMP_FILES[@]}"; do
        if [ -f "$tmp_file" ]; then
            rm -f "$tmp_file"
        fi
    done
}

cleanup_and_exit() {
    local message="$1"
    local exit_code="${2:-1}"

    echo ""
    echo "Error: $message" # For actual errors

    # The trap will call cleanup_all_temp_files
    if [ -n "$TARGET_CLONE_PATH" ] && [ -d "$TARGET_CLONE_PATH" ]; then
        echo "Cleaning up repository in '$TARGET_CLONE_PATH'..."
        current_dir_before_cd_back=$(pwd)
        if [[ "$current_dir_before_cd_back" == "$TARGET_CLONE_PATH"* ]]; then
            cd "$ORIGINAL_PWD" || echo "Warning: Failed to cd back to original directory '$ORIGINAL_PWD' during cleanup."
        fi

        rm -rf "$TARGET_CLONE_PATH"
        if [ $? -eq 0 ]; then
            echo "Cleanup successful."
        else
            echo "Warning: Cleanup of '$TARGET_CLONE_PATH' may have failed. Please check manually."
        fi
    fi
    exit "$exit_code"
}

handle_sigint() {
    echo "" # Move to a new line for cleaner output
    echo "Operation cancelled by user (Ctrl+C). Performing cleanup..."

    # Clean up the main cloned repository directory
    if [ -n "$TARGET_CLONE_PATH" ] && [ -d "$TARGET_CLONE_PATH" ]; then
        echo "Cleaning up repository in '$TARGET_CLONE_PATH'..."
        current_dir_on_ctrl_c=$(pwd)
        if [[ "$current_dir_on_ctrl_c" == "$TARGET_CLONE_PATH"* ]]; then
            cd "$ORIGINAL_PWD" || echo "Warning: Failed to cd back to original directory '$ORIGINAL_PWD' during Ctrl+C cleanup."
        fi
        rm -rf "$TARGET_CLONE_PATH"
    fi
    # The EXIT trap will still call cleanup_all_temp_files.
    exit 130 # Standard exit code for termination by Ctrl+C.
}

# Setup traps
trap cleanup_all_temp_files EXIT  # Ensures temp files are cleaned on any exit
trap handle_sigint SIGINT         # Handles Ctrl+C specifically

create_temp_file() {
    local temp_file
    temp_file=$(mktemp /tmp/sparse_clone.XXXXXX)
    TMP_FILES+=("$temp_file")
    echo "$temp_file"
}

# --- Argument Parsing ---
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    show_usage
    exit 1
fi

REPO_URL="$1"
FOLDER_TO_CLONE_ARG="$2"

# --- Initial Setup and Checks ---
REPO_NAME_WITH_GIT=$(basename "$REPO_URL")
REPO_NAME="${REPO_NAME_WITH_GIT%.git}"

if [ -z "$REPO_NAME" ]; then
    cleanup_and_exit "Could not extract a valid repository name from the URL: '$REPO_URL'." 1
fi

TARGET_CLONE_PATH="$ORIGINAL_PWD/$REPO_NAME"

if [ -d "$TARGET_CLONE_PATH" ]; then
    cleanup_and_exit "Target directory '$TARGET_CLONE_PATH' already exists. Please remove it first." 1
fi

# --- Clone Repository ---
echo "Preparing to clone from '$REPO_URL'..."
git clone --depth 1 --no-checkout --filter=blob:none "$REPO_URL" "$TARGET_CLONE_PATH"
if [ $? -ne 0 ]; then
    cleanup_and_exit "Git clone operation failed."
fi
cd "$TARGET_CLONE_PATH" || cleanup_and_exit "Failed to change directory to '$TARGET_CLONE_PATH'."

# --- Determine Default Remote Branch ---
echo "Identifying the default remote branch..."
DEFAULT_BRANCH_REF=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)
if [ -n "$DEFAULT_BRANCH_REF" ]; then
    DEFAULT_BRANCH="${DEFAULT_BRANCH_REF#refs/remotes/origin/}"
else
    REMOTE_BRANCHES=$(git branch -r)
    if echo "$REMOTE_BRANCHES" | grep -qE '\s+origin/main\b'; then
        DEFAULT_BRANCH="main"
    elif echo "$REMOTE_BRANCHES" | grep -qE '\s+origin/master\b'; then
        DEFAULT_BRANCH="master"
    else
        DEFAULT_BRANCH=$(echo "$REMOTE_BRANCHES" | grep '\s+origin/' | grep -v 'HEAD' | head -n1 | sed -e 's/^\s*origin\///')
    fi
fi
DEFAULT_BRANCH=$(echo "$DEFAULT_BRANCH" | awk '{$1=$1};1')
if [ -z "$DEFAULT_BRANCH" ]; then
    cleanup_and_exit "Could not automatically determine the default remote branch."
fi
echo "Determined remote default branch as: '$DEFAULT_BRANCH'."

# --- Determine Folder to Clone (Interactively if not provided) ---
if [ -z "$FOLDER_TO_CLONE_ARG" ]; then
    echo "No specific folder argument provided. Listing top-level directories from 'origin/$DEFAULT_BRANCH'..."

    LSTREE_DIR_STDOUT_FILE=$(create_temp_file)

    git ls-tree --name-only -d "origin/${DEFAULT_BRANCH}" . > "$LSTREE_DIR_STDOUT_FILE"
    LSTREE_DIR_EXIT_CODE=$?
    LSTREE_DIR_STDOUT=$(cat "$LSTREE_DIR_STDOUT_FILE")

    mapfile -t DIRECTORIES < <(echo -n "$LSTREE_DIR_STDOUT")

    if [ "$LSTREE_DIR_EXIT_CODE" -ne 0 ] || [ -z "$LSTREE_DIR_STDOUT" ] ; then
        cleanup_and_exit "Failed to list or found no top-level directories in 'origin/$DEFAULT_BRANCH'."
    fi

    echo ""
    echo "Available top-level folders in '$REPO_NAME' (from branch '$DEFAULT_BRANCH'):"
    PS3="Enter the number for the folder to clone (or 'q' to quit): " # Updated prompt
    select selected_folder in "${DIRECTORIES[@]}"; do
        # Check for 'q' or 'Q' first
        if [[ "$REPLY" =~ ^[Qq]$ ]]; then
            echo "Folder selection aborted by user."
            FOLDER_TO_CLONE="" # Ensure FOLDER_TO_CLONE is empty
            break # Exit the select loop
        # Then check if a valid numbered option was selected
        elif [[ -n "$selected_folder" ]]; then
            FOLDER_TO_CLONE="$selected_folder"
            echo "You selected folder: '$FOLDER_TO_CLONE'"
            break
        # Otherwise, it's an invalid input
        else
            echo "Invalid selection: '$REPLY'. Please enter a number from the list or 'q' to quit."
        fi
    done

    if [ -z "$FOLDER_TO_CLONE" ]; then
        cleanup_and_exit "No folder was selected. Aborting operation." 1
    fi
else
    FOLDER_TO_CLONE="$FOLDER_TO_CLONE_ARG"
    echo "Folder specified via argument: '$FOLDER_TO_CLONE'"
fi

# --- Dialog for including root items ---
LSTREE_ROOT_STDOUT_FILE=$(create_temp_file)
LSTREE_ROOT_STDERR_FILE=$(create_temp_file) # Used to capture stderr from ls-tree if any

git ls-tree "origin/${DEFAULT_BRANCH}" . > "$LSTREE_ROOT_STDOUT_FILE" 2> "$LSTREE_ROOT_STDERR_FILE"
LSTREE_ROOT_ITEMS_EXIT_CODE=$?
LSTREE_ROOT_ITEMS_STDOUT=$(cat "$LSTREE_ROOT_STDOUT_FILE")
LSTREE_ROOT_ITEMS_STDERR=$(cat "$LSTREE_ROOT_STDERR_FILE") # Capture stderr

mapfile -t ALL_ROOT_ENTRIES < <(echo -n "$LSTREE_ROOT_ITEMS_STDOUT")
ACTUAL_ROOT_FILES=()
if [ "$LSTREE_ROOT_ITEMS_EXIT_CODE" -eq 0 ] && [ ${#ALL_ROOT_ENTRIES[@]} -gt 0 ]; then
    for entry in "${ALL_ROOT_ENTRIES[@]}"; do
        _type=$(echo "$entry" | awk '{print $2}')
        if [[ "$entry" == *$'\t'* ]]; then
            _path=$(echo "$entry" | sed 's/^[^\t]*\t//')
        else
            _path=""
        fi
        if [ "$_type" == "blob" ] && [ -n "$_path" ]; then
            ACTUAL_ROOT_FILES+=("$_path")
        fi
    done
fi

reply_include_root="" # Default to no if dialog not shown or user presses Enter
if [ "$LSTREE_ROOT_ITEMS_EXIT_CODE" -eq 0 ] && [ ${#ACTUAL_ROOT_FILES[@]} -gt 0 ]; then
    echo ""
    echo "The following files were found at the repository root:"
    LIMITED_FILES_TO_SHOW=5
    count=0
    for rf in "${ACTUAL_ROOT_FILES[@]}"; do
        echo "  - $rf"
        count=$((count + 1))
        if [ "$count" -ge "$LIMITED_FILES_TO_SHOW" ]; then
            if [ ${#ACTUAL_ROOT_FILES[@]} -gt "$LIMITED_FILES_TO_SHOW" ]; then
                echo "  - ...and more."
            fi
            break
        fi
    done
    echo ""
    prompt_message="Do you want to include ALL root-level items (these files, plus any other files and top-level directories at the root) along with '$FOLDER_TO_CLONE'? (y/N): "
    read -r -p "$prompt_message" reply_include_root
fi

# --- Initialize Sparse Checkout and Set Patterns based on user choice ---
SPARSE_SET_PATTERNS=() 

if [[ "$reply_include_root" =~ ^[Yy]$ ]]; then
    echo "Initializing sparse-checkout in CONE mode to include '$FOLDER_TO_CLONE' AND all root-level items."
    git sparse-checkout init --cone
    if [ $? -ne 0 ]; then cleanup_and_exit "Failed to initialize sparse-checkout (cone mode)."; fi
    SPARSE_SET_PATTERNS=("$FOLDER_TO_CLONE" ".")
else
    # This block executes if user replied 'n', pressed Enter, or if no root files dialog was shown.
    if [ -n "$reply_include_root" ] && ! [[ "$reply_include_root" =~ ^[Yy]$ ]]; then # User explicitly answered something other than 'y'
        echo "Will include ONLY '$FOLDER_TO_CLONE' and its contents (no root items)."
    elif [ "$LSTREE_ROOT_ITEMS_EXIT_CODE" -ne 0 ] || ([ "$LSTREE_ROOT_ITEMS_EXIT_CODE" -eq 0 ] && [ ${#ACTUAL_ROOT_FILES[@]} -eq 0 ]); then
        echo "No root files to include or failed to list them. Will include ONLY '$FOLDER_TO_CLONE' and its contents."
    fi # If reply_include_root is empty (dialog not shown or user hit enter), this defaults to non-cone.
    
    echo "Initializing sparse-checkout in NON-CONE mode for precise folder selection."
    git sparse-checkout init # Ensures non-cone mode
    if [ $? -ne 0 ]; then cleanup_and_exit "Failed to initialize sparse-checkout (non-cone mode)."; fi
    SPARSE_SET_PATTERNS=("/${FOLDER_TO_CLONE}/")
fi

echo "Setting sparse-checkout patterns: ${SPARSE_SET_PATTERNS[*]}"
git sparse-checkout set "${SPARSE_SET_PATTERNS[@]}"
if [ $? -ne 0 ]; then
    patterns_string=$(printf "'%s' " "${SPARSE_SET_PATTERNS[@]}")
    cleanup_and_exit "Failed to set sparse-checkout for patterns: $patterns_string."
fi

# --- Checkout Files ---
echo "Checking out files for the specified patterns from branch '$DEFAULT_BRANCH'..."
git checkout "$DEFAULT_BRANCH"
if [ $? -ne 0 ]; then
    cleanup_and_exit "Failed to checkout branch '$DEFAULT_BRANCH'."
fi

echo ""
echo "-----------------------------------------------------------------------"
echo "Sparse clone and checkout completed successfully."
echo "Patterns applied: ${SPARSE_SET_PATTERNS[*]}"
echo "From repository '$REPO_URL' (branch '$DEFAULT_BRANCH')"
echo ""
echo "Repository is located at: $TARGET_CLONE_PATH"
echo "You are now inside this directory ($(pwd))."
echo "-----------------------------------------------------------------------"

exit 0