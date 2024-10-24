param(
    [int]$VSVersion = 70,
    [string]$TargetFolder = ".\mpv-vsrife",
    [switch]$Python38,
    [switch]$Unattended
)


function Download-GitHubAsset {
    param (
        [string]$Repo,          # The GitHub repository in the form "owner/repo"
        [string]$AssetPattern,  # The pattern to match specific asset
        [string]$OutputFile     # filename for the downloaded asset
    )
    $apiUrl = "https://api.github.com/repos/$Repo/releases"

    try {
        $releases = Invoke-RestMethod -Uri $apiUrl -Headers @{ 'User-Agent' = 'PowerShellScript' }
        foreach ($release in $releases) {
            foreach ($asset in $release.assets) {
                if ($asset.name -like $AssetPattern) {
                    $downloadUrl = $asset.browser_download_url
                    Write-Host "Found: $($asset.name)"
                    
                    Invoke-WebRequest -Uri $downloadUrl -OutFile $OutputFile
                    return
                }
            }
        }
        Write-Host "No matching asset found for pattern '$AssetPattern' in repo '$Repo'."
    } catch {
        Write-Host "Error fetching releases for repo '$Repo': $_"
    }
}


$PythonVersionMajor = 3
$PythonVersionMid = 12
$PythonVersionMinor = 6


if ($Python38 -or ([System.Environment]::OSVersion.Version.Major -lt 10)) {
    $Python38 = $true
    $PythonVersionMid = 8
    $PythonVersionMinor = 10
}

$DownloadFolder = "$TargetFolder\vs-temp-dl"

$ProgressPreference = 'SilentlyContinue'
$VSGithubVersion = "Unknown"

if (!$Unattended -and (Test-Path -Path @("$TargetFolder\portable.vs") -PathType Leaf)) {
    $Answer = Read-Host "There appears to already exist a portable VapourSynth install in the target directory."
}

Write-Host "Fetching latest version information..."

$ErrorActionPreference = "SilentlyContinue"

$GithubVersion = Invoke-WebRequest -Uri "https://api.github.com/repos/vapoursynth/vapoursynth/releases" | ConvertFrom-Json 

foreach ($Version in $GithubVersion) {
    if (-Not ($Version.prerelease)) {
        $VSGithubVersion = $Version.name
        break
    }
}

Write-Host "Installing..."

New-Item -Path "$TargetFolder" -ItemType Directory -Force | Out-Null
if (-Not (Test-Path "$TargetFolder")) {
    Write-Host "Could not create '$TargetFolder' folder, aboring"
    exit 1
}

Write-Host "Determining latest Python $PythonVersionMajor.$PythonVersionMid.x version..."

for ($i = $PythonVersionMinor + 1; $i -le 10; $i++) {
    $PyUri = "https://www.python.org/ftp/python/$PythonVersionMajor.$PythonVersionMid.$i/python-$PythonVersionMajor.$PythonVersionMid.$i-embed-amd64.zip"
    try {
        $PythonReply = Invoke-WebRequest -Uri $PyUri -Method head
        $PythonVersionMinor = $i
    } catch {
        break
    }
}

Write-Host "Python version $PythonVersionMajor.$PythonVersionMid.$PythonVersionMinor will be used for installation"

Start-Sleep -Second 2

New-Item -Path "$DownloadFolder" -ItemType Directory -Force | Out-Null

$ProgressPreference = 'Continue'

Write-Host "Downloading Python..."
Invoke-WebRequest -Uri "https://www.python.org/ftp/python/$PythonVersionMajor.$PythonVersionMid.$PythonVersionMinor/python-$PythonVersionMajor.$PythonVersionMid.$PythonVersionMinor-embed-amd64.zip" -OutFile "$DownloadFolder\python-$PythonVersionMajor.$PythonVersionMid.$PythonVersionMinor-embed-amd64.zip"
Write-Host "Downloading VapourSynth..."
Invoke-WebRequest -Uri "https://github.com/vapoursynth/vapoursynth/releases/download/R$VSVersion/VapourSynth64-Portable-R$VSVersion.zip" -OutFile "$DownloadFolder\VapourSynth64-Portable-R$VSVersion.zip"
Write-Host "Downloading Pip..."
Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile "$DownloadFolder\get-pip.py"

# Expand-Archive requires the global scope variable to be set and not just the local one because why not?
$global:ProgressPreference = 'SilentlyContinue'

Write-Host "Extracting Python..."
Expand-Archive -LiteralPath "$DownloadFolder\python-$PythonVersionMajor.$PythonVersionMid.$PythonVersionMinor-embed-amd64.zip" -DestinationPath "$TargetFolder" -Force
Add-Content -Path "$TargetFolder\python$PythonVersionMajor$PythonVersionMid._pth" -Encoding UTF8 -Value "vs-scripts" | Out-Null
Add-Content -Path "$TargetFolder\python$PythonVersionMajor$PythonVersionMid._pth" -Encoding UTF8 -Value "Lib\site-packages" | Out-Null
New-Item -Path "$TargetFolder\vs-plugins" -ItemType Directory -Force | Out-Null
New-Item -Path "$TargetFolder\vs-scripts" -ItemType Directory -Force | Out-Null
Write-Host "Installing Pip..."
& "$TargetFolder\python.exe" "$DownloadFolder\get-pip.py" "--no-warn-script-location"
Remove-Item -Path "$TargetFolder\Scripts\*.exe"
Write-Host "Extracting VapourSynth..."
Expand-Archive -LiteralPath "$DownloadFolder\VapourSynth64-Portable-R$VSVersion.zip" -DestinationPath "$TargetFolder" -Force
if ($Python38) {
    Move-Item -Path "$TargetFolder\VSScriptPython38.dll" -Destination "$TargetFolder\VSScript.dll" -Force
} else {
    Remove-Item -Path "$TargetFolder\VSScriptPython38.dll"
}
Write-Host "Installing VapourSynth..."
& "$TargetFolder\python.exe" "-m" "pip" "install" "$TargetFolder\wheel\VapourSynth-$VSVersion-cp$PythonVersionMajor$PythonVersionMid-cp$PythonVersionMajor$PythonVersionMid-win_amd64.whl" 


