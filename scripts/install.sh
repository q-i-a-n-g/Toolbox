#!/bin/bash

set -e

echo "=========================================="
echo "Installing project dependencies"
echo "=========================================="

# Check if we're in the right directory
if [ ! -f "Check_App/package.json" ]; then
    echo "Error: Run this script from the project root directory"
    exit 1
fi

# Install Node dependencies (Check_App)
echo ""
echo "📦 Installing Node dependencies (Check_App)..."
cd Check_App
npm install
cd ..

# Install Python dependencies (Check_App)
echo ""
echo "🐍 Installing Python dependencies (Check_App)..."
pip install -r Check_App/requirements.txt

# Install Playwright browsers
echo ""
echo "🌐 Installing Playwright browsers..."
npx playwright install

echo ""
echo "=========================================="
echo "✅ All dependencies installed successfully!"
echo "=========================================="
