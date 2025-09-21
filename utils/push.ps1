param (
    [string]$msg
)

Write-Host "adding"
git add .
Write-Host "commiting"
git commit -m "$msg"
Write-Host "Pushing"
git push