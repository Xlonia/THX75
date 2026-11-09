func load_csv(path:String) -> Array:
    var result = []
    var file = FileAccess.open(path, FileAccess.READ)
    if not file:
        return []
    while not file.eof_reached():
        var row = file.get_csv_line()
        # 跳过 # 开头的注释行
        if row.size()>0 and row[0].begins_with("#"):
            continue
        result.append(row)
    file.close()
    return result

#Name是本地化键名去掉前缀“THX075.Character.”的名称
#ID是角色在游戏内该队伍的扁平化ID
#Team是角色所属队伍的扁平化ID
#Cruise是快机速度上限，单位像素每帧
#Normal是移动速度上限，单位像素每帧
##即：1秒距为这些像素的六十倍
##尽管显示时可能大部分玩家都是800像素网上，但别忘了逻辑画布为400*400，所以这些角色的渲染速度可能更快
#Determite是角色判定点规模半径，单位像素
#Defend是角色个人结界的额外半径，Defend+Determine为角色结界规模半径，单位像素
#Main_Cd是主要武器冷却时间
#Sub_Cd是僚机冷却时间
#Weapon_Muti是角色火力点乘数，给角色计算决斗火力通道个数用的
#Char是角色战术卡性格偏好
#NameZH/NameJP/NameEN是中日英三语言的本地化名称，后期版本将会将其放入本地化yaml中
#Mag和Phy分别代表魔法和物理，也就是法弹和物弹，代表这些角色是否有能力发射法弹或物弹，物弹是可以误伤友军的