# Advanced Git Sparse Clone (`git-sparse-clone.sh`)

This Bash script provides an enhanced way to clone a Git repository using sparse checkout. It allows you to clone only a specific folder (even nested ones) from a repository, and optionally, all other root-level files and directories. This is particularly useful for large monorepos where you only need a subset of the codebase.

The script offers both command-line arguments for direct specification and an interactive, ergonomic, keyboard-driven tree-walking interface for selecting folders. It also handles cases where the target directory already exists by prompting for removal.

## Features

* **Sparse Checkout**: Clones only specified parts of a repository, saving bandwidth and disk space.
* **Targeted Folder Cloning**: Specify a single folder (top-level or nested) to clone.
* **Interactive Tree-Walking Folder Selection**: If no folder is specified as an argument, the script launches an interactive browser:
    * Navigate through the repository's directory structure.
    * Select the current directory, go up to the parent, or quit.
* **Ergonomic Keyboard Navigation**:
    * Folder selection uses an ergonomic key mapping based on your chosen keyboard layout (QWERTY, Colemak, Colemak-DH, Colemak-DH-ISO, Dvorak).
    * Keys are assigned based on home row, then top row, then bottom row for quick access.
    * Dedicated number keys for actions: `0` (Select current), `9` (Up), `8` (Quit).
* **Root Item Inclusion**: Interactively decide whether to include all root-level files and other top-level directories along with your selected folder.
    * If root items are included, uses Git's **cone mode** for the selected folder and the repository root.
    * If root items are *not* included, uses Git's **non-cone mode** to strictly limit the checkout to the selected folder and its contents.
* **Existing Directory Handling**: Prompts to remove the target directory if it already exists, allowing for a clean clone.
* **Automatic Default Branch Detection**: Identifies the default branch of the remote repository.
* **Error Handling and Cleanup**: Provides informative error messages and cleans up partial clones on failure or cancellation.

## Prerequisites

* **Bash**: The script is written for Bash.
* **Git**: Version 2.25 or newer is recommended for full sparse checkout functionality (especially cone mode).
* Standard Unix utilities like `mktemp`, `awk`, `sed`, `grep`, `basename`, `head`, `read`.

## Installation

1.  **Download the script**:
    Save the script content as `git-sparse-clone.sh` (or any other name you prefer) on your system.

    ```
    wget [https://raw.githubusercontent.com/gabebohlmann/git-sparse-clone/main/git-sparse-clone.sh](https://raw.githubusercontent.com/gabebohlmann/git-sparse-clone/main/git-sparse-clone.sh)
    chmod +x git-sparse-clone.sh
    ```

    *(Replace the URL with the actual raw file URL if it differs.)*

2.  **Make it executable**:

    ```
    chmod +x git-sparse-clone.sh
    ```

3.  **Place it in your PATH (Optional but Recommended)**:
    For easier access, you can move the script to a directory listed in your system's `PATH` environment variable (e.g., `/usr/local/bin` or `~/bin`).

    ```
    # Example:
    # 1. Ensure ~/bin exists and is in your PATH:
    mkdir -p ~/bin
    # Add to ~/.bashrc or ~/.zshrc (if not already present and run `source ~/.bashrc` or `source ~/.zshrc`):
    # export PATH="$HOME/bin:$PATH"
    
    # 2. Move the script (optionally rename it):
    mv git-sparse-clone.sh ~/bin/git-sparse-clone 
    # Now you can run it as `git-sparse-clone`
    ```

## Usage

The script is run from the command line:


git-sparse-clone  [folder-to-clone]


* `<repository-url>`: **Required**. The URL of the Git repository.
* `[folder-to-clone]`: **Optional**. The path to the specific folder you want to clone (e.g., `apps/web` or `src/components`).
    * If omitted, the script enters interactive folder selection mode.

### Interactive Mode

If `[folder-to-clone]` is not provided:

1.  The script will display a list of directories in the current path, starting at the repository root.
2.  Each directory will be assigned an ergonomic key (e.g., `a`, `s`, `d`...).
3.  Special actions are mapped to number keys:
    * `0`: Select the current directory as the final target.
    * `9`: Navigate up to the parent directory.
    * `8`: Quit the folder selection process.
4.  Press the key corresponding to the directory you want to enter or the action you want to perform.

## Configuration

### Keyboard Layout

At the top of the `git-sparse-clone.sh` script, you can set the `KEYBOARD_LAYOUT` variable to match your preferred keyboard layout for the ergonomic selectors in interactive mode:

--- User Configuration ---
Set your preferred keyboard layout to change the ergonomic key selectors.
Supported layouts: "qwerty", "colemak", "colemak-dh", "colemak-dh-iso", "dvorak"
KEYBOARD_LAYOUT="qwerty"
Change `"qwerty"` to your desired layout (e.g., `"colemak-dh"`).

## TODO

* Fix issue with displaying files with a prepended `.` such as `.yarnrc.yml` (currently, the root item *preview* lists only directories, but the *prompt* to include all root items still considers files correctly).
* Consider adding an option to specify the target clone directory name.
* Explore pagination or a "more" option if the number of directories exceeds available ergonomic keys.

