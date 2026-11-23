param([string]$Godot = "godot")
$ErrorActionPreference = "Stop"
$projectPath = Split-Path -Parent $PSScriptRoot
$testNames = @("first_shift_test", "fishing_test", "provisions_test", "spawn_safety_test", "dock_access_test", "expedition_test", "northern_access_test", "ship_asset_test", "cabin_asset_test", "radio_asset_test", "lighthouse_asset_test", "lighthouse_interior_test", "building_interiors_test", "characters_test", "first_watch_test", "first_shift_demo_test", "game_polish_test", "backpack_salvage_test", "fieldwork_test", "dynamics_test", "gameplay_test", "campaign_test", "lumi_test", "minigames_test", "atmosphere_test", "hunter_test", "lore_test", "save_points_test", "supplies_test", "escalation_test", "small_scares_test", "tutorial_test", "settings_test", "hunter_visual_test", "hunter_presence_test", "hiding_spots_test", "hunter_night_test", "achievements_test", "difficulty_test", "time_flow_test")
foreach ($testName in $testNames) {
    Write-Output ("TEST: " + $testName)
    & $Godot --headless --path $projectPath --script ("res://tests/" + $testName + ".gd")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
Write-Output "All Godot integration checks passed."
