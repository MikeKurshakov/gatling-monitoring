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

# Check if helm is installed
check_helm() {
  if ! command -v helm &> /dev/null; then
    echo "❌ Helm is not installed!"
    echo "   Install Helm from: https://helm.sh/docs/intro/install/"
    echo "   Or run: curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && chmod 700 get_helm.sh && ./get_helm.sh"
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
check_helm
check_x2i
echo "✅ Prerequisites satisfied"

section "🌐 Creating Kubernetes namespace"
kubectl apply -f k8s-namespace.yaml

section "💾 Creating ConfigMaps"
kubectl apply -f k8s-configmaps.yaml

section "⚙️ Creating storage resources"
kubectl apply -f k8s-storage.yaml

section "🚀 Setting up Kafka with Helm"
# Add Bitnami repo if not already added
if ! helm repo list | grep -q bitnami; then
  echo "Adding Bitnami Helm repository..."
  helm repo add bitnami https://charts.bitnami.com/bitnami
fi

# Update repositories
helm repo update

# Install Kafka using Bitnami chart in KRaft mode
echo "Installing Kafka using Helm chart..."
helm upgrade --install kafka bitnami/kafka \
  --namespace performance-framework \
  --values kafka-values.yaml \
  --wait --timeout 5m

section "🚀 Deploying other infrastructure components"
kubectl apply -f k8s-services.yaml

# Apply only the nginx and telegraf deployments (skipping kafka and zookeeper)
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: performance-framework
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 8089
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d/default.conf
          subPath: default.conf
          readOnly: true
        readinessProbe:
          httpGet:
            path: /healthcheck
            port: 8089
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /healthcheck
            port: 8089
          initialDelaySeconds: 15
          periodSeconds: 20
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-config
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: telegraf
  namespace: performance-framework
spec:
  replicas: 0
  selector:
    matchLabels:
      app: telegraf
  template:
    metadata:
      labels:
        app: telegraf
    spec:
      containers:
      - name: telegraf
        image: telegraf:latest
        ports:
        - containerPort: 8088
        volumeMounts:
        - name: telegraf-config
          mountPath: /etc/telegraf/telegraf.conf
          subPath: telegraf.conf
          readOnly: true
        - name: telegraf-inputs
          mountPath: /etc/telegraf/telegraf.d/inputs.influxdb_listener.8087.x2i_gatling.conf
          subPath: inputs.influxdb_listener.conf
          readOnly: true
        - name: telegraf-outputs
          mountPath: /etc/telegraf/telegraf.d/outputs.kafka.conf
          subPath: outputs.kafka.conf
          readOnly: true
        readinessProbe:
          httpGet:
            path: /ping
            port: 8088
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /ping
            port: 8088
          initialDelaySeconds: 15
          periodSeconds: 20
      volumes:
      - name: telegraf-config
        configMap:
          name: telegraf-config
          items:
          - key: telegraf.conf
            path: telegraf.conf
      - name: telegraf-inputs
        configMap:
          name: telegraf-config
          items:
          - key: inputs.influxdb_listener.conf
            path: inputs.influxdb_listener.conf
      - name: telegraf-outputs
        configMap:
          name: telegraf-config
          items:
          - key: outputs.kafka.conf
            path: outputs.kafka.conf
      - name: metrics-volume
        emptyDir: {}
EOF

section "⏱️ Waiting for deployments to be ready"
echo "Waiting for Nginx deployment..."
kubectl -n performance-framework wait --for=condition=available --timeout=300s deployment/nginx

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
kubectl create configmap x2i-binary -n performance-framework --from-file=x2i=./x2i/x2i --dry-run=client -o yaml | kubectl apply -f -

section "✅ Setup complete!"
echo ""
echo "Your performance testing framework is now deployed to Minikube!"
echo ""
echo "To test Kafka functionality:"
echo "kubectl exec -it -n performance-framework $(kubectl get pods -n performance-framework -l app.kubernetes.io/name=kafka -o jsonpath='{.items[0].metadata.name}') -- kafka-topics.sh --list --bootstrap-server localhost:9092"
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