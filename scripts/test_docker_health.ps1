$ErrorActionPreference = "Stop"

Write-Host "=== DOCKER HEALTHCHECK TIMING TEST ==="

# Build image if needed
docker build -t devops-demo:local . | Out-Null

# Clean up any existing container
docker rm -f demo-health-test 2>$null | Out-Null

$startTime = Get-Date
Write-Host "Starting container at $startTime..."
$containerId = docker run -d --name demo-health-test -p 3009:3000 devops-demo:local
Write-Host "Container started: $containerId"

try {
    for ($i = 1; $i -le 45; $i++) {
        $status = docker inspect --format '{{.State.Health.Status}}' demo-health-test
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
        Write-Host "[$elapsed s] Health status: $status"
        if ($status -eq "healthy") {
            Write-Host "CONTAINER REACHED HEALTHY STATUS AT $elapsed SECONDS!"
            break
        }
        Start-Sleep -Seconds 1
    }
} finally {
    Write-Host "Stopping and cleaning up container..."
    docker rm -f demo-health-test | Out-Null
}
