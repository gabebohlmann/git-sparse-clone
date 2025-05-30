#!/bin/bash

# This script provides a shorthand for cloning a Git repository with sparse checkout,
# including only a specified folder, with an option to include root files.
# It allows interactive folder selection via tree walking and uses 'q' to quit selection.
# Ctrl+C can be used to cancel the entire operation gracefully.

# --- User Configuration ---
# Set your preferred keyboard layout to change the ergonomic key selectors.
# Supported layouts: "qwerty", "colemak", "colemak-dh", "colemak-dh-iso", "dvorak"
KEYBOARD_LAYOUT="qwerty"

# --- Globals ---
ORIGINAL_PWD=$(pwd)
REPO_URL=""
FOLDER_TO_CLONE_ARG=""
REPO_NAME=""
TARGET_CLONE_PATH=""
DEFAULT_BRANCH=""
FOLDER_TO_CLONE="" # This will be set by argument or interactive selection
TMP_FILES=() # Array to store temp files for cleanup
ERGONOMIC_KEYS=() # Will be populated based on KEYBOARD_LAYOUT

# --- Ergonomic Key Definitions ---
# The order is: home row (l->r), top row (l->r), bottom row (l->r)
QWERTY_KEYS=('a' 's' 'd' 'f' 'g' 'h' 'j' 'k' 'l' ';' 'q' 'w' 'e' 'r' 't' 'y' 'u' 'i' 'o' 'p' 'z' 'x' 'c' 'v' 'b' 'n' 'm' ',' '.' '/')
COLEMAK_KEYS=('a' 'r' 's' 't' 'd' 'h' 'n' 'e' 'i' 'o' 'q' 'w' 'f' 'p' 'g' 'j' 'l' 'u' 'y' ';' 'z' 'x' 'c' 'v' 'b' 'k' 'm' ',' '.' '/')
COLEMAK_DH_KEYS=('a' 'r' 's' 't' 'g' 'm' 'n' 'e' 'i' 'o' 'q' 'w' 'f' 'p' 'b' 'j' 'l' 'u' 'y' ';' 'x' 'c' 'd' 'v' 'z' 'k' 'h' ',' '.' '/')
COLEMAK_DH_ISO_KEYS=('a' 'r' 's' 't' 'g' 'm' 'n' 'e' 'i' 'o' 'q' 'w' 'f' 'p' 'b' 'j' 'l' 'u' 'y' ';' 'z' 'x' 'c' 'd' 'v' 'k' 'h' ',' '.')
DVORAK_KEYS=('a' 'o' 'e' 'u' 'i' 'd' 'h' 't' 'n' 's' '-' '<' '>' 'p' 'y' 'f' 'g' 'c' 'r' 'l' ';' 'q' 'j' 'k' 'x' 'b' 'm' 'w' 'v' 'z')


# --- Helper Functions ---
show_usage() {
    echo "Usage: $0 <repository-url> [folder-to-clone]"
    echo "Clones <repository-url> and sparsely checks out [folder-to-clone]."
    echo "If [folder-to-clone] is omitted, an interactive tree walker will allow you to select a folder."
    echo "You will then be asked if you want to include root-level repository items."
    echo ""
    echo "Examples:"
    echo "  $0 https://github.com/nandorojo/solito.git apps/web"
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
    printf "Error: %s\n" "$message" # Using printf for potentially complex messages

    # The trap will call cleanup_all_temp_files
    if [ -n "$TARGET_CLONE_PATH" ] && [ -d "$TARGET_CLONE_PATH" ]; then
        # Check if the message indicates the directory already existed and user chose not to remove it
        # This is to avoid the "Cleaning up repository..." message if we are exiting because user said 'no' to removal.
        if [[ "$message" != "Operation aborted by user. Target directory not removed." ]]; then
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

# --- Main Logic ---

# Select the active key array based on configuration
case "$KEYBOARD_LAYOUT" in
    colemak)
        ERGONOMIC_KEYS=("${COLEMAK_KEYS[@]}")
        ;;
    colemak-dh)
        ERGONOMIC_KEYS=("${COLEMAK_DH_KEYS[@]}")
        ;;
    colemak-dh-iso)
        ERGONOMIC_KEYS=("${COLEMAK_DH_ISO_KEYS[@]}")
        ;;
    dvorak)
        ERGONOMIC_KEYS=("${DVORAK_KEYS[@]}")
        ;;
    *) # Default to QWERTY
        ERGONOMIC_KEYS=("${QWERTY_KEYS[@]}")
        ;;
