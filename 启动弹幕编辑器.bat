@echo off
rem THX075 弹幕编辑器独立启动（与游戏主程序互不影响）
cd /d "%~dp0"
start "" "Godot_v4.7.2-stable_win64.exe" --path . "res://scenes/danmaku_editor.tscn"
