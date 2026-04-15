#!/bin/bash

# ============================================
# 工业生产链模拟器 - 开发环境一键启动脚本
# ============================================
# 功能：并行启动 Rust 后端和 Flutter 前端
# 使用方法：./run_dev.sh [选项]
# 选项：
#   -c, --clean    清理构建文件后启动
#   -t, --test     运行测试后启动
#   -h, --help     显示帮助信息
# ============================================

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目根目录
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$PROJECT_ROOT/backend"
FLUTTER_DIR="$PROJECT_ROOT"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
工业生产链模拟器 - 开发环境一键启动脚本

使用方法: $0 [选项]

选项:
  -c, --clean     清理构建文件后启动
  -t, --test      运行测试后启动
  -h, --help      显示此帮助信息

示例:
  $0              正常启动前后端
  $0 --clean      清理后启动
  $0 --test       运行测试后启动
EOF
}

# 检查依赖
check_dependencies() {
    log_info "检查系统依赖..."
    
    # 检查 cargo
    if ! command -v cargo &> /dev/null; then
        log_error "未找到 cargo，请安装 Rust"
        exit 1
    fi
    
    # 检查 flutter
    if ! command -v flutter &> /dev/null; then
        log_error "未找到 flutter，请安装 Flutter SDK"
        exit 1
    fi
    
    # 检查 sqlite3 (可选)
    if ! command -v sqlite3 &> /dev/null; then
        log_warning "未找到 sqlite3，数据库功能可能受限"
    fi
    
    log_success "依赖检查完成"
}

# 清理构建文件
clean_build() {
    log_info "清理构建文件..."
    
    # 清理 Rust 构建
    if [ -d "$BACKEND_DIR/target" ]; then
        cd "$BACKEND_DIR"
        cargo clean
        log_success "Rust 构建文件已清理"
    fi
    
    # 清理 Flutter 构建
    cd "$FLUTTER_DIR"
    flutter clean
    log_success "Flutter 构建文件已清理"
    
    # 清理数据库文件
    if [ -f "$BACKEND_DIR/backend.db" ]; then
        rm "$BACKEND_DIR/backend.db"
        log_success "数据库文件已清理"
    fi
}

# 运行测试
run_tests() {
    log_info "运行测试..."
    
    # Rust 测试
    log_info "运行 Rust 测试..."
    cd "$BACKEND_DIR"
    if cargo test -- --nocapture; then
        log_success "Rust 测试通过"
    else
        log_error "Rust 测试失败"
        exit 1
    fi
    
    # Flutter 测试
    log_info "运行 Flutter 测试..."
    cd "$FLUTTER_DIR"
    if flutter test; then
        log_success "Flutter 测试通过"
    else
        log_error "Flutter 测试失败"
        exit 1
    fi
}

# 编译 Rust 后端
build_backend() {
    log_info "编译 Rust 后端..."
    cd "$BACKEND_DIR"
    
    if cargo build --release; then
        log_success "Rust 后端编译成功"
    else
        log_error "Rust 后端编译失败"
        exit 1
    fi
}

# 编译 Flutter 前端
build_frontend() {
    log_info "编译 Flutter 前端..."
    cd "$FLUTTER_DIR"
    
    # 获取依赖
    flutter pub get
    
    # 分析代码
    if ! flutter analyze; then
        log_warning "代码分析发现问题，但继续构建..."
    fi
    
    # 构建 Linux 版本
    if flutter build linux --release; then
        log_success "Flutter 前端编译成功"
    else
        log_error "Flutter 前端编译失败"
        exit 1
    fi
}

# 启动 Rust 后端服务器
start_backend() {
    log_info "启动 Rust 后端服务器 (端口 8080)..."
    cd "$BACKEND_DIR"
    
    # 检查端口是否被占用
    if lsof -ti:8080 > /dev/null; then
        log_warning "端口 8080 已被占用，尝试停止现有进程..."
        lsof -ti:8080 | xargs kill -9 2>/dev/null || true
        sleep 1
    fi
    
    # 在后台启动服务器
    cargo run --release &
    BACKEND_PID=$!
    
    # 等待服务器启动
    local max_attempts=30
    local attempt=1
    
    log_info "等待后端服务器启动..."
    while [ $attempt -le $max_attempts ]; do
        if curl -s http://localhost:8080/api/simulation/state > /dev/null 2>&1; then
            log_success "Rust 后端服务器已启动 (PID: $BACKEND_PID)"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    
    log_error "后端服务器启动超时"
    kill $BACKEND_PID 2>/dev/null || true
    exit 1
}

# 启动 Flutter 前端
start_frontend() {
    log_info "启动 Flutter 前端..."
    cd "$FLUTTER_DIR"
    
    # 在后台启动 Flutter 应用
    flutter run -d linux --debug &
    FLUTTER_PID=$!
    
    sleep 3
    if ps -p $FLUTTER_PID > /dev/null; then
        log_success "Flutter 前端已启动 (PID: $FLUTTER_PID)"
    else
        log_error "Flutter 前端启动失败"
        exit 1
    fi
}

# 清理函数，在脚本退出时调用
cleanup() {
    log_info "正在停止所有进程..."
    
    # 停止后端
    if [ -n "$BACKEND_PID" ] && ps -p $BACKEND_PID > /dev/null; then
        log_info "停止 Rust 后端 (PID: $BACKEND_PID)"
        kill $BACKEND_PID 2>/dev/null || true
    fi
    
    # 停止前端
    if [ -n "$FLUTTER_PID" ] && ps -p $FLUTTER_PID > /dev/null; then
        log_info "停止 Flutter 前端 (PID: $FLUTTER_PID)"
        kill $FLUTTER_PID 2>/dev/null || true
    fi
    
    log_success "清理完成"
}

# 主函数
main() {
    # 解析命令行参数
    local clean_build_flag=false
    local run_tests_flag=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--clean)
                clean_build_flag=true
                shift
                ;;
            -t|--test)
                run_tests_flag=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 显示欢迎信息
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  工业生产链模拟器 - 开发环境启动脚本${NC}"
    echo -e "${GREEN}============================================${NC}"
    
    # 检查依赖
    check_dependencies
    
    # 清理构建文件
    if [ "$clean_build_flag" = true ]; then
        clean_build
    fi
    
    # 运行测试
    if [ "$run_tests_flag" = true ]; then
        run_tests
    fi
    
    # 编译
    build_backend
    build_frontend
    
    # 设置退出时清理
    trap cleanup EXIT INT TERM
    
    # 启动服务
    start_backend
    start_frontend
    
    # 显示运行信息
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  服务已启动！${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo -e "Rust 后端: ${BLUE}http://localhost:8080${NC}"
    echo -e "Flutter 前端: ${BLUE}正在运行${NC}"
    echo -e ""
    echo -e "可用 API 端点:"
    echo -e "  ${YELLOW}GET${NC}  /api/simulation/state      # 获取模拟状态"
    echo -e "  ${YELLOW}POST${NC} /api/atoms                # 创建 Atom"
    echo -e "  ${YELLOW}POST${NC} /api/structs/manual      # 验证手动结构"
    echo -e "  ${YELLOW}POST${NC} /api/structs/auto        # 自动生成结构"
    echo -e "  ${YELLOW}POST${NC} /api/simulation/start    # 启动模拟"
    echo -e "  ${YELLOW}GET${NC}  /api/analysis/metrics    # 获取分析指标"
    echo -e ""
    echo -e "按 ${RED}Ctrl+C${NC} 停止所有服务"
    echo -e "${GREEN}============================================${NC}"
    
    # 等待用户中断
    wait
}

# 运行主函数
main "$@"