extends Node
## ct_bullet_stub —— dmapproach 探针的弹幕替身（鸭子类型：arena 只访问
## alive/hidden_now/pos/cur_dir()/cur_speed()——G 节池外无副作用）
var alive := true
var hidden_now := false
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var _dir := Vector2(1, 0) ## 朝 +x 飞（角色在右——上一拍在左侧圈外）


func cur_dir() -> Vector2:
	return _dir


func cur_speed() -> float:
	return 6000.0 ## 回推=pos-dir/60=1s 位移——100px 上一拍差（圈外→圈内上升沿）