esac

# --- Argument Parsing ---
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    show_usage
    exit 1
fi

REPO_URL="$1"
FOLDER_TO_CLONE_ARG="$2" # Might be empty

# --- Initial Setup and Checks ---
REPO_NAME_WITH_GIT=$(basename "$REPO_URL")
REPO_NAME="${REPO_NAME_WITH_GIT%.git}"

if [ -z "$REPO_NAME" ]; then
    cleanup_and_exit "Could not extract a valid repository name from the URL: '$REPO_URL'." 1
fi

TARGET_CLONE_PATH="$ORIGINAL_PWD/$REPO_NAME"

if [ -d "$TARGET_CLONE_PATH" ]; then
    echo "Target directory '$TARGET_CLONE_PATH' already exists."
    read -r -p "Do you want to remove it and continue? (y/N): " remove_confirm
    if [[ "$remove_confirm" =~ ^[Yy]$ ]]; then
        echo "Removing existing directory '$TARGET_CLONE_PATH'..."
        rm -rf "$TARGET_CLONE_PATH"
        if [ $? -ne 0 ]; then
            cleanup_and_exit "Failed to remove existing directory '$TARGET_CLONE_PATH'." 1
        fi
        echo "Directory removed."
    else
        # User chose not to remove, so we exit.
        echo "Operation aborted by user. Target directory not removed."
        exit 1 # Exit without calling cleanup_and_exit's rm -rf part
    fi
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
        # Fallback: try to pick the first non-HEAD origin branch
        DEFAULT_BRANCH=$(echo "$REMOTE_BRANCHES" | grep '\s+origin/' | grep -v 'HEAD' | head -n1 | sed -e 's/^\s*origin\///')
    fi
fi
DEFAULT_BRANCH=$(echo "$DEFAULT_BRANCH" | awk '{$1=$1};1') # Trim whitespace
if [ -z "$DEFAULT_BRANCH" ]; then
    cleanup_and_exit "Could not automatically determine the default remote branch."
fi
echo "Determined remote default branch as: '$DEFAULT_BRANCH'."

