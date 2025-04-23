#!/bin/bash

set -e

# Function to display section headers
section() {
  echo ""
  echo "===================================================================="
  echo "  $1"
  echo "===================================================================="
  echo ""
}

# Check if minikube is running
check_minikube() {
  if ! minikube status > /dev/null 2>&1; then
    echo "❌ Minikube is not running!"
    echo "   Start it with: minikube start"
    exit 1
  fi
}

# Make sure the x2i binary is available
check_x2i() {
  if [ ! -f "x2i/x2i" ]; then
    echo "❌ The x2i binary is missing or not in the expected location!"
    echo "   Make sure the x2i binary is at ./x2i/x2i"
    exit 1
  fi
}

section "🔍 Checking prerequisites"
check_minikube
check_x2i
echo "✅ Prerequisites satisfied"

section "🌐 Creating Kubernetes namespace"
kubectl apply -f k8s-namespace.yaml

section "💾 Creating ConfigMaps"
kubectl apply -f k8s-configmaps.yaml

section "⚙️ Creating storage resources"
kubectl apply -f k8s-storage.yaml

section "🚀 Deploying infrastructure components"
kubectl apply -f k8s-services.yaml
kubectl apply -f k8s-deployments.yaml

section "⏱️ Waiting for deployments to be ready"
echo "This may take a few minutes..."
kubectl -n performance-framework wait --for=condition=available --timeout=300s deployment/nginx
kubectl -n performance-framework wait --for=condition=available --timeout=300s deployment/telegraf
kubectl -n performance-framework wait --for=condition=available --timeout=300s deployment/zookeeper
kubectl -n performance-framework wait --for=condition=available --timeout=300s deployment/kafka

section "🔄 Creating Ingress for external access"
# Create a simple ingress for the NGINX service
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: performance-framework-ingress
  namespace: performance-framework
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: performance.test
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx
            port:
              number: 8089
EOF

# Add the hostname to /etc/hosts if running locally
if [ -z "$CI" ]; then
  MINIKUBE_IP=$(minikube ip)
  echo "ℹ️ To access the framework locally, add this line to your /etc/hosts:"
  echo "   $MINIKUBE_IP performance.test"
fi

section "📊 Setting up x2i"
# Copy the x2i tool to a ConfigMap
echo "Creating ConfigMap for x2i binaries..."
kubectl create configmap x2i-binary -n performance-framework --from-file=x2i=./x2i/x2i

section "✅ Setup complete!"
echo ""
echo "Your performance testing framework is now deployed to Minikube!"
echo ""
echo "To run a Gatling test:"
echo "1. Place your Gatling test JAR in this directory"
echo "2. Run: ./run-gatling-test.sh -j ./your-test-jar.jar -s your.SimulationClass"
echo ""
echo "Useful commands:"
echo "- kubectl get all -n performance-framework"
echo "- kubectl logs -f deployment/nginx -n performance-framework"
echo "- kubectl logs -f deployment/telegraf -n performance-framework"
echo ""
echo "To access the Gatling results, use port forwarding:"
echo "kubectl port-forward service/nginx 8089:8089 -n performance-framework"