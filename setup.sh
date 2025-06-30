#!/bin/bash

# AWX Complete Setup Script for Fresh Debian 12
# This script installs Docker, Kubernetes (k3s), and AWX Operator
# Run as root or with sudo privileges

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    warn "Running as root. This is fine but not recommended for production."
fi

log "Starting AWX installation on Debian 12..."

# Update system
log "Updating system packages..."
apt update && apt upgrade -y

# Install required packages
log "Installing required packages..."
apt install -y \
    curl \
    wget \
    git \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    jq \
    htop \
    vim \
    unzip

# Note: Docker not needed - k3s includes containerd runtime
log "Skipping Docker installation (k3s includes container runtime)"

# Install kubectl
log "Installing kubectl..."
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/
else
    log "kubectl already installed."
fi

# Install k3s (lightweight Kubernetes)
log "Installing k3s..."
if ! command -v k3s &> /dev/null; then
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -s -
    
    # Wait for k3s to be ready
    log "Waiting for k3s to be ready..."
    while ! kubectl get nodes &> /dev/null; do
        sleep 5
    done
    
    # Set up kubeconfig for non-root user
    if [[ $EUID -ne 0 ]] && [[ -n "$SUDO_USER" ]]; then
        mkdir -p /home/$SUDO_USER/.kube
        cp /etc/rancher/k3s/k3s.yaml /home/$SUDO_USER/.kube/config
        chown $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.kube/config
        chmod 600 /home/$SUDO_USER/.kube/config
    fi
    
    # Also create kubeconfig in /root/.kube for root access
    mkdir -p /root/.kube
    cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
    chmod 600 /root/.kube/config
    
    # Set KUBECONFIG environment variable
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
else
    log "k3s already installed."
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
fi

# Verify k3s is running
log "Verifying k3s cluster..."
kubectl get nodes
if [ $? -ne 0 ]; then
    error "k3s cluster is not ready"
fi

# Install kustomize
log "Installing kustomize..."
if ! command -v kustomize &> /dev/null; then
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    mv kustomize /usr/local/bin/
else
    log "kustomize already installed."
fi

# Create AWX namespace
log "Creating AWX namespace..."
kubectl create namespace awx --dry-run=client -o yaml | kubectl apply -f -

# Get the latest AWX operator version
log "Getting latest AWX operator version..."
AWX_OPERATOR_VERSION=$(curl -s https://api.github.com/repos/ansible/awx-operator/releases/latest | jq -r .tag_name)
log "Using AWX operator version: $AWX_OPERATOR_VERSION"

# Create kustomization file for AWX operator
log "Creating AWX operator kustomization..."
cat > /tmp/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=${AWX_OPERATOR_VERSION}

images:
  - name: quay.io/ansible/awx-operator
    newTag: ${AWX_OPERATOR_VERSION}

namespace: awx
EOF

# Deploy AWX operator
log "Deploying AWX operator..."
kubectl apply -k /tmp/kustomization.yaml

# Wait for operator to be ready
log "Waiting for AWX operator to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/awx-operator-controller-manager -n awx

# Create AWX instance configuration
log "Creating AWX instance..."
cat > /tmp/awx-demo.yaml << EOF
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-demo
  namespace: awx
spec:
  service_type: nodeport
  nodeport_port: 30080
  admin_user: admin
  admin_email: admin@example.com
  postgres_storage_class: local-path
  postgres_storage_requirements:
    requests:
      storage: 8Gi
  projects_storage_class: local-path
  projects_storage_size: 8Gi
  projects_storage_access_mode: ReadWriteOnce
EOF

kubectl apply -f /tmp/awx-demo.yaml

# Wait for AWX to be ready
log "Waiting for AWX to be deployed (this may take 5-10 minutes)..."
log "You can monitor progress with: kubectl logs -f deployment/awx-operator-controller-manager -n awx -c awx-manager"

# Wait for AWX pods to be ready
kubectl wait --for=condition=ready --timeout=600s pod -l app.kubernetes.io/name=awx-demo -n awx

# Get AWX admin password
log "Getting AWX admin password..."
sleep 10  # Wait a bit for secret to be created
AWX_PASSWORD=$(kubectl get secret awx-demo-admin-password -o jsonpath="{.data.password}" -n awx | base64 --decode)

# Get node IP for access
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Create info file
cat > /root/awx-info.txt << EOF
==================================================
AWX Installation Complete!
==================================================

Access URL: http://$NODE_IP:30080
Username: admin
Password: $AWX_PASSWORD

Kubernetes Commands:
- Check AWX status: kubectl get all -n awx
- Get AWX logs: kubectl logs -f deployment/awx-demo-web -n awx
- Get operator logs: kubectl logs -f deployment/awx-operator-controller-manager -n awx -c awx-manager

Files created:
- /tmp/kustomization.yaml (AWX operator config)
- /tmp/awx-demo.yaml (AWX instance config)
- /root/awx-info.txt (this file)

To access from other machines, you may need to:
1. Open firewall port 30080
2. Use the server's external IP instead of $NODE_IP

==================================================
EOF

# Display completion message
log "AWX installation completed successfully!"
echo ""
cat /root/awx-info.txt
echo ""

log "Checking AWX deployment status..."
kubectl get all -n awx

# Final verification
log "Performing final verification..."
if curl -s --connect-timeout 10 http://localhost:30080 > /dev/null; then
    log "✅ AWX is accessible at http://$NODE_IP:30080"
else
    warn "AWX may still be starting up. Please wait a few more minutes and try accessing http://$NODE_IP:30080"
fi

log "🎉 Installation script completed! Check /root/awx-info.txt for connection details."
