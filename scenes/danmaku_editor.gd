extends Control
## 【th75 编辑器独立进程包装 20261114（作者批准：THXGameKit 同款模式）】
## 为什么要有本包装：submodule 内 kit 的 danmaku_editor.tscn 引用内核逻辑
## 脚本路径（res://addons/thx_gamekit/...）——th75 挂载点不存在该路径
## （实际=res://addons/thxgamekit/kit/addons/...）→ 直接跑 kit tscn=空白窗。
## 本包装=th75 挂载点专属入口：按挂载点路径实例化编辑器脚本，
## 并把它挂到根 Window 下（=独立进程主场景位，编辑器退出链 get_tree().quit
## 判定成立）。启动弹幕编辑器.bat / 标题"弹幕编辑器"按钮都走本场景。

func _ready() -> void:
	var ed: Control = (load("res://addons/thxgamekit/kit/addons/thx_gamekit/editor/danmaku_editor.gd") as GDScript).new()
	ed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child.call_deferred(ed) ## 挂根 Window 下（非本节点子级）=窗口模式判定成立
