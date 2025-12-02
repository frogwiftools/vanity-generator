#!/usr/bin/env bash

# Vanity Address Generator for Solana
# Cross-platform script for macOS, Linux, and Windows (WSL/Git Bash)
#
# Usage:
#   ./vanity-generator.sh --suffix <ray|pump|bonk|custom> --count <number> --threads <number>
#
# Examples:
#   ./vanity-generator.sh --suffix ray --count 5 --threads 8
#   ./vanity-generator.sh --suffix pump --count 10 --threads 16
#   ./vanity-generator.sh -s bonk -c 3 -t 4

# Don't use set -e as it causes issues with curl | bash
# set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
SUFFIX=""
COUNT=1
THREADS=4

# Print colored output
print_error() {
    echo -e "${RED}Error: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_info() {
    echo -e "${CYAN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Linux*)     OS="linux";;
        Darwin*)    OS="macos";;
        CYGWIN*|MINGW*|MSYS*) OS="windows";;
        *)          OS="unknown";;
    esac
    echo "$OS"
}

# Detect shell type
detect_shell() {
    if [ -n "$ZSH_VERSION" ]; then
        echo "zsh"
    elif [ -n "$BASH_VERSION" ]; then
        echo "bash"
    else
        echo "sh"
    fi
}

# Get shell config file
get_shell_config() {
    local shell_type=$(detect_shell)
    local os=$(detect_os)

    case "$shell_type" in
        zsh)
            echo "$HOME/.zshrc"
            ;;
        bash)
            if [ "$os" = "macos" ]; then
                # macOS uses .bash_profile for login shells
                if [ -f "$HOME/.bash_profile" ]; then
                    echo "$HOME/.bash_profile"
                else
                    echo "$HOME/.bashrc"
                fi
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        *)
            echo "$HOME/.profile"
            ;;
    esac
}

# Check if Solana CLI is installed
check_solana_installed() {
    if command -v solana-keygen &> /dev/null; then
        return 0
    fi

    # Check if it exists in the default install location but not in PATH
    if [ -f "$HOME/.local/share/solana/install/active_release/bin/solana-keygen" ]; then
        return 1  # Installed but not in PATH
    fi

    return 2  # Not installed
}

# Install Solana CLI
install_solana() {
    print_info "Installing Solana CLI tools..."
    print_info "This may take a few minutes..."
    echo ""

    local os=$(detect_os)

    case "$os" in
        macos|linux)
            print_info "Downloading and installing Solana..."
            # Run the installer and capture output
            if ! curl --proto '=https' --tlsv1.2 -sSfL https://solana-install.solana.workers.dev | bash; then
                print_error "Solana installation failed!"
                print_info "Try installing manually:"
                print_info "  curl --proto '=https' --tlsv1.2 -sSfL https://solana-install.solana.workers.dev | bash"
                exit 1
            fi
            ;;
        windows)
            print_info "For Windows, please follow the installation instructions at:"
            print_info "https://solana.com/docs/intro/installation"
            print_warning "If using WSL, the script will attempt Linux installation."
            if ! curl --proto '=https' --tlsv1.2 -sSfL https://solana-install.solana.workers.dev | bash; then
                print_error "Solana installation failed!"
                exit 1
            fi
            ;;
        *)
            print_error "Unsupported OS: $os"
            exit 1
            ;;
    esac

    echo ""
    print_success "Solana CLI installed successfully!"
}

# Setup PATH for Solana
setup_path() {
    local solana_bin="$HOME/.local/share/solana/install/active_release/bin"
    local shell_config=$(get_shell_config)
    local path_export="export PATH=\"$solana_bin:\$PATH\""

    # Add to current session
    export PATH="$solana_bin:$PATH"

    # Check if already in shell config
    if grep -q "solana/install/active_release/bin" "$shell_config" 2>/dev/null; then
        print_info "Solana PATH already configured in $shell_config"
    else
        print_info "Adding Solana to PATH in $shell_config"
        echo "" >> "$shell_config"
        echo "# Solana CLI" >> "$shell_config"
        echo "$path_export" >> "$shell_config"
        print_success "PATH updated in $shell_config"
        print_warning "Run 'source $shell_config' or restart your terminal for permanent PATH changes"
    fi
}

# Setup Cargo environment if needed
setup_cargo_env() {
    if [ -f "$HOME/.cargo/env" ]; then
        . "$HOME/.cargo/env"
    fi
}

# Check if jq is installed
check_jq_installed() {
    if command -v jq &> /dev/null; then
        return 0
    fi
    return 1
}

