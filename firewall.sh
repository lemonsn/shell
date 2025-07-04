#!/bin/bash
# firewalld端口管理脚本
# 功能：同步管理SSH端口与防火墙规则，当前端口绿色高亮

# 定义颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# SSH配置文件路径
SSH_CONFIG="/etc/ssh/sshd_config"
BACKUP_DIR="/var/tmp/ssh_config_backups"
DATE_STAMP=$(date +"%Y%m%d%H%M")

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请用root权限运行！${NC}"
    exit 1
fi

# 检查并关闭SELinux（仅在未关闭时执行）
check_selinux() {
    local selinux_status=$(sestatus | grep "SELinux status" | awk '{print $3}')
    
    if [ "$selinux_status" = "disabled" ]; then
        echo -e "${GREEN}SELinux已处于关闭状态，跳过操作。${NC}"
    else
        echo -e "${YELLOW}检测到SELinux处于启用状态，先临时关闭...${NC}"
        setenforce 0  # 临时关闭SELinux
        echo -e "${GREEN}SELinux已临时关闭，正在修改配置文件永久关闭...${NC}"
        
        sed -i 's/^SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        sed -i 's/^SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}已修改SELinux配置为disabled，重启后永久生效！${NC}"
        else
            echo -e "${RED}修改SELinux配置失败，请手动编辑/etc/selinux/config！${NC}"
        fi
    fi
}

# 执行SELinux检查和关闭（脚本开始执行）
check_selinux

# 检查firewalld服务
service_status=$(systemctl status firewalld | grep "active" | awk '{print $2}')
if [ "$service_status" != "active" ]; then
    echo "提示：尝试启动firewalld服务..."
    systemctl start firewalld
    if [ $? -ne 0 ]; then
        echo -e "${RED}启动失败，请手动检查！${NC}"
        exit 1
    else
        echo -e "${GREEN}firewalld服务已启动！${NC}"
    fi
fi

# 检查SSH服务状态
sshd_status=$(systemctl status sshd | grep "active" | awk '{print $2}')
if [ -z "$sshd_status" ]; then
    echo -e "${YELLOW}提示：SSH服务未运行，修改端口后可能需要手动启动！${NC}"
fi

# 获取当前SSH端口函数
get_current_ssh_port() {
    local sshd_port=$(grep -E "^Port " $SSH_CONFIG | head -1 | awk '{print $2}')
    [ -z "$sshd_port" ] && sshd_port="22"  # 默认端口
    echo "$sshd_port"
}

# 定义SSH端口管理函数
manage_ssh_port() {
    local current_port=$(get_current_ssh_port)
    local current_ssh_firewall=""
    local firewall_ports=$(firewall-cmd --list-ports)
    
    # 确定当前防火墙中的SSH端口
    if [[ $firewall_ports =~ "22/tcp" ]]; then
        current_ssh_firewall="22/tcp"
    elif [[ $firewall_ports =~ "$current_port/tcp" ]]; then
        current_ssh_firewall="${current_port}/tcp"
    fi
    
    while true; do
        echo -e "\n===== SSH端口管理 ====="
        echo -e "当前SSH端口：${GREEN}$current_port${NC}"  # 绿色高亮当前端口
        echo "1. 查看当前SSH配置"
        echo "2. 设置自定义SSH端口"
        echo "3. 恢复默认SSH端口（22）"
        echo "4. 返回主菜单"
        read -p "选择操作（1-4）：" choice
        
        case $choice in
            1) 
                display_ssh_status $current_port $current_ssh_firewall
                ;;
            2) 
                set_custom_ssh_port $current_port
                ;;
            3) 
                restore_default_ssh $current_port
                ;;
            4) return 0 ;;
            *) 
                echo -e "${RED}无效选择！脚本退出。${NC}"
                exit 1
                ;;
        esac
    done
}

# 显示SSH状态
display_ssh_status() {
    local sshd_port=$1
    local firewall_port=$2
    
    echo "--- SSH服务配置 ---"
    if [ "$sshd_port" = "22" ]; then
        echo -e "${GREEN}SSH服务端口：$sshd_port（默认）${NC}"  # 绿色高亮端口
    else
        echo -e "${GREEN}SSH服务端口：$sshd_port（自定义）${NC}"  # 绿色高亮端口
    fi
    
    echo "--- 防火墙配置 ---"
    # 获取sshd端口对应的防火墙规则
    local ssh_firewall_port="${sshd_port}/tcp"
    if firewall-cmd --list-ports | grep "$ssh_firewall_port" >/dev/null; then
        echo -e "${GREEN}防火墙开放端口：$ssh_firewall_port（已同步sshd端口）${NC}"  # 高亮同步后的端口
    elif firewall-cmd --list-ports | grep "22/tcp" >/dev/null; then
        echo -e "${YELLOW}防火墙开放端口：22/tcp（与sshd端口${GREEN}$sshd_port${NC}不一致）${NC}"  # 提示不一致
    else
        echo -e "${RED}警告：防火墙未开放SSH端口！请确保端口${GREEN}$sshd_port${NC}已添加${NC}"  # 提示添加
    fi
}

