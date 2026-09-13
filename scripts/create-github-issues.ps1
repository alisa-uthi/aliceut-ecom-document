<#
.SYNOPSIS
    Creates GitHub Issues from phase-1 backlog epic-breakdown files.

.DESCRIPTION
    Parses every *.md file in phase-1/backlog/epic-breakdown/, creates one
    GitHub Issue per task, assigns the correct milestone (Sprint N), labels
    it with the epic name, and optionally links it to a GitHub Project board.

.PARAMETER Repo
    GitHub repository in owner/repo format.
    Default: alisa-uthi/aliceut-ecom-document

.PARAMETER ProjectNumber
    GitHub Projects (v2) number to add issues to.
    Find it in the URL: github.com/users/<owner>/projects/<number>
    Omit (or pass 0) to skip project linking.

.PARAMETER Owner
    GitHub owner for project commands. Default: alisa-uthi

.PARAMETER DryRun
    Print what would be created without calling GitHub.

.EXAMPLE
    .\create-github-issues.ps1 -DryRun

.EXAMPLE
    .\create-github-issues.ps1

.EXAMPLE
    .\create-github-issues.ps1 -ProjectNumber 1
#>

param(
    [string]$Repo          = "alisa-uthi/aliceut-ecom-document",
    [string]$Owner         = "alisa-uthi",
    [int]   $ProjectNumber = 0,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$isDryRun  = $DryRun.IsPresent
$epicDir   = Join-Path $PSScriptRoot "..\phase-1\backlog\epic-breakdown"

$milestoneCache = @{}
$labelCache     = @{}
$palette        = @("0075ca","e4e669","d93f0b","0e8a16","b60205","5319e7","1d76db","f9d0c4")
$paletteIdx     = 0

function Ensure-Milestone([string]$sprintNum) {
    $title = "Sprint $sprintNum"
    if ($milestoneCache.ContainsKey($title)) { return }
    $milestoneCache[$title] = $true
    if ($isDryRun) { return }
    $existing = gh api "repos/$Repo/milestones" --jq ".[] | select(.title == `"$title`") | .number" 2>$null
    if (-not $existing) {
        gh api "repos/$Repo/milestones" -X POST -f title="$title" | Out-Null
        Write-Host "  + Milestone: $title"
    }
}

function Ensure-Label([string]$epicName) {
    $label = "epic:$($epicName.ToLower())"
    if ($labelCache.ContainsKey($label)) { return }
    $labelCache[$label] = $true
    if ($isDryRun) { return }
    $color = $palette[$script:paletteIdx % $palette.Length]
    $script:paletteIdx++
    gh label create $label --repo $Repo --color $color 2>$null
}

$epicFiles    = Get-ChildItem $epicDir -Filter "*.md" | Sort-Object Name
$totalCreated = 0

foreach ($file in $epicFiles) {
    $raw      = [System.IO.File]::ReadAllText($file.FullName)
    $epicName = $file.BaseName

    $sprint = "1"
    if ($raw -match '(?m)^\*\*Sprint:\*\*\s*(\d+)') { $sprint = $Matches[1] }

    Write-Host "`n[$epicName]  Sprint $sprint"

    Ensure-Milestone $sprint
    Ensure-Label $epicName

    $blocks = [array]($raw -split '(?m)^\s*---\s*$' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })

    for ($i = 1; $i -lt $blocks.Count; $i++) {
        $block = [string]$blocks[$i]
        if ($block -notmatch '(?m)^#{2,3}\s+([A-Z][A-Z0-9-]+-\d+)\s+[^\w\s]+\s+(.+)') { continue }
        $taskId    = $Matches[1].Trim()
        $taskTitle = $Matches[2].Trim()

        $bodyLines   = $block -split "`n"
        $bodyContent = ($bodyLines[1..($bodyLines.Length - 1)] -join "`n").Trim()
        $issueBody   = "**Epic:** ``$epicName`` | **Sprint:** $sprint`n`n$bodyContent"
        $issueTitle  = "[$taskId] $taskTitle"

        if ($isDryRun) {
            Write-Host "  [DRY] $issueTitle"
            $totalCreated++
            continue
        }

        $issueUrl = gh issue create `
            --repo $Repo `
            --title $issueTitle `
            --body $issueBody `
            --label "epic:$($epicName.ToLower())" `
            --milestone "Sprint $sprint"

        if ($LASTEXITCODE -ne 0) {
            Write-Warning "  FAILED: $issueTitle"
            continue
        }

        Write-Host "  $issueUrl"
        $totalCreated++

        if ($ProjectNumber -gt 0 -and $issueUrl) {
            gh project item-add $ProjectNumber --owner $Owner --url $issueUrl | Out-Null
        }
    }
}

Write-Host "`n$totalCreated issue$(if ($totalCreated -ne 1) { 's' }) $(if ($isDryRun) { '(dry run)' } else { 'created' })."