# Install jq based on OS
install_jq() {
    local os=$(detect_os)
    print_info "Installing jq..."

    case "$os" in
        macos)
            if command -v brew &> /dev/null; then
                brew install jq
            else
                print_error "Homebrew not found. Please install jq manually: brew install jq"
                return 1
            fi
            ;;
        linux)
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y jq
            elif command -v yum &> /dev/null; then
                sudo yum install -y jq
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y jq
            elif command -v pacman &> /dev/null; then
                sudo pacman -S --noconfirm jq
            else
                print_error "Could not detect package manager. Please install jq manually."
                return 1
            fi
            ;;
        windows)
            print_warning "On Windows/WSL, please install jq manually:"
            print_info "  apt-get install jq  (for WSL/Ubuntu)"
            print_info "  choco install jq    (for Chocolatey)"
            return 1
            ;;
        *)
            print_error "Unsupported OS for automatic jq installation"
            return 1
            ;;
    esac

    print_success "jq installed successfully!"
    return 0
}

# Merge generated JSON files and convert to base58 private keys
merge_and_convert() {
    local suffix="$1"
    local date_str=$(date +%Y%m%d-%H%M%S)
    local merged_file="merged-vanities-${suffix}-${date_str}.json"
    local keys_file="${suffix}-vanities-${date_str}.txt"

    # Find all generated JSON files for this suffix
    local json_files=$(ls *"$suffix".json 2>/dev/null || true)

    if [ -z "$json_files" ]; then
        print_warning "No keypair files found matching *${suffix}.json"
        return 1
    fi

    # Check if jq is available for merging
    if ! check_jq_installed; then
        print_warning "jq not found. Attempting to install..."
        if ! install_jq; then
            print_warning "Could not install jq. Skipping merge step."
            print_info "You can manually merge files with: jq -s '.' *${suffix}.json > merged-vanities.json"
            return 1
        fi
    fi

    echo ""
    print_info "Merging keypair files..."

    # Merge all JSON files into one array
    jq -s '.' *"$suffix".json > "$merged_file"
    print_success "Merged keypairs saved to: $merged_file"

    # Convert to base58 private keys
    echo ""
    print_info "Converting to base58 private keys..."

    # Use a Python script to convert the merged JSON to base58 private keys
    if command -v python3 &> /dev/null; then
        python3 << EOF
import json
import sys

# Base58 alphabet used by Bitcoin/Solana
ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'

def base58_encode(data):
    """Encode bytes to base58 string"""
    # Count leading zeros
    leading_zeros = 0
    for byte in data:
        if byte == 0:
            leading_zeros += 1
        else:
            break

    # Convert bytes to integer
    num = int.from_bytes(data, 'big')

    # Convert to base58
    result = ''
    while num > 0:
        num, remainder = divmod(num, 58)
        result = ALPHABET[remainder] + result

    # Add leading '1's for each leading zero byte
    return '1' * leading_zeros + result

try:
    with open('$merged_file', 'r') as f:
        keypairs = json.load(f)

    with open('$keys_file', 'w') as out:
        for i, keypair in enumerate(keypairs):
            # keypair is an array of 64 bytes (secret key)
            secret_key_bytes = bytes(keypair)
            private_key_b58 = base58_encode(secret_key_bytes)
            out.write(private_key_b58 + '\n')
            print(f"Key {i+1}: {private_key_b58[:20]}...{private_key_b58[-8:]}")

    print(f"\nTotal: {len(keypairs)} private keys converted")
except Exception as e:
    print(f"Error converting keys: {e}", file=sys.stderr)
    sys.exit(1)
EOF
        print_success "Private keys saved to: $keys_file"

        # Clean up intermediate files
        rm -f "$merged_file"
        rm -f *"$suffix".json
        print_info "Cleaned up intermediate JSON files"
    else
        print_warning "Python3 not found. Skipping base58 conversion."
        print_info "Use the print-vanity-keys script to convert:"
        print_info "  npx nx scripts run --script=print-vanity-keys --params=\"$merged_file\""
    fi

    return 0
}

