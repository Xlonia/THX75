@echo off
rem THXGameKit 内核同步（th75 宿主侧）——submodule 拉取+project.godot 边界改名
rem 【背景】内核仓需要 project.godot（GameKit 独立工程主场景）；th75 宿主需要
rem 它改名为 .standalone（防 Godot 把 submodule 当独立工程边界→全局类不注册）
rem 【用法】内核 push 后双击本脚本；出现"完成"即可打开 th75
cd /d "%~dp0"
git submodule update --remote addons/thxgamekit/kit
if exist "addons\thxgamekit\kit\project.godot" (
  ren "addons\thxgamekit\kit\project.godot" project.godot.standalone
  echo [OK] project.godot 已改名为 .standalone（宿主边界）
) else (
  if exist "addons\thxgamekit\kit\project.godot.standalone" (
    echo [OK] .standalone 已在位
  ) else (
    echo [错误] 内核目录异常——请检查 submodule
  )
)
echo 完成。
pause
