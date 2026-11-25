# Ram 진화 과정 녹화: git 기록에서 단계별 코드를 꺼내, 같은 키 입력(driver.gd)을 재생해 영상으로 남긴다.
# 사용: pwsh tools/godot/evolution/record_all.ps1 [-Only 1,11] [-Godot <godot console exe>] [-Work <작업 폴더>]
#   -Only  번호를 주면 그 단계만 (stages.ps1 의 n)
#   -Godot 기본은 환경변수 GODOT, 없으면 바탕화면\Godot 의 4.7.2 콘솔 실행 파일
#   -Work  기본은 저장소의 out\evolution (out\ 은 git 이 무시한다)
# 결과: <Work>\NN_<해시>.ogv, 확인용 정지 컷 <Work>\shots\NN_<해시>_1~3.png. 단계마다 게임 창이 40초쯤 떴다 닫힌다.
# 이어서 encode_all.ps1 을 돌리면 MP4 와 비교 영상이 나온다.
param(
    [int[]]$Only = @(),
    [string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "$env:USERPROFILE\Desktop\Godot\Godot_v4.7.2-stable_win64_console.exe" }),
    [string]$Work = ''
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = (Resolve-Path "$here\..\..\..").Path
if (-not $Work) { $Work = "$repo\out\evolution" }
. "$here\stages.ps1"       # $stages: 번호, 해시, 날짜, 제목

New-Item -ItemType Directory -Force "$Work\shots", "$Work\src" | Out-Null
foreach ($s in $stages) {
    if ($Only.Count -gt 0 -and $Only -notcontains $s.n) { continue }
    $name = '{0:d2}_{1}' -f $s.n, $s.hash
    $src = "$Work\src\$name"
    if (-not (Test-Path "$src\project.godot")) {
        # 그 시점의 코드를 따로 꺼낸다 (작업 폴더와 git 상태는 건드리지 않는다)
        New-Item -ItemType Directory -Force $src | Out-Null
        git -C $repo archive --format=zip -o "$src.zip" $s.hash
        tar -xf "$src.zip" -C $src
        Remove-Item "$src.zip"
    }
    if (-not (Test-Path "$src\.godot")) {
        $p = Start-Process -FilePath $Godot -ArgumentList '--headless', '--path', $src, '--import' -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\ram_evo_import.txt" -RedirectStandardError "$env:TEMP\ram_evo_import.err"
        if (-not $p.WaitForExit(300000)) { $p.Kill(); Write-Output "$name import TIMEOUT"; continue }
    }
    $title = '"{0}/{1} · {2} · {3}"' -f $s.n, $stages.Count, $s.date, $s.title
    $out = "$Work\$name.ogv"
    Remove-Item $out -ErrorAction SilentlyContinue
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath $Godot -ArgumentList '--path', $src, '--fixed-fps', '60', '--resolution', '1280x720', '--write-movie', $out, '--script', "$here\driver.gd", '--', $title, "$Work\shots\$name" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\ram_evo_rec.txt" -RedirectStandardError "$env:TEMP\ram_evo_rec.err"
    if (-not $p.WaitForExit(300000)) { $p.Kill(); Write-Output "$name record TIMEOUT"; continue }
    $mb = if (Test-Path $out) { [math]::Round((Get-Item $out).Length / 1MB, 1) } else { 0 }
    $errs = (Get-Content "$env:TEMP\ram_evo_rec.txt", "$env:TEMP\ram_evo_rec.err" -Encoding UTF8 | Select-String -Pattern 'SCRIPT ERROR|Parse Error' | Measure-Object).Count
    Write-Output ("{0}  {1} MB  {2}s  script errors {3}" -f $name, $mb, [int]$sw.Elapsed.TotalSeconds, $errs)
}