# 设置自定义SSH端口（先查后改，同步防火墙）
set_custom_ssh_port() {
    local old_port=$1
    local old_firewall_port="${old_port}/tcp"
    echo -e "${YELLOW}注意：即将修改SSH端口（当前：${GREEN}$old_port${NC}），建议先通过其他方式保留远程连接！${NC}"  # 绿色高亮旧端口
    
    while true; do
        read -p "请输入新的SSH端口号（格式如8822/tcp，默认TCP，范围1-65535）：" port
        
        # 处理端口格式：默认补全TCP协议
        if [[ ! $port =~ /(tcp|udp)$ ]]; then
            port="${port}/tcp"
            echo -e "${GREEN}注意：已自动补全TCP协议，端口为：$port${NC}"
        fi
        
        # 验证端口格式
        if ! [[ $port =~ ^[0-9]+/(tcp|udp)$ ]]; then
            echo -e "${RED}错误：端口格式必须为'端口号/协议'（如8822/tcp）！${NC}"
            continue
        fi
        
        local new_port=$(echo $port | cut -d'/' -f1)
        local new_proto=$(echo $port | cut -d'/' -f2)
        
        # 验证端口范围
        if [ $new_port -lt 1 ] || [ $new_port -gt 65535 ]; then
            echo -e "${RED}错误：端口号必须为1-65535之间的数字！${NC}"
            continue
        fi
        
        # 避免新旧端口相同
        if [ "$new_port" = "$old_port" ]; then
            echo -e "${YELLOW}提示：新端口与当前端口（${GREEN}$old_port${NC}）相同，无需修改！${NC}"  # 绿色高亮当前端口
            return
        fi
        
        break  # 格式验证通过，退出循环
    done
    
    # 备份SSH配置文件
    mkdir -p $BACKUP_DIR
    cp $SSH_CONFIG $BACKUP_DIR/sshd_config_bak_$DATE_STAMP
    echo -e "${GREEN}已备份SSH配置文件至：$BACKUP_DIR/sshd_config_bak_$DATE_STAMP${NC}"
    
    # 修改SSH配置文件
    if [ "$old_port" = "22" ]; then
        sed -i "s/^Port 22/Port $new_port/g" $SSH_CONFIG
    else
        sed -i "s/^Port [0-9]*/Port $new_port/g" $SSH_CONFIG
    fi
    
    # 同步防火墙操作：先添加新端口，再删除旧端口
    firewall-cmd --permanent --add-port=$port
    if [ $? -ne 0 ]; then
        echo -e "${RED}防火墙新端口添加失败，已回滚SSH配置！${NC}"
        cp $BACKUP_DIR/sshd_config_bak_$DATE_STAMP $SSH_CONFIG
        return
    fi
    
    if firewall-cmd --list-ports | grep "$old_firewall_port" >/dev/null; then
        firewall-cmd --permanent --remove-port=$old_firewall_port
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}警告：旧防火墙端口关闭失败，但新端口已开放！${NC}"
        fi
    fi
    
    firewall-cmd --reload
    
    # 询问是否重启SSH服务
    read -p "是否重启SSH服务使新端口（${GREEN}$new_port${NC}）生效？(y/n)：" confirm  # 绿色高亮新端口
    if [[ $confirm =~ ^[Yy]$ ]]; then
        systemctl restart sshd
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}SSH服务已重启，新端口（$new_port）生效！${NC}"
        else
            echo -e "${YELLOW}警告：SSH服务重启失败，请手动执行 'systemctl restart sshd'！${NC}"
        fi
    else
        echo -e "${YELLOW}提示：未重启SSH服务，需手动执行 'systemctl restart sshd' 使新端口生效！${NC}"
    fi
    
    echo -e "${GREEN}SSH端口已成功从 $old_port 修改为 $new_port（防火墙协议：$new_proto）${NC}"
}

