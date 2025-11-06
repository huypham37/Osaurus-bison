#!/bin/bash
# LLM Rotation Proxy Installation Script

set -e

echo "🚀 Installing LLM Rotation Proxy..."

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: Python 3 is not installed"
    echo "Please install Python 3 from https://www.python.org/downloads/"
    exit 1
fi

echo "✓ Python 3 found: $(python3 --version)"

# Check if pip3 is installed
if ! command -v pip3 &> /dev/null; then
    echo "❌ Error: pip3 is not installed"
    echo "Please install pip3 or use: python3 -m ensurepip"
    exit 1
fi

echo "✓ pip3 found"

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Install Python dependencies
echo ""
echo "📦 Installing Python dependencies..."
pip3 install -r requirements.txt

echo ""
echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "1. Edit config.yaml and add your API keys"
echo "2. Run: python3 proxy_server.py"
echo "3. The proxy will be available at http://localhost:8000"
echo ""
echo "Test with: curl http://localhost:8000/health"
