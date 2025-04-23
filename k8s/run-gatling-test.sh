#!/bin/bash

set -e

# Default values
SIMULATION_CLASS="computerdatabase.ComputerDatabaseSimulation"
TEST_JAR="performance-tests-pack.jar"
NAMESPACE="performance-framework"

# Display help information
function show_help {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -s, --simulation-class  Gatling simulation class (default: computerdatabase.ComputerDatabaseSimulation)"
  echo "  -j, --jar-path          Path to Gatling test JAR file (default: ./performance-tests-pack.jar)"
  echo "  -n, --namespace         Kubernetes namespace (default: performance-framework)"
  echo "  -h, --help              Show this help message"
  echo ""
  echo "Example:"
  echo "  $0 -s my.CustomSimulation -j ./my-tests.jar"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -s|--simulation-class)
      SIMULATION_CLASS="$2"
      shift 2
      ;;
    -j|--jar-path)
      TEST_JAR="$2"
      shift 2
      ;;
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

# Check if JAR file exists
if [[ ! -f "$TEST_JAR" ]]; then
  echo "Error: Test JAR file not found at $TEST_JAR"
  exit 1
fi

echo "📊 Starting Gatling performance test"
echo "  - Simulation class: $SIMULATION_CLASS"
echo "  - Test JAR: $TEST_JAR"
echo "  - Namespace: $NAMESPACE"

# Create unique job name with timestamp
JOB_NAME="gatling-test-$(date +%Y%m%d%H%M%S)"

# Upload the JAR to a ConfigMap
echo "🔄 Creating ConfigMap for the test JAR..."
kubectl create configmap performance-tests-pack --from-file=performance-tests-pack.jar="$TEST_JAR" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create a new job based on the template
echo "🚀 Creating Kubernetes job..."
cat k8s-gatling-job.yaml | \
  sed "s/name: gatling-test/name: $JOB_NAME/" | \
  sed "s/computerdatabase.ComputerDatabaseSimulation/$SIMULATION_CLASS/" | \
  kubectl apply -f -

# Follow the logs
echo "📋 Following job logs (press Ctrl+C to stop watching logs)..."
echo "---"
sleep 2
kubectl logs -f "job/$JOB_NAME" -n "$NAMESPACE"

echo "✅ Test job submitted. To clean up the job later, run:"
echo "kubectl delete job $JOB_NAME -n $NAMESPACE"