# --- Determine Folder to Clone (Interactively if not provided) ---
if [ -z "$FOLDER_TO_CLONE_ARG" ]; then
    echo "No specific folder argument provided. Starting interactive folder selection..."

    CURRENT_PATH_PARTS=() # Array of path components, e.g., ("src" "components")

    while true; do
        # 1. Construct current path string
        current_path_str=""
        current_path_display_name=""
        if [ ${#CURRENT_PATH_PARTS[@]} -eq 0 ]; then
            current_path_str="." # Represents the root of the repository
            current_path_display_name="<root>"
        else
            current_path_str=$(printf "%s/" "${CURRENT_PATH_PARTS[@]}")
            current_path_str=${current_path_str%/}
            current_path_display_name="$current_path_str"
        fi

        echo ""
        echo "Currently browsing: '$current_path_display_name' in 'origin/$DEFAULT_BRANCH'"

        # 2. Get subdirectories
        LSTREE_OUTPUT_FILE=$(create_temp_file)
        if [ "$current_path_str" == "." ]; then
            git ls-tree --name-only -d "origin/${DEFAULT_BRANCH}" . > "$LSTREE_OUTPUT_FILE" 2>/dev/null
        else
            git ls-tree --name-only -d "origin/${DEFAULT_BRANCH}:${current_path_str}" > "$LSTREE_OUTPUT_FILE" 2>/dev/null
        fi

        mapfile -t SUB_DIRS < <(cat "$LSTREE_OUTPUT_FILE")
        temp_sub_dirs=()
        for item in "${SUB_DIRS[@]}"; do
            if [[ -n "$item" ]]; then
                temp_sub_dirs+=("$item")
            fi
        done
        SUB_DIRS=("${temp_sub_dirs[@]}")

        # 3. Display the menu and get input
        echo "Choose an action:"

        # Display directories with their assigned keys
        for i in "${!SUB_DIRS[@]}"; do
            if [ "$i" -ge "${#ERGONOMIC_KEYS[@]}" ]; then
                printf "  ... (more directories available)\n"
                break
            fi
            key="${ERGONOMIC_KEYS[i]}"
            dir_name="${SUB_DIRS[i]}"
            printf "  %s) %s\n" "$key" "$dir_name"
        done

        # Display special options with static keys
        SELECT_KEY="0"
        UP_KEY="9"
        QUIT_KEY="8"

        printf "  %s) [Select this folder: %s]\n" "$SELECT_KEY" "$current_path_display_name"
        if [ ${#CURRENT_PATH_PARTS[@]} -gt 0 ]; then
            printf "  %s) [Up to parent folder]\n" "$UP_KEY"
        fi
        printf "  %s) [Quit selection]\n" "$QUIT_KEY"

        # Prompt and read input
        read -r -n 1 -p "Enter key: " user_input
        echo "" # Add a newline after the input for cleaner output

        # 4. Process the input
        if [[ "$user_input" == "$QUIT_KEY" ]]; then
            echo "Folder selection aborted by user."
            FOLDER_TO_CLONE=""
            break 2
        elif [[ "$user_input" == "$SELECT_KEY" ]]; then
            if [ "$current_path_str" == "." ]; then
                FOLDER_TO_CLONE="."
                echo "Selected repository root (.) as the target folder."
            else
                FOLDER_TO_CLONE="$current_path_str"
                echo "You selected folder: '$FOLDER_TO_CLONE'"
            fi
            break 2
        elif [[ "$user_input" == "$UP_KEY" ]] && [ ${#CURRENT_PATH_PARTS[@]} -gt 0 ]; then
            unset 'CURRENT_PATH_PARTS[${#CURRENT_PATH_PARTS[@]}-1]'
            echo "Moving up one level."
            continue
        else
            # Check if the input key corresponds to a directory
            selected_dir=""
            for i in "${!ERGONOMIC_KEYS[@]}"; do
                if [[ "$user_input" == "${ERGONOMIC_KEYS[i]}" ]]; then
                    # Check if this key is within the range of displayed options
                    if [ "$i" -lt "${#SUB_DIRS[@]}" ]; then
                        selected_dir="${SUB_DIRS[i]}"
                        break
                    fi
                fi
            done

            if [ -n "$selected_dir" ]; then
                # A valid directory key was pressed
                CURRENT_PATH_PARTS+=("$selected_dir")
            else
                # Invalid key pressed
                echo "Invalid selection: '$user_input'. Please try again."
            fi
        fi
    done

    if [ -z "$FOLDER_TO_CLONE" ] && ! [[ "$REPLY" =~ ^[Qq]$ ]]; then
        echo "Interactive selection did not result in a folder."
    fi

else
    FOLDER_TO_CLONE="$FOLDER_TO_CLONE_ARG"
    echo "Folder specified via argument: '$FOLDER_TO_CLONE'"
fi


if [ -z "$FOLDER_TO_CLONE" ]; then
    cleanup_and_exit "No folder was selected or specified. Aborting operation." 1
fi

# --- Dialog for including root items ---
LSTREE_ROOT_DIRS_STDOUT_FILE=$(create_temp_file)

# List ONLY directories at the root of the default branch
git ls-tree --name-only -d "origin/${DEFAULT_BRANCH}" . > "$LSTREE_ROOT_DIRS_STDOUT_FILE" 2>/dev/null
LSTREE_ROOT_DIRS_EXIT_CODE=$?

mapfile -t ACTUAL_ROOT_DIRECTORIES < "$LSTREE_ROOT_DIRS_STDOUT_FILE"
# Clean up empty lines from mapfile if any
temp_root_dirs=()
for item in "${ACTUAL_ROOT_DIRECTORIES[@]}"; do
    if [[ -n "$item" ]]; then
        temp_root_dirs+=("$item")
    fi
done
ACTUAL_ROOT_DIRECTORIES=("${temp_root_dirs[@]}")

reply_include_root=""
if [ "$LSTREE_ROOT_DIRS_EXIT_CODE" -eq 0 ] && [ ${#ACTUAL_ROOT_DIRECTORIES[@]} -gt 0 ]; then
    echo ""
    echo "The following top-level directories were found at the repository root:" # Changed message
    LIMITED_ITEMS_TO_SHOW=5
    count=0
    for rd in "${ACTUAL_ROOT_DIRECTORIES[@]}"; do
        echo "  - $rd"
        count=$((count + 1))
        if [ "$count" -ge "$LIMITED_ITEMS_TO_SHOW" ]; then
            if [ ${#ACTUAL_ROOT_DIRECTORIES[@]} -gt "$LIMITED_ITEMS_TO_SHOW" ]; then
                echo "  - ...and more."
            fi
            break
        fi
    done
    echo ""
    folder_display_for_prompt="$FOLDER_TO_CLONE"
    if [ "$FOLDER_TO_CLONE" == "." ]; then
        folder_display_for_prompt="<repository root>"
    fi
    # The prompt still asks about ALL root-level items (files and directories)
    prompt_message="Do you want to include ALL root-level items (files and top-level directories at the root) along with '$folder_display_for_prompt'? (y/N): "
    read -r -p "$prompt_message" reply_include_root
fi

# --- Initialize Sparse Checkout and Set Patterns based on user choice ---
SPARSE_SET_PATTERNS=()

if [[ "$reply_include_root" =~ ^[Yy]$ ]]; then
    # User explicitly said YES to include root items.
    echo "Initializing sparse-checkout in CONE mode to include '$FOLDER_TO_CLONE' AND all root-level items."
    git sparse-checkout init --cone
    if [ $? -ne 0 ]; then cleanup_and_exit "Failed to initialize sparse-checkout (cone mode)."; fi
    SPARSE_SET_PATTERNS=("$FOLDER_TO_CLONE" ".")
else
    # This block executes if:
    # 1. User explicitly said NO (or anything other than 'y'/'Y') to the dialog.
    # 2. User pressed ENTER at the dialog (reply_include_root is empty).
    # 3. The dialog was NOT shown (reply_include_root is empty because ACTUAL_ROOT_DIRECTORIES was empty).

    if [ -n "$reply_include_root" ]; then # User typed something, and it wasn't 'y' or 'Y' (e.g., 'n')
        echo "Will include ONLY '$FOLDER_TO_CLONE' and its contents (no other root items)."
    else # reply_include_root is empty. This means: dialog was skipped OR user pressed Enter.
        echo "Defaulting to not include all root-level items. Will include contents based on '$FOLDER_TO_CLONE' selection."
    fi

    echo "Initializing sparse-checkout in NON-CONE mode for precise folder selection."
    git sparse-checkout init
    if [ $? -ne 0 ]; then cleanup_and_exit "Failed to initialize sparse-checkout (non-cone mode)."; fi

    if [ "$FOLDER_TO_CLONE" == "." ]; then
        SPARSE_SET_PATTERNS=("/./")
    else
        SPARSE_SET_PATTERNS=("/${FOLDER_TO_CLONE}/")
    fi
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
printf "Patterns applied: %s\n" "${SPARSE_SET_PATTERNS[*]}"
printf "From repository '%s' (branch '%s')\n" "$REPO_URL" "$DEFAULT_BRANCH"
echo ""
printf "Repository is located at: %s\n" "$TARGET_CLONE_PATH"
# Clarify that the script operated in TARGET_CLONE_PATH and provide cd command for user
printf "Script operations completed within: %s\n" "$(pwd)" # pwd here is TARGET_CLONE_PATH
printf "To navigate here in your shell, run:\ncd %s\n" "$TARGET_CLONE_PATH"
echo "-----------------------------------------------------------------------"

exit 0
