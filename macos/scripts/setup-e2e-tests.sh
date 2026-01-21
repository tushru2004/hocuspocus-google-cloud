#!/bin/bash
#
# Setup E2E tests on MacBook Air
# Run via SimpleMDM to clone repo and install dependencies
#

set -e

# Configuration
REPO_URL="https://github.com/tushru2004/hocuspocus-google-cloud.git"
INSTALL_DIR="/Users/Shared/hocuspocus-vpn"
PYTHON_VERSION="3.11"

echo "=== Setting up E2E tests on MacBook Air ==="

# Check if Xcode Command Line Tools are installed (for git)
if ! xcode-select -p &>/dev/null; then
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install
    # Wait for installation
    sleep 30
fi

# Check if git is available
if ! command -v git &>/dev/null; then
    echo "ERROR: git not available. Install Xcode Command Line Tools first."
    exit 1
fi
echo "✅ git available"

# Check if Python 3 is available
if ! command -v python3 &>/dev/null; then
    echo "ERROR: Python 3 not found. Installing via Homebrew..."
    # Install Homebrew if not present
    if ! command -v brew &>/dev/null; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew install python@${PYTHON_VERSION}
fi
echo "✅ Python 3 available: $(python3 --version)"

# Clone or update repo
if [ -d "$INSTALL_DIR" ]; then
    echo "Updating existing repo..."
    cd "$INSTALL_DIR"
    git pull origin main || git pull origin master
else
    echo "Cloning repo..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi
echo "✅ Repo cloned to $INSTALL_DIR"

# Create virtual environment
echo "Setting up Python virtual environment..."
cd "$INSTALL_DIR"
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
echo "Installing test dependencies..."
pip install --upgrade pip
pip install pytest pytest-timeout selenium

echo "✅ Dependencies installed"

# Enable Safari WebDriver
echo "Enabling Safari WebDriver..."
safaridriver --enable 2>/dev/null || echo "Note: safaridriver may need manual enable in Safari settings"

# Create run script
cat > "$INSTALL_DIR/run-macos-tests.sh" << 'EOF'
#!/bin/bash
cd /Users/Shared/hocuspocus-vpn
source .venv/bin/activate
pytest tests/e2e_macos/test_verify_vpn.py -v -s
EOF
chmod +x "$INSTALL_DIR/run-macos-tests.sh"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To run tests on MacBook Air:"
echo "  cd $INSTALL_DIR"
echo "  ./run-macos-tests.sh"
echo ""
echo "Or manually:"
echo "  cd $INSTALL_DIR"
echo "  source .venv/bin/activate"
echo "  pytest tests/e2e_macos/test_verify_vpn.py -v -s"
