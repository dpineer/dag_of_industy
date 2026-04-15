# 工业生产链模拟器 - 一键编译测试运行脚本

本文档介绍如何快速编译、测试和运行工业生产链模拟器项目。

## 项目结构

```
dag_of_industy/
├── backend/          # Rust 后端
│   ├── src/
│   │   ├── main.rs   # 主入口
│   │   └── models.rs # 数据模型
│   └── Cargo.toml    # Rust 依赖
├── lib/              # Flutter 前端
│   ├── main.dart     # 主界面
│   ├── providers.dart # 状态管理
│   └── models.dart   # 数据模型
├── run_dev.sh        # 完整开发脚本
├── quick_start.sh    # 快速启动脚本
├── Makefile          # 传统构建工具
└── SCRIPTS_README.md # 本文档
```

## 脚本说明

### 1. `run_dev.sh` - 完整开发脚本

**功能**：完整的编译、测试和启动流程

**使用方法**：
```bash
# 给予执行权限（首次使用）
chmod +x run_dev.sh

# 正常启动（编译并启动）
./run_dev.sh

# 清理构建文件后启动
./run_dev.sh --clean

# 运行测试后启动
./run_dev.sh --test

# 显示帮助
./run_dev.sh --help
```

**执行流程**：
1. 检查系统依赖（Rust, Flutter）
2. 可选：清理构建文件（--clean）
3. 可选：运行测试（--test）
4. 编译 Rust 后端（release 模式）
5. 编译 Flutter 前端（release 模式）
6. 启动 Rust 后端服务器（端口 8080）
7. 启动 Flutter 前端（debug 模式）
8. 显示服务状态和 API 信息

**API 端点**：
- `GET  /api/simulation/state` - 获取模拟状态
- `POST /api/atoms` - 创建 Atom
- `POST /api/structs/manual` - 验证手动结构
- `POST /api/structs/auto` - 自动生成结构
- `POST /api/simulation/start` - 启动模拟
- `GET  /api/analysis/metrics` - 获取分析指标

### 2. `quick_start.sh` - 快速启动脚本

**功能**：快速启动已编译的服务（不重新编译）

**使用方法**：
```bash
# 给予执行权限
chmod +x quick_start.sh

# 快速启动
./quick_start.sh
```

**前提条件**：
- 已编译 Rust 后端（`backend/target/release/backend` 存在）
- Flutter 依赖已获取

**适用场景**：
- 日常开发快速重启
- 代码修改后的快速测试
- 演示和展示

### 3. `Makefile` - 传统构建工具

**功能**：提供传统的 make 命令

**常用命令**：
```bash
# 显示所有命令
make help

# 编译前后端
make build

# 运行所有测试
make test

# 快速开发启动
make dev

# 清理构建文件
make clean

# 运行代码检查
make lint

# 格式化代码
make format

# 检查依赖
make deps
```

## 开发工作流

### 首次设置
```bash
# 1. 确保系统依赖
#    - Rust (cargo)
#    - Flutter SDK
#    - SQLite3 (可选)

# 2. 检查依赖
make deps

# 3. 完整编译和启动
./run_dev.sh --clean
```

### 日常开发
```bash
# 方法1：使用完整脚本（推荐）
./run_dev.sh

# 方法2：使用 Makefile
make dev

# 方法3：手动启动
# 终端1：启动后端
cd backend && cargo run --release

# 终端2：启动前端
flutter run -d linux --debug
```

### 代码质量检查
```bash
# 运行测试
make test

# 代码检查
make lint

# 格式化代码
make format
```

## 故障排除

### 1. 端口 8080 被占用
脚本会自动尝试停止占用端口的进程。如果失败，手动停止：
```bash
sudo lsof -ti:8080 | xargs kill -9
```

### 2. Rust 编译错误
```bash
# 清理并重新编译
cd backend && cargo clean
cargo build --release
```

### 3. Flutter 依赖问题
```bash
# 清理并重新获取依赖
flutter clean
flutter pub get
```

### 4. 数据库问题
```bash
# 删除数据库文件重新开始
rm backend/backend.db
```

## 环境要求

- **操作系统**：Linux (Debian 13 测试通过)
- **Rust**：1.70+ (`cargo --version`)
- **Flutter**：3.22+ (`flutter --version`)
- **SQLite3**：3.37+ (可选，用于数据库功能)
- **内存**：建议 4GB+
- **磁盘空间**：建议 2GB+ 用于构建缓存

## 性能优化

### 开发模式
```bash
# 使用快速启动脚本避免重复编译
./quick_start.sh
```

### 生产构建
```bash
# Rust 后端优化编译
cd backend && cargo build --release

# Flutter 前端优化构建
flutter build linux --release --split-debug-info
```

## 扩展脚本

如果需要自定义功能，可以修改脚本：

1. **修改端口**：编辑脚本中的 `8080` 为其他端口
2. **添加环境变量**：在脚本开头添加 `export KEY=value`
3. **自定义构建参数**：修改 `cargo build` 或 `flutter build` 参数

## 贡献指南

1. 运行测试确保功能正常
2. 通过代码检查
3. 更新脚本文档
4. 提交 Pull Request

## 许可证

本项目脚本遵循 MIT 许可证。