Write-Host "Installing vsrife requirements..."

& "$TargetFolder\python.exe" "-m" "pip" "install" "pillow" "fastrlock" "setuptools" "wheel" "nvidia_stub" "hatchling" "--upgrade" "--no-warn-script-location"

& "$TargetFolder\python.exe" "-m" "pip" "install" `
	"https://download.pytorch.org/whl/nightly/cu124/torch-2.6.0.dev20241017%2Bcu124-cp312-cp312-win_amd64.whl" `
	"https://download.pytorch.org/whl/nightly/cu124/torchvision-0.20.0.dev20241018%2Bcu124-cp312-cp312-win_amd64.whl" `
	"https://download.pytorch.org/whl/nightly/cu124/torch_tensorrt-2.6.0.dev20241018%2Bcu124-cp312-cp312-win_amd64.whl" `
	"https://pypi.nvidia.com/tensorrt/tensorrt-10.0.0b6-py2.py3-none-win_amd64.whl" `
	"https://pypi.nvidia.com/nvidia-cuda-runtime-cu12/nvidia_cuda_runtime_cu12-12.6.77-py3-none-win_amd64.whl" `
	"cupy-cuda12x" `
	"tensorrt-cu12==10.3.0" `
	"tensorrt-cu12-bindings==10.3.0" `
	"tensorrt-cu12-libs==10.3.0" `
	"--upgrade" "--no-deps" "--no-warn-script-location"


Write-Host "Installing vsrife..."

& "$TargetFolder\python.exe" "-m" "pip" "install" "https://github.com/HolyWu/vs-rife/archive/refs/heads/master.zip" "--upgrade" "--no-warn-script-location"
& "$TargetFolder\python.exe" "-m" "vsrife"

Write-Host "Downloading mpv..."
Download-GitHubAsset -Repo "shinchiro/mpv-winbuild-cmake" -AssetPattern "*mpv-x86_64-v3*.7z" -OutputFile "$DownloadFolder\mpv.7z"
Write-Host "Extracting mpv..."
& "$TargetFolder\7z.exe" "e" "-y" "$DownloadFolder\mpv.7z" "-o$TargetFolder" | Out-Null

Write-Host "Downloading bestsource..."
Download-GitHubAsset -Repo "vapoursynth/bestsource" -AssetPattern "*.7z" -OutputFile "$DownloadFolder\bestsource.7z"
Write-Host "Extracting bestsource..."
& "$TargetFolder\7z.exe" "e" "-y" "$DownloadFolder\bestsource.7z" "-o$TargetFolder\vs-plugins" | Out-Null


Write-Host "Extracting Python..."

Write-Host "Testing vsrife..."

$Script = @'
import vapoursynth as vs
core = vs.core
from vsrife import rife

clip = clip = core.std.BlankClip(width=1920, height=1080, format=vs.RGBH, length=30 * 24)
clip = rife(clip, model='4.6', factor_num=2, trt=True, num_streams=2, trt_optimization_level=3)
clip = core.resize.Point(clip, format=vs.YUV420P16, matrix_s='709', range_s='limited')
clip.set_output()
'@

Set-Content -Path "$TargetFolder\vs-scripts\test.vpy" -Value $Script
& "$TargetFolder\vspipe.exe" "$TargetFolder\vs-scripts\test.vpy" "--progress" "."

Write-Host "Creating default mpv vapoursynth script $TargetFolder\portable_config\mpv_vsrife.vpy"
New-Item -Path "$TargetFolder\portable_config" -ItemType Directory -Force | Out-Null

$VsrifeScript= @'
import vapoursynth as vs
from vsrife import rife
core = vs.core
core.num_threads = 4

clip = video_in

clip = core.resize.Bilinear(clip, format=vs.RGBH, matrix_in_s='709', range_in_s='limited')

clip = rife(clip, model='4.6', factor_num=2, trt=True, num_streams=2, trt_optimization_level=3)

clip = core.resize.Point(clip, format=vs.YUV420P8, matrix_s='709', range_s='limited')

clip.set_output()
'@

Set-Content -Path "$TargetFolder\portable_config\mpv_vsrife.vpy" -Value $VsrifeScript

Write-Host "Creating default mpv config $TargetFolder\portable_config\mpv.conf"
New-Item -Path "$TargetFolder\portable_config" -ItemType Directory -Force | Out-Null

$MpvConfig = @'
vf=vapoursynth=~~home/mpv_vsrife.vpy:4:8

video-sync = audio
vo = gpu-next
hwdec = no
gpu-api = d3d11
gpu-context = d3d11
'@

Set-Content -Path "$TargetFolder\portable_config\mpv.conf" -Value $MpvConfig

Remove-Item -Path "$DownloadFolder" -Recurse -Force

Write-Host "Installation complete" -ForegroundColor Green

if (!$Unattended) {
    pause
}