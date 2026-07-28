#!/bin/bash\n\
echo ""
echo "👋 Welcome to your SICK user workspace!"
echo ""
echo "To install recommended tools, run:"
echo "  install-recommended-tools"
echo ""
echo "This script installs:"
echo "  • docker-io & docker-compose  - for container management"
echo "  • Go & Go tools (grpcurl, gopls, delve) - for gRPC testing and development"
echo "  • curl, openssh, git          - essential tools (e.g., SCP, scripting)"

# Show workspace management commands
workspace help
