#!/bin/bash
set -euo pipefail

# ======================== 配置区 ========================
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)  # 脚本绝对路径
XML_FILE="/storage/.config/emulationstation/es_input.cfg" # 固定XML路径
SDL_DB_FILE="/storage/.config/SDL-GameControllerDB/gamecontrollerdb.txt" # 目标DB文件
JOYGUID_BIN="${SCRIPT_DIR}/update_controller/joyguid"     # joyguid路径
PYTHON_SCRIPT="${SCRIPT_DIR}/update_controller/convert_xml_to_sdl.py"       # Python转换脚本

# ===================== 全局变量声明 =====================
WORK_DIR=""  # 显式声明为全局变量

# ===================== 功能函数实现 =====================
# 带颜色输出的日志函数
log() {
    local level=$1
    local message=$2
    local color_code=""
    case $level in
        "SUCCESS") color_code="\033[32m" ;;
        "ERROR") color_code="\033[31m" ;;
        "WARNING") color_code="\033[33m" ;;
        "INFO") color_code="\033[34m" ;;
        *) color_code="\033[0m" ;;
    esac
    echo -e "${color_code}[$(date '+%Y-%m-%d %H:%M:%S')] $level: $message\033[0m"
}

# 符号链接处理函数
handle_symlink() {
    local sdl_file=$1
    log "INFO" "开始检查文件链接状态: $sdl_file"

    if [[ -L "$sdl_file" ]]; then
        log "WARNING" "检测到符号链接: $sdl_file"
        local target_file=$(readlink -f "$sdl_file")
        local bak_file="${sdl_file}_bak_$(date +%Y%m%d%H%M%S)"

        # 检查目标文件是否只读
        if [ ! -w "$target_file" ] || [[ "$(stat -c %a "$target_file")" =~ ^[0-7][0-7][0-7]4 ]]; then
            log "WARNING" "检测到只读文件: $target_file"

            # 备份原始链接
            log "INFO" "创建备份: $bak_file"
            cp -P "$sdl_file" "$bak_file" || {
                log "ERROR" "备份文件失败"
                return 1
            }

            # 替换为可写副本
            log "INFO" "创建可写副本..."
            local tmp_file="${sdl_file}.tmp"
            cp -f "$target_file" "$tmp_file" && 
            chmod u+w "$tmp_file" &&
            mv -f "$tmp_file" "$sdl_file" || {
                log "ERROR" "文件替换操作失败"
                return 1
            }

            # 验证结果
            if [ -L "$sdl_file" ]; then
                log "ERROR" "符号链接未成功替换"
                return 1
            fi
            log "SUCCESS" "已转换为可写普通文件"
        else
            log "INFO" "目标文件可写，保持链接状态"
        fi
    elif [ ! -f "$sdl_file" ]; then
        log "WARNING" "文件不存在，创建初始配置"
        mkdir -p "$(dirname "$sdl_file")"
        touch "$sdl_file"
    fi
}

# 检查joyguid可执行文件
check_joyguid() {
    log "INFO" "检查joyguid可执行文件"

    # 存在性检查
    if [ ! -f "$JOYGUID_BIN" ]; then
        log "ERROR" "找不到joyguid可执行文件"
        log "ERROR" "预期路径: $JOYGUID_BIN"
        log "ERROR" "请确认："
        log "ERROR" "1. update_controller目录是否与脚本同级"
        log "ERROR" "2. joyguid文件是否存在于目录中"
        exit 1
    fi

    # 权限检查
    if [ ! -x "$JOYGUID_BIN" ]; then
        log "WARNING" "缺少执行权限，尝试修复..."
        if chmod +x "$JOYGUID_BIN"; then
            log "SUCCESS" "权限修复成功"
        else
            log "ERROR" "权限修复失败，请手动执行："
            log "ERROR" "sudo chmod +x '$JOYGUID_BIN'"
            exit 1
        fi
    fi

    # 功能测试
    log "INFO" "运行joyguid自检..."
    if ! "$JOYGUID_BIN" --test >/dev/null 2>&1; then
        log "ERROR" "joyguid自检失败"
        log "ERROR" "可能原因："
        log "ERROR" "1. 控制器未连接"
        log "ERROR" "2. 缺少依赖库"
        log "ERROR" "3. 权限不足（尝试使用sudo）"
        exit 1
    fi
}

# ===================== 清理函数 =====================
cleanup() {
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        echo "清理临时目录: $WORK_DIR"
        rm -rf "$WORK_DIR"
    fi
}

# ===================== 主流程函数 =====================
main() {
    log "INFO" "====== 开始控制器配置更新流程 ======"

    # 初始化检查
    check_joyguid
    handle_symlink "$SDL_DB_FILE"

    # 获取GUID（带重试机制）
    local GUID
    local max_retries=3
    for ((retry=1; retry<=max_retries; retry++)); do
        log "INFO" "尝试获取GUID (第${retry}次)"
		GUID=$("$JOYGUID_BIN" 2>/dev/null | tr -d '\n')  # 移除换行符
        
        if [[ "${#GUID}" -eq 32 ]]; then
            log "SUCCESS" "GUID获取成功: ${GUID:0:8}****"
            break
        fi
        
        if [[ $retry -eq max_retries ]]; then
            log "ERROR" "GUID获取失败，请检查控制器连接"
            exit 1
        fi
        sleep 1
    done

    # 生成SDL条目
    log "INFO" "生成SDL配置条目..."
    if [ ! -f "$PYTHON_SCRIPT" ]; then
        log "ERROR" "找不到Python脚本: $PYTHON_SCRIPT"
        exit 1
    fi
    
    local NEW_ENTRY
    NEW_ENTRY=$(python3 "$PYTHON_SCRIPT" "$XML_FILE" "$GUID") || {
        log "ERROR" "SDL条目生成失败"
        exit 1
    }
    log "DEBUG" "生成条目内容: $NEW_ENTRY"

    # 创建临时工作区
    WORK_DIR=$(mktemp -d)
    trap cleanup EXIT INT TERM  # 注册清理函数
    log "INFO" "创建临时工作目录: $WORK_DIR"

    # 处理数据库文件
    local CURRENT_DB="${WORK_DIR}/current"
    local NEW_DB="${WORK_DIR}/new"
    
    cp "$SDL_DB_FILE" "$CURRENT_DB" || {
        log "ERROR" "数据库文件拷贝失败"
        exit 1
    }

    # 使用改进的awk处理逻辑
    log "INFO" "更新数据库条目（GUID不存在时添加到文件头）..."
    awk -v guid="$GUID" -v new_entry="$NEW_ENTRY" '
    BEGIN { found = 0; idx = 0 }
    {
        # 匹配当前GUID的行
        if ($0 ~ "^" guid ",") {
            print new_entry
            found = 1
        }
        # 非匹配行存入数组
        else {
            lines[idx++] = $0
        }
    }
    END {
        # 未找到时先输出新条目
        if (!found) {
            print new_entry
        }
        # 输出所有其他行
        for (i = 0; i < idx; i++) {
            print lines[i]
        }
    }
    ' "$CURRENT_DB" > "$NEW_DB"

    # 原子替换操作
    log "INFO" "执行原子替换..."
    mv -f "$NEW_DB" "$SDL_DB_FILE" || {
        log "ERROR" "文件替换失败"
        exit 1
    }
	chmod 777 "$SDL_DB_FILE"

    log "SUCCESS" "====== 更新成功完成 ======"
    log "INFO" "修改后条目预览:"
	grep -m1 "^${GUID}," "$SDL_DB_FILE"
}

# ===================== 执行入口 =====================
main "$@"