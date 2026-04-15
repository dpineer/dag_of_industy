# ============================================
# 工业生产链模拟器 - Makefile
# ============================================
# 提供传统的构建和测试命令
# ============================================

.PHONY: all build test clean run backend frontend help

# 项目目录
PROJECT_ROOT := $(shell pwd)
BACKEND_DIR := $(PROJECT_ROOT)/backend

# 默认目标
all: build

# 显示帮助信息
help:
	@echo "工业生产链模拟器 - Makefile 命令"
	@echo ""
	@echo "可用命令:"
	@echo "  make build       编译前后端"
	@echo "  make test        运行所有测试"
	@echo "  make run         启动开发环境"
	@echo "  make backend     仅编译和运行后端"
	@echo "  make frontend    仅编译和运行前端"
	@echo "  make clean       清理构建文件"
	@echo "  make help        显示此帮助信息"
	@echo ""
	@echo "快速命令:"
	@echo "  make dev         快速开发启动（不重新编译）"
	@echo "  make lint        运行代码检查"

# 编译前后端
build: build-backend build-frontend

# 编译 Rust 后端
build-backend:
	@echo "编译 Rust 后端..."
	cd $(BACKEND_DIR) && cargo build --release
	@echo "Rust 后端编译完成"

# 编译 Flutter 前端
build-frontend:
	@echo "编译 Flutter 前端..."
	flutter pub get
	flutter analyze
	flutter build linux --release
	@echo "Flutter 前端编译完成"

# 运行所有测试
test: test-backend test-frontend

# 运行 Rust 测试
test-backend:
	@echo "运行 Rust 测试..."
	cd $(BACKEND_DIR) && cargo test -- --nocapture
	@echo "Rust 测试完成"

# 运行 Flutter 测试
test-frontend:
	@echo "运行 Flutter 测试..."
	flutter test
	@echo "Flutter 测试完成"

# 启动开发环境
run: build
	@echo "启动开发环境..."
	@echo "请在新终端中运行以下命令:"
	@echo "1. 启动后端: cd $(BACKEND_DIR) && cargo run --release"
	@echo "2. 启动前端: flutter run -d linux --debug"
	@echo ""
	@echo "或使用提供的脚本:"
	@echo "  ./run_dev.sh     完整编译并启动"
	@echo "  ./quick_start.sh 快速启动（需已编译）"

# 仅运行后端
backend: build-backend
	@echo "启动 Rust 后端..."
	cd $(BACKEND_DIR) && cargo run --release

# 仅运行前端
frontend: build-frontend
	@echo "启动 Flutter 前端..."
	flutter run -d linux --debug

# 快速开发启动（假设已编译）
dev:
	@echo "快速启动开发环境..."
	@if [ ! -f "$(BACKEND_DIR)/target/release/backend" ]; then \
		echo "错误: 未找到编译后的后端程序"; \
		echo "请先运行: make build-backend 或 ./run_dev.sh"; \
		exit 1; \
	fi
	@echo "启动后端..."
	@cd $(BACKEND_DIR) && ./target/release/backend &
	@BACKEND_PID=$$!; \
	echo "后端启动 (PID: $$BACKEND_PID)"; \
	echo "等待后端就绪..."; \
	sleep 3; \
	echo "启动前端..."; \
	flutter run -d linux --debug &
	@FLUTTER_PID=$$!; \
	echo "前端启动 (PID: $$FLUTTER_PID)"; \
	echo ""; \
	echo "服务已启动!"; \
	echo "后端: http://localhost:8080"; \
	echo "前端: 正在运行"; \
	echo ""; \
	echo "按 Ctrl+C 停止所有服务"; \
	trap 'kill $$BACKEND_PID $$FLUTTER_PID 2>/dev/null; echo "服务已停止"; exit' INT; \
	wait

# 运行代码检查
lint:
	@echo "运行代码检查..."
	@echo "1. 检查 Rust 代码..."
	cd $(BACKEND_DIR) && cargo clippy -- -D warnings
	@echo "2. 检查 Flutter 代码..."
	flutter analyze
	@echo "代码检查完成"

# 清理构建文件
clean:
	@echo "清理构建文件..."
	@if [ -d "$(BACKEND_DIR)/target" ]; then \
		cd $(BACKEND_DIR) && cargo clean; \
		echo "Rust 构建文件已清理"; \
	fi
	flutter clean
	@if [ -f "$(BACKEND_DIR)/backend.db" ]; then \
		rm "$(BACKEND_DIR)/backend.db"; \
		echo "数据库文件已清理"; \
	fi
	@echo "所有构建文件已清理"

# 格式化代码
format:
	@echo "格式化代码..."
	@echo "1. 格式化 Rust 代码..."
	cd $(BACKEND_DIR) && cargo fmt
	@echo "2. 格式化 Dart 代码..."
	flutter format lib/
	@echo "代码格式化完成"

# 检查依赖
deps:
	@echo "检查系统依赖..."
	@command -v cargo >/dev/null 2>&1 || { echo "错误: 未找到 cargo (Rust)"; exit 1; }
	@command -v flutter >/dev/null 2>&1 || { echo "错误: 未找到 flutter"; exit 1; }
	@command -v sqlite3 >/dev/null 2>&1 || echo "警告: 未找到 sqlite3"
	@echo "所有必需依赖已安装"

# 生成文档
doc:
	@echo "生成文档..."
	@echo "1. 生成 Rust 文档..."
	cd $(BACKEND_DIR) && cargo doc --no-deps
	@echo "2. 生成 Flutter 文档..."
	flutter pub global run dartdoc
	@echo "文档生成完成，打开:"
	@echo "  Rust: $(BACKEND_DIR)/target/doc/backend/index.html"
	@echo "  Dart: doc/api/index.html"