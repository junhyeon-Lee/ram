# Ram — Windows PC 세팅 (Godot 4.7.2 + 저장소)
# 사용: PowerShell 에 이 파일 내용을 붙여 넣거나, 저장소를 받은 뒤 `powershell -ExecutionPolicy Bypass -File tools\setup_windows.ps1`
# 하는 일: Git 없으면 설치 → 바탕화면\Godot 에 Godot 4.7.2 → 바탕화면\home\ram 에 저장소(있으면 pull) → 에디터로 열기

$ProgressPreference = 'SilentlyContinue'
$Desk     = [Environment]::GetFolderPath('Desktop')
$GodotDir = Join-Path $Desk 'Godot'
$GodotExe = Join-Path $GodotDir 'Godot_v4.7.2-stable_win64.exe'
$Repo     = Join-Path $Desk 'home\ram'   # 바탕화면\home = 게임 프로젝트 보관 폴더

# 1) Git 이 없으면 설치
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    winget install --id Git.Git -e --source winget
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}

# 2) Godot 4.7.2 받기
if (-not (Test-Path $GodotExe)) {
    New-Item -ItemType Directory -Force $GodotDir | Out-Null
    $zip = Join-Path $env:TEMP 'godot472.zip'
    Invoke-WebRequest 'https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip' -OutFile $zip
    Expand-Archive $zip -DestinationPath $GodotDir -Force
    Remove-Item $zip
}

# 3) 저장소 받기 (비공개: 처음에 GitHub 로그인 창이 뜬다)
if (Test-Path (Join-Path $Repo '.git')) { git -C $Repo pull } else { git clone https://github.com/junhyeon-Lee/ram $Repo }

# 4) Godot 에디터로 프로젝트 열기 (F5 로 실행)
& $GodotExe --path $Repo -e
