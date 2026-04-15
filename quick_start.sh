#!/bin/bash

# ============================================
# 快速启动脚本 - 仅启动服务，不重新编译
# ============================================
# 用于日常开发快速启动
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 项目目录
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$PROJECT_ROOT/backend"

# 日志函数
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 清理函数
cleanup() {
    log "正在停止所有进程..."
    
    # 停止后端
    if [ -n "$BACKEND_PID" ] && ps -p $BACKEND_PID > /dev/null; then
        log "停止 Rust 后端 (PID: $BACKEND_PID)"
        kill $BACKEND_PID 2>/dev/null || true
    fi
    
    # 停止前端
    if [ -n "$FLUTTER_PID" ] && ps -p $FLUTTER_PID > /dev/null; then
        log "停止 Flutter 前端 (PID: $FLUTTER_PID)"
        kill $FLUTTER_PID 2>/dev/null || true
    fi
    
    success "清理完成"
}

# 检查端口是否被占用
check_port() {
    local port=$1
    if lsof -ti:$port > /dev/null; then
        log "端口 $port 已被占用，尝试停止现有进程..."
        lsof -ti:$port | xargs kill -9 2>/dev/null || true
        sleep 1
    fi
}

# 启动 Rust 后端
start_backend() {
    log "启动 Rust 后端服务器..."
    cd "$BACKEND_DIR"
    
    check_port 8080
    
    # 检查是否已编译
    if [ ! -f "target/release/backend" ]; then
        error "未找到编译后的后端程序，请先运行 ./run_dev.sh 或手动编译"
        exit 1
    fi
    
    # 启动后端
    ./target/release/backend &
    BACKEND_PID=$!
    
    # 等待启动
    local attempts=0
    local max_attempts=20
    
    while [ $attempts -lt $max_attempts ]; do
        if curl -s http://localhost:8080/api/simulation/state > /dev/null 2>&1; then
            success "Rust 后端已启动 (PID: $BACKEND_PID)"
            return 0
        fi
        sleep 1
        attempts=$((attempts + 1))
    done
    
    error "后端启动超时"
    return 1
}

# 启动 Flutter 前端
start_frontend() {
    log "启动 Flutter 前端..."
    cd "$PROJECT_ROOT"
    
    # 检查 Flutter 依赖
    if [ ! -d "build" ]; then
        log "未找到构建文件，尝试获取依赖..."
        flutter pub get
    fi
    
    # 启动 Flutter
    flutter run -d linux --debug &
    FLUTTER_PID=$!
    
    sleep 3
    if ps -p $FLUTTER_PID > /dev/null; then
        success "Flutter 前端已启动 (PID: $FLUTTER_PID)"
    else
        error "Flutter 前端启动失败"
        return 1
    fi
}

# 主函数
main() {
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  工业生产链模拟器 - 快速启动${NC}"
    echo -e "${GREEN}============================================${NC}"
    
    # 设置退出时清理
    trap cleanup EXIT INT TERM
    
    # 启动服务
    if start_backend; then
        if start_frontend; then
            echo -e "${GREEN}============================================${NC}"
            echo -e "${GREEN}  服务启动成功！${NC}"
            echo -e "${GREEN}============================================${NC}"
            echo -e "后端: ${BLUE}http://localhost:8080${NC}"
            echo -e "前端: ${BLUE}正在运行${NC}"
            echo -e ""
            echo -e "按 ${RED}Ctrl+C${NC} 停止所有服务"
            echo -e "${GREEN}============================================${NC}"
            
            # 等待用户中断
            wait
        else
            cleanup
            exit 1
        fi
    else
        exit 1
    fi
}

# 运行主函数
main "$@"