# scripts/test_c9_kind.ps1 - Run C9 local Kubernetes cluster test using kind

$ErrorActionPreference = "Stop"

Write-Output "=== 1. Creating kind cluster demo ==="
.\kind.exe create cluster --name demo

try {
    Write-Output "=== 2. Loading local image devops-demo:local into kind ==="
    .\kind.exe load docker-image devops-demo:local --name demo

    Write-Output "=== 3. Creating namespace staging ==="
    kubectl.exe create namespace staging

    Write-Output "=== 4. Applying deployment.yaml and service.yaml ==="
    # Remove imagePullPolicy: Always or set image to local so Kubernetes doesn't try to pull from remote
    kubectl.exe apply -n staging -f k8s/deployment.yaml
    kubectl.exe apply -n staging -f k8s/service.yaml

    Write-Output "=== 5. Setting image to devops-demo:local and setting imagePullPolicy to IfNotPresent ==="
    kubectl.exe set image deployment/myapp myapp=devops-demo:local -n staging
    # In deployment.yaml, imagePullPolicy is IfNotPresent, so local image works directly

    Write-Output "=== 6. Waiting for rollout status ==="
    kubectl.exe rollout status deployment/myapp -n staging --timeout=120s

    Write-Output "=== 7. Verifying pods ==="
    kubectl.exe get pods -n staging -o wide

    Write-Output "=== 8. Port-forward and test /healthz ==="
    $pf = Start-Process -FilePath "kubectl.exe" -ArgumentList "port-forward", "-n", "staging", "svc/myapp", "18080:80" -PassThru
    Start-Sleep -Seconds 4

    try {
        $health = curl.exe -s http://localhost:18080/healthz
        Write-Output "Healthz response via k8s service port-forward: $health"
        if ($health -like '*"status":"ok"*') {
            Write-Output "C9 Kind test: PASS"
        } else {
            Write-Output "C9 Kind test: FAILED unexpected response: $health"
        }
    } finally {
        if ($pf -and !$pf.HasExited) {
            Stop-Process -Id $pf.Id -Force
        }
    }
} finally {
    Write-Output "=== 9. Deleting kind cluster demo ==="
    .\kind.exe delete cluster --name demo
}
