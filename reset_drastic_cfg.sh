#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)  # 脚本绝对路径
SDL_DB_FILE="/storage/.config/SDL-GameControllerDB/gamecontrollerdb.txt" # 目标DB文件
JOYGUID_BIN="${SCRIPT_DIR}/update_controller/joyguid"     # joyguid路径
DRASTIC_TEMPLATE="${SCRIPT_DIR}/update_controller/drastic.cfg"       # drastic.cfg模板
DRASTIC_CFG="/storage/.config/drastic/config/drastic.cfg"

# 定义配置文件路径
CONFIG_FILE="/storage/.config/joy_guid"

if [ -f /storage/.config/drastic/config/drastic.cf2 ]; then
    rm -rf /storage/.config/drastic/config/drastic.cf*
fi

if [ -f /storage/.config/drastic_chn/config/drastic.cf2 ]; then
    rm -rf /storage/.config/drastic_chn/config/drastic.cf*
fi

cp "${DRASTIC_TEMPLATE}" "${DRASTIC_CFG}"

guid=$("$JOYGUID_BIN" 2>/dev/null | tr -d '\n')  # 移除换行符

# 查找匹配的配置行
mapping_line=$(grep -m1 "^${guid}," "$SDL_DB_FILE")

if [ -z "$mapping_line" ]; then
    echo "错误：未找到GUID $guid 对应的控制器配置"
    exit 1
fi

# 生成临时文件
tmp_file=$(mktemp)

awk -v mapping_str="$mapping_line" '
BEGIN {
    # 初始化键值映射
    split(mapping_str, parts, /,/)
    delete key_map
    for (i in parts) {
        if (parts[i] ~ /:/) {
            split(parts[i], kv, /:/)
            key = kv[1]
            # 提取数字部分（去掉b前缀）
            if (kv[2] ~ /^b/) {
                value = substr(kv[2], 2)
                key_map[key] = value + 0  # 转换为数字
            }
        }
    }

    # 定义控件映射关系（保持不变）
    control_mapping["CONTROL_INDEX_UP"] = "dpup"
    control_mapping["CONTROL_INDEX_DOWN"] = "dpdown"
    control_mapping["CONTROL_INDEX_LEFT"] = "dpleft"
    control_mapping["CONTROL_INDEX_RIGHT"] = "dpright"
    control_mapping["CONTROL_INDEX_A"] = "a"
    control_mapping["CONTROL_INDEX_B"] = "b"
    control_mapping["CONTROL_INDEX_X"] = "x"
    control_mapping["CONTROL_INDEX_Y"] = "y"
    control_mapping["CONTROL_INDEX_L"] = "leftshoulder"
    control_mapping["CONTROL_INDEX_R"] = "rightshoulder"
    control_mapping["CONTROL_INDEX_START"] = "start"
    control_mapping["CONTROL_INDEX_SELECT"] = "back"
    control_mapping["CONTROL_INDEX_TOUCH_CURSOR_PRESS"] = "rightstick"
    control_mapping["CONTROL_INDEX_MENU"] = "leftstick"
    control_mapping["CONTROL_INDEX_SWAP_SCREENS"] = "guide"
    control_mapping["CONTROL_INDEX_SWAP_ORIENTATION_A"] = "lefttrigger"
    control_mapping["CONTROL_INDEX_SWAP_ORIENTATION_B"] = "righttrigger"
    control_mapping["CONTROL_INDEX_UI_UP"] = "dpup"
    control_mapping["CONTROL_INDEX_UI_DOWN"] = "dpdown"
    control_mapping["CONTROL_INDEX_UI_LEFT"] = "dpleft"
    control_mapping["CONTROL_INDEX_UI_RIGHT"] = "dpright"
    control_mapping["CONTROL_INDEX_UI_SELECT"] = "a"
    control_mapping["CONTROL_INDEX_UI_BACK"] = "x"
    control_mapping["CONTROL_INDEX_UI_EXIT"] = "b"
}

{
    current_line = $0
    if (index(current_line, "controls_b[") == 1) {
        split(current_line, arr1, "[")
        if (length(arr1) >= 2) {
            split(arr1[2], arr2, "]")
            control_index = arr2[1]
            
            if (control_index in control_mapping) {
                physical_key = control_mapping[control_index]
                
                if (physical_key in key_map) {
                    new_value = key_map[physical_key] + 1024
                    split(current_line, arr3, "=")
                    if (length(arr3) >= 2) {
                        current_line = arr3[1] "= " new_value
                    }
                }
            }
        }
    }
    print current_line
}
' "$DRASTIC_CFG" > "$tmp_file"

# 替换原文件
mv "$tmp_file" "$DRASTIC_CFG"

if [ -d /storage/.config/drastic_chn/config/ ]; then
    cp "$DRASTIC_CFG"  /storage/.config/drastic_chn/config/drastic.cfg
fi

echo "配置文件已更新：$config_file（使用GUID：$guid）"