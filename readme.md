# Advanced Git Sparse Clone (`git-sparse-clone.sh`)

This Bash script provides an enhanced way to clone a Git repository using sparse checkout. It allows you to clone only a specific folder from a repository, and optionally, all other root-level files and directories. This is particularly useful for large monorepos where you only need a subset of the codebase.

The script offers both command-line arguments for direct specification and interactive prompts for selecting folders and choosing whether to include root-level items.



## Features

* **Sparse Checkout**: Clones only specified parts of a repository, saving bandwidth and disk space.
* **Targeted Folder Cloning**: Specify a single top-level folder to clone.
* **Interactive Folder Selection**: If no folder is specified, the script lists available top-level directories from the remote repository for you to choose.
* **Root Item Inclusion**: Interactively decide whether to include all root-level files and other top-level directories along with your selected folder.
    * If root items are included, uses Git's **cone mode** for the selected folder and the repository root.
    * If root items are *not* included, uses Git's **non-cone mode** to strictly limit the checkout to the selected folder and its contents.
* **Automatic Default Branch Detection**: Identifies the default branch of the remote repository.
* **Error Handling and Cleanup**: Provides informative error messages and cleans up partial clones on failure.

## Prerequisites

* **Bash**: The script is written for Bash.
* **Git**: Version 2.25 or newer is recommended for full sparse checkout functionality (especially cone mode). The script will attempt to use features that provide the best experience with modern Git.
* Standard Unix utilities like `mktemp`, `awk`, `sed`, `grep`, `basename`, `head`.

## Installation

1.  **Download the script**:
    Save the script content as `git-sparse-clone.sh` (or any other name you prefer) on your system.

    ```bash
    # Example:
    # wget [https://raw.githubusercontent.com/gabebohlmann/git-sparse-clone/main/git-sparse-clone.sh](https://raw.githubusercontent.com/gabebohlmann/git-sparse-clone/main/git-sparse-clone.sh)
    # chmod +x git-sparse-clone.sh
    ```
    (Replace the URL with the actual raw file URL once you publish it.)

2.  **Make it executable**:
    ```bash
    chmod +x git-sparse-clone.sh
    ```

3.  **Place it in your PATH (Optional)**:
    For easier access, you can move the script to a directory listed in your system's `PATH` environment variable (e.g., `/usr/local/bin` or `~/bin`).
    ```bash
    # Example:
    # mkdir -p ~/bin
    # mv git-sparse-clone.sh ~/bin/
    # # Ensure ~/bin is in your PATH (add to .bashrc, .zshrc, etc. if not)
    # # export PATH="$HOME/bin:$PATH"
    ```
    If you do this, you can run the script as `git-sparse-clone.sh` instead of `./git-sparse-clone.sh`.

## Usage

The script is run from the command line with the following syntax:

```bash
./git-sparse-clone.sh <repository-url> [folder-to-clone]