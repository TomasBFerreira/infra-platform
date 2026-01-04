#!/bin/bash
set -e

# GitHub Actions Self-Hosted Runner Installation Script
# Run this script on your l-ct-dev1 host

echo "========================================="
echo "GitHub Actions Self-Hosted Runner Setup"
echo "========================================="

# Configuration
RUNNER_VERSION="2.321.0"  # Update to latest version from https://github.com/actions/runner/releases
RUNNER_HOME="/opt/github-runner"
RUNNER_USER="github-runner"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root (use sudo)"
  exit 1
fi

# Create runner user if it doesn't exist
if ! id "$RUNNER_USER" &>/dev/null; then
  echo "Creating $RUNNER_USER user..."
  useradd -m -s /bin/bash "$RUNNER_USER"
  usermod -aG docker "$RUNNER_USER"  # Add to docker group if needed
fi

# Create runner directory
echo "Creating runner directory at $RUNNER_HOME..."
mkdir -p "$RUNNER_HOME"
cd "$RUNNER_HOME"

# Download and extract runner
if [ ! -f "bin/Runner.Listener" ]; then
  echo "Downloading GitHub Actions runner v${RUNNER_VERSION}..."
  curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
  
  echo "Extracting runner..."
  tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
  rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
fi

# Install dependencies
echo "Installing dependencies..."
./bin/installdependencies.sh

# Set ownership
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME"

echo ""
echo "========================================="
echo "Runner installation complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Go to your GitHub repository: https://github.com/<YOUR_ORG>/<YOUR_REPO>/settings/actions/runners/new"
echo "2. Copy the registration token"
echo "3. Run the following commands as the github-runner user:"
echo ""
echo "   sudo su - $RUNNER_USER"
echo "   cd $RUNNER_HOME"
echo "   ./config.sh --url https://github.com/<YOUR_ORG>/<YOUR_REPO> --token <YOUR_TOKEN>"
echo ""
echo "4. Install as a service (run as root):"
echo "   sudo ./svc.sh install $RUNNER_USER"
echo "   sudo ./svc.sh start"
echo "   sudo ./svc.sh status"
echo ""
echo "5. To check runner logs:"
echo "   sudo journalctl -u actions.runner.* -f"
echo ""
