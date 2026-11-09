extends Node
#o_是用来防止与其它变量混淆的前缀，它是仅在游戏中作为玩家数据出现的
# 剧情章节信息
var chapter_name: String = ""
var chapter_id: int = 0 #章节
var o_story_progress: int = 0 # 剧情进度编号，对话、NPC
var player_main: int #自机，魔理沙0，灵梦1，铃仙2
var o_bomb #灵击（
var o_music=0 #啥音乐，0即默认主题曲

# 几乎是rpg都有的经典的事件flag
var o_event_flags: Dictionary = {}

#角色id字典
var options_active_dict: Dictionary = {}
const player_main_in_dict: int= 0

#角色列表
var options_active_id: Array[int] = []
var options_active_name: Array[String] = []

#玩家位置
var current_scene: String = "" # 场景，存档乱改会有好事发生的
var current_scene_name: Dictionary
var player_spawn_pos: Vector2 = Vector2.ZERO
var player_spawn_dir: Vector2 = Vector2.RIGHT # 玩家朝向


#玩家资源数据
var o_player_yen: int #三自机开局故事不一样，选自机的时候赋值
var o_temp=0 #未来无欲拾食dlc的队伍体温，温度减去37.5，*即拾氏度*
var o_skip=false #能不能折跃
var o_level:Array[float] = []


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