# Show usage
show_usage() {
    echo ""
    echo "Solana Vanity Address Generator"
    echo "================================"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --suffix <value>    Suffix for the vanity address (required)"
    echo "                          Preset options: ray, pump, bonk"
    echo "                          Or specify any custom suffix"
    echo "  -c, --count <number>    Number of addresses to generate (default: 1)"
    echo "  -t, --threads <number>  Number of CPU threads to use (default: 4)"
    echo "  -h, --help              Show this help message"
    echo "  --install-only          Only install Solana CLI, don't generate"
    echo "  --no-merge              Skip merging and converting keypairs"
    echo ""
    echo "Examples:"
    echo "  $0 --suffix ray --count 5 --threads 8"
    echo "  $0 -s pump -c 10 -t 16"
    echo "  $0 --suffix bonk --count 3"
    echo "  $0 --suffix abc123 --count 1 --threads 4"
    echo ""
    echo "Output files:"
    echo "  - Private keys (base58): <suffix>-vanities-<date>.txt"
    echo ""
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--suffix)
                SUFFIX="$2"
                shift 2
                ;;
            -c|--count)
                COUNT="$2"
                shift 2
                ;;
            -t|--threads)
                THREADS="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            --install-only)
                INSTALL_ONLY=true
                shift
                ;;
            --no-merge)
                NO_MERGE=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Validate arguments
validate_args() {
    if [ -z "$SUFFIX" ] && [ "$INSTALL_ONLY" != "true" ]; then
        print_error "Suffix is required"
        show_usage
        exit 1
    fi

    # Validate count is a positive integer
    if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -lt 1 ]; then
        print_error "Count must be a positive integer"
        exit 1
    fi

    # Validate threads is a positive integer
    if ! [[ "$THREADS" =~ ^[0-9]+$ ]] || [ "$THREADS" -lt 1 ]; then
        print_error "Threads must be a positive integer"
        exit 1
    fi
}

# Main execution
main() {
    parse_args "$@"

    echo ""
    print_info "========================================="
    print_info "   Solana Vanity Address Generator"
    print_info "========================================="
    echo ""

    # Detect environment
    local os=$(detect_os)
    local shell_type=$(detect_shell)
    print_info "Detected OS: $os"
    print_info "Detected Shell: $shell_type"
    echo ""

    # Setup cargo environment
    setup_cargo_env

    # Check if Solana is installed
    check_solana_installed
    local install_status=$?

    if [ $install_status -eq 2 ]; then
        print_warning "Solana CLI not found. Installing..."
        install_solana
        setup_path
        # Source the new PATH for this session
        export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
    elif [ $install_status -eq 1 ]; then
        print_warning "Solana CLI installed but not in PATH. Setting up PATH..."
        setup_path
        # Source the new PATH for this session
        export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
    else
        print_success "Solana CLI already installed and in PATH"
    fi

    # Verify installation
    if ! command -v solana-keygen &> /dev/null; then
        # Try the direct path as fallback
        if [ -f "$HOME/.local/share/solana/install/active_release/bin/solana-keygen" ]; then
            export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
            print_info "Added Solana to PATH for this session"
        else
            print_error "solana-keygen not found after installation"
            print_info "Please restart your terminal or run:"
            print_info "  source $(get_shell_config)"
            print_info ""
            print_info "Then run this script again."
            exit 1
        fi
    fi

    # Show version
    print_info "Solana CLI version: $(solana --version 2>/dev/null || echo 'unknown')"
    echo ""

    # Exit if install-only mode
    if [ "$INSTALL_ONLY" = "true" ]; then
        print_success "Installation complete!"
        exit 0
    fi

    # Validate arguments for generation
    validate_args

    # Display generation parameters
    echo ""
    print_info "Generation Parameters:"
    print_info "  Suffix: $SUFFIX"
    print_info "  Count: $COUNT"
    print_info "  Threads: $THREADS"
    echo ""

    # Estimate time warning for complex suffixes
    local suffix_len=${#SUFFIX}
    if [ $suffix_len -gt 4 ]; then
        print_warning "Note: Longer suffixes take exponentially longer to find."
        print_warning "A $suffix_len-character suffix may take a significant amount of time."
        echo ""
    fi

    # Run the keygen command
    print_info "Starting vanity address generation..."
    print_info "Press Ctrl+C to stop early"
    echo ""

    # The grind command will output found keypairs to files
    solana-keygen grind --ends-with "$SUFFIX:$COUNT" --num-threads "$THREADS"

    echo ""
    print_success "Generation complete!"
    print_info "Keypair files have been saved in the current directory"

    # List generated files
    local generated_files=$(ls -la *"$SUFFIX".json 2>/dev/null || true)
    if [ -n "$generated_files" ]; then
        echo ""
        print_info "Generated keypair files:"
        echo "$generated_files"
    fi

    # Merge and convert unless --no-merge was specified
    if [ "$NO_MERGE" != "true" ]; then
        merge_and_convert "$SUFFIX"
    else
        print_info "Skipping merge step (--no-merge flag specified)"
    fi

    echo ""
    print_success "All done!"
}

# Run main function with all arguments
main "$@"