# 恢复默认SSH端口（同步防火墙）
restore_default_ssh() {
    local old_port=$1
    local old_firewall_port="${old_port}/tcp"
    
    if [ "$old_port" = "22" ]; then
        echo -e "${YELLOW}提示：当前已使用默认SSH端口（${GREEN}22${NC}）！${NC}"  # 绿色高亮默认端口
        return
    fi
    
    # 备份SSH配置文件
    mkdir -p $BACKUP_DIR
    cp $SSH_CONFIG $BACKUP_DIR/sshd_config_bak_$DATE_STAMP
    echo -e "${GREEN}已备份SSH配置文件至：$BACKUP_DIR/sshd_config_bak_$DATE_STAMP${NC}"
    
    # 修改SSH配置文件为默认端口
    sed -i "s/^Port [0-9]*/Port 22/g" $SSH_CONFIG
    
    # 同步防火墙操作：先添加默认端口，再删除旧端口
    firewall-cmd --permanent --add-port=22/tcp
    if [ $? -ne 0 ]; then
        echo -e "${RED}防火墙默认端口添加失败，已回滚SSH配置！${NC}"
        cp $BACKUP_DIR/sshd_config_bak_$DATE_STAMP $SSH_CONFIG
        return
    fi
    
    if firewall-cmd --list-ports | grep "$old_firewall_port" >/dev/null; then
        firewall-cmd --permanent --remove-port=$old_firewall_port
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}警告：旧防火墙端口关闭失败，但默认端口已开放！${NC}"
        fi
    fi
    
    firewall-cmd --reload
    
    # 询问是否重启SSH服务
    read -p "是否重启SSH服务恢复默认端口（${GREEN}22${NC}）？(y/n)：" confirm  # 绿色高亮默认端口
    if [[ $confirm =~ ^[Yy]$ ]]; then
        systemctl restart sshd
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}SSH服务已重启，恢复默认端口（22）！${NC}"
        else
            echo -e "${YELLOW}警告：SSH服务重启失败，请手动执行 'systemctl restart sshd'！${NC}"
        fi
    else
        echo -e "${YELLOW}提示：未重启SSH服务，需手动执行 'systemctl restart sshd' 恢复默认端口！${NC}"
    fi
    
    echo -e "${GREEN}已恢复默认SSH端口（22），旧端口 $old_port 已从防火墙移除！${NC}"
}

# 常规端口操作函数（添加默认TCP，删除兼容格式）
add_port() {
    while true; do
        read -p "请输入要添加的端口号（如80，默认TCP；或80/udp）：" port
        
        # 处理端口格式：默认补全TCP协议
        if [[ ! $port =~ /(tcp|udp)$ ]]; then
            port="${port}/tcp"
            echo -e "${GREEN}注意：已自动补全TCP协议，端口为：$port${NC}"
        fi
        
        # 验证端口格式
        if ! [[ $port =~ ^[0-9]+/(tcp|udp)$ ]]; then
            echo -e "${RED}错误：端口格式必须为'端口号/协议'（如80/tcp）！${NC}"
            continue
        fi
        
        # 验证端口范围
        local port_num=$(echo $port | cut -d'/' -f1)
        if [ $port_num -lt 1 ] || [ $port_num -gt 65535 ]; then
            echo -e "${RED}错误：端口号必须为1-65535之间的数字！${NC}"
            continue
        fi
        
        break  # 格式验证通过，退出循环
    done
    
    firewall-cmd --permanent --add-port=$port
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}端口 $port 添加成功！${NC}"
        firewall-cmd --reload
    else
        echo -e "${RED}添加失败，请检查格式或端口是否已存在！${NC}"
    fi
}

remove_port() {
    while true; do
        read -p "请输入要删除的端口号（如80/tcp，支持协议标识）：" port
        
        # 处理端口格式：若未指定协议，尝试匹配TCP和UDP
        if [[ ! $port =~ /(tcp|udp)$ ]]; then
            port_tcp="${port}/tcp"
            port_udp="${port}/udp"
            
            # 先尝试删除TCP端口
            firewall-cmd --permanent --remove-port=$port_tcp
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}端口 $port_tcp 删除成功！${NC}"
                firewall-cmd --reload
                return
            fi
            
            # 再尝试删除UDP端口
            firewall-cmd --permanent --remove-port=$port_udp
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}端口 $port_udp 删除成功！${NC}"
                firewall-cmd --reload
                return
            fi
            
            # 两者都不存在时提示错误
            echo -e "${RED}删除失败：未找到端口 $port/tcp 或 $port/udp！${NC}"
            continue
        fi
        
        # 验证端口格式
        if ! [[ $port =~ ^[0-9]+/(tcp|udp)$ ]]; then
            echo -e "${RED}错误：端口格式必须为'端口号/协议'（如80/tcp）！${NC}"
            continue
        fi
        
        break  # 格式验证通过，退出循环
    done
    
    firewall-cmd --permanent --remove-port=$port
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}端口 $port 删除成功！${NC}"
        firewall-cmd --reload
    else
        echo -e "${RED}删除失败，端口可能不存在！${NC}"
    fi
}

check_ports() {
    echo "当前开放端口："
    firewall-cmd --list-ports
    if [ $? -ne 0 ]; then
        echo -e "${RED}查询失败，请检查配置！${NC}"
    fi
}

# 主菜单
while true; do
    echo -e "\n===== firewalld端口管理工具 ====="
    echo "1. 管理SSH端口（含服务配置）"
    echo "2. 添加常规端口"
    echo "3. 删除常规端口"
    echo "4. 查询所有开放端口"
    echo "5. 退出"
    read -p "选择操作（1-5）：" choice
    
    case $choice in
        1) manage_ssh_port ;;
        2) add_port ;;
        3) remove_port ;;
        4) check_ports ;;
        5) 
            echo "已退出。"
            exit 0
            ;;
        *) 
            echo -e "${RED}无效选择！脚本退出。${NC}"
            exit 1
            ;;
    esac
done