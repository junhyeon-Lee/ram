# record_all.ps1 로 찍은 OGV 를 MP4 로 바꾸고, 한 편으로 이은 영상과 나란히 비교 영상을 만든다.
# 사용: pwsh tools/godot/evolution/encode_all.ps1 [-Work <작업 폴더>] [-Ffmpeg <ffmpeg exe>] [-Python <python exe>]
#   ffmpeg 는 -Ffmpeg, 없으면 PATH 의 ffmpeg, 그것도 없으면 파이썬 패키지 imageio-ffmpeg 에 든 것을 쓴다
#   (pip install imageio-ffmpeg — 받는 파일 약 31MB, 설치 뒤 100MB).
# 결과: <Work>\mp4\NN_<해시>.mp4, <Work>\ram_evolution_all.mp4(전체 이어 보기),
#       <Work>\ram_first_vs_now.mp4(첫 판과 마지막 판 좌우), <Work>\ram_four_stages.mp4(1·6·9·마지막 2×2)
param([string]$Work = '', [string]$Ffmpeg = '', [string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = (Resolve-Path "$here\..\..\..").Path
if (-not $Work) { $Work = "$repo\out\evolution" }
$ff = $Ffmpeg
if (-not $ff) { $ff = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source }
if (-not $ff) { $ff = & $Python -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())" }
New-Item -ItemType Directory -Force "$Work\mp4" | Out-Null

$list = @()
foreach ($f in Get-ChildItem $Work -Filter '??_*.ogv' | Sort-Object Name) {
    $mp4 = "$Work\mp4\$($f.BaseName).mp4"
    & $ff -y -loglevel error -i $f.FullName -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p -r 60 -c:a aac -b:a 128k -ar 48000 -movflags +faststart $mp4
    $list += "file '$($mp4 -replace '\\','/')'"
    Write-Output ("{0}  {1} MB" -f $f.BaseName, [math]::Round((Get-Item $mp4).Length / 1MB, 1))
}

# 한 편으로 잇기 (모두 같은 설정으로 만들었으니 다시 압축하지 않고 붙인다)
$txt = "$Work\mp4\_list.txt"
[IO.File]::WriteAllLines($txt, $list, (New-Object Text.UTF8Encoding $false))
& $ff -y -loglevel error -f concat -safe 0 -i $txt -c copy -movflags +faststart "$Work\ram_evolution_all.mp4"

# 첫 판과 마지막 판을 좌우로 (소리는 마지막 판)
$all = Get-ChildItem "$Work\mp4" -Filter '??_*.mp4' | Sort-Object Name
$first = $all[0].FullName
$last = $all[-1].FullName
& $ff -y -loglevel error -i $first -i $last -filter_complex "[0:v]scale=960:540[a];[1:v]scale=960:540[b];[a][b]hstack=inputs=2[v]" -map "[v]" -map 1:a -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart "$Work\ram_first_vs_now.mp4"

# 네 단계를 2×2 로 (1 · 6 · 9 · 마지막, 소리는 마지막 판)
$g = @('01', '06', '09') | ForEach-Object { (Get-ChildItem "$Work\mp4" -Filter "$($_)_*.mp4").FullName }
if ($g.Count -eq 3) {
    & $ff -y -loglevel error -i $g[0] -i $g[1] -i $g[2] -i $last -filter_complex "[0:v]scale=960:540[a];[1:v]scale=960:540[b];[2:v]scale=960:540[c];[3:v]scale=960:540[d];[a][b][c][d]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0[v]" -map "[v]" -map 3:a -c:v libx264 -crf 21 -preset medium -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart "$Work\ram_four_stages.mp4"
}
Get-ChildItem $Work -Filter 'ram_*.mp4' | ForEach-Object { Write-Output ("{0}  {1} MB" -f $_.Name, [math]::Round($_.Length / 1MB, 1)) }
