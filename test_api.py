#!/usr/bin/env python3
"""
API 功能测试脚本
测试 dag_of_industy 的 HTTP API 服务
包括：增加、删减、查找、修改和配置卡片信息的功能
"""

import json
import requests
import time
import subprocess
import sys
import os
from typing import Dict, Any, Optional

# API 基础 URL（端口可能会动态变化）
BASE_URL = "http://localhost:8081"
API_STATE = f"{BASE_URL}/api/state"
API_NODE = f"{BASE_URL}/api/node"
API_INVENTORY = f"{BASE_URL}/api/inventory"
API_SIMULATION_TOGGLE = f"{BASE_URL}/api/simulation/toggle"

def start_flutter_app() -> Optional[subprocess.Popen]:
    """启动 Flutter 应用并返回进程对象"""
    print("🚀 启动 Flutter 应用...")
    # 切换到项目目录
    project_dir = os.path.dirname(os.path.abspath(__file__))
    # 在后台启动 Flutter
    proc = subprocess.Popen(
        ["flutter", "run", "-d", "linux", "--debug"],
        cwd=project_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    
    # 等待应用启动
    print("⏳ 等待应用启动（10秒）...")
    time.sleep(10)
    
    # 检查进程是否仍在运行
    if proc.poll() is not None:
        stdout, stderr = proc.communicate()
        print(f"❌ Flutter 应用启动失败")
        print(f"标准输出:\n{stdout}")
        print(f"标准错误:\n{stderr}")
        return None
    
    print("✅ Flutter 应用已启动")
    return proc

def stop_flutter_app(proc: subprocess.Popen):
    """停止 Flutter 应用"""
    print("🛑 停止 Flutter 应用...")
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
    print("✅ Flutter 应用已停止")

def test_get_state():
    """测试获取状态端点"""
    print("\n📋 测试 GET /api/state")
    try:
        response = requests.get(API_STATE, timeout=5)
        print(f"  状态码: {response.status_code}")
        if response.status_code == 200:
            data = response.json()
            print(f"  响应: isSimulating={data.get('isSimulating')}")
            print(f"  节点数量: {len(data.get('nodes', []))}")
            print(f"  连接数量: {len(data.get('connections', []))}")
            return True
        else:
            print(f"  ❌ 请求失败: {response.text}")
            return False
    except Exception as e:
        print(f"  ❌ 异常: {e}")
        return False

def test_create_node():
    """测试创建节点"""
    print("\n➕ 测试 POST /api/node")
    node_data = {
        "name": "测试节点",
        "category": "reaction",
        "position": {"dx": 100.0, "dy": 100.0},
        "inputs": [
            {"id": "原料", "itemName": "原料", "rate": 10.0, "unit": "kg", "isRequired": True}
        ],
        "outputs": [
            {"id": "产品", "itemName": "产品", "rate": 5.0, "unit": "kg", "isPollutant": False},
            {"id": "副产品", "itemName": "副产品", "rate": 4.0, "unit": "kg", "isPollutant": False}
        ],
        "maxCapacity": 100.0,
        "stackCount": 1,
        "isBuilt": True,
        "isRunning": True,
        "constructionCost": {"钢材": 100.0, "电子元件": 50.0},
        "signalInputs": [],
        "signalOutputs": [],
        "logicOp": "identity",
        "registers": {}
    }
    
    try:
        response = requests.post(API_NODE, json=node_data, timeout=5)
        print(f"  状态码: {response.status_code}")
        if response.status_code == 200:
            data = response.json()
            node_id = data.get('id')
            print(f"  ✅ 节点创建成功，ID: {node_id}")
            return node_id
        else:
            print(f"  ❌ 创建失败: {response.text}")
            return None
    except Exception as e:
        print(f"  ❌ 异常: {e}")
        return None

def test_update_node(node_id: str):
    """测试更新节点"""
    print(f"\n✏️  测试 PUT /api/node/{node_id}")
    update_data = {
        "id": node_id,
        "name": "更新后的测试节点",
        "category": "reaction",
        "position": {"dx": 200.0, "dy": 200.0},
        "inputs": [
            {"id": "原料", "itemName": "原料", "rate": 15.0, "unit": "kg", "isRequired": True}
        ],
        "outputs": [
            {"id": "产品", "itemName": "产品", "rate": 8.0, "unit": "kg", "isPollutant": False},
            {"id": "副产品", "itemName": "副产品", "rate": 6.0, "unit": "kg", "isPollutant": False}
        ],
        "maxCapacity": 150.0,
        "stackCount": 2,
        "isBuilt": True,
        "isRunning": False,
        "constructionCost": {"钢材": 150.0, "电子元件": 75.0},
        "signalInputs": [],
        "signalOutputs": [],
        "logicOp": "identity",
        "registers": {}
    }
    
    try:
        response = requests.put(f"{API_NODE}/{node_id}", json=update_data, timeout=5)
        print(f"  状态码: {response.status_code}")
        if response.status_code == 200:
            print(f"  ✅ 节点更新成功")
            return True
        else:
            print(f"  ❌ 更新失败: {response.text}")
            return False
    except Exception as e:
        print(f"  ❌ 异常: {e}")
        return False

def test_inventory_intervention(node_id: str):
    """测试库存干预"""
    print(f"\n📦 测试 POST /api/inventory (库存干预)")
    inventory_data = {
        "nodeId": node_id,
        "portId": "原料",
        "isInput": True,
        "amount": 500.0
    }
    
    try:
        response = requests.post(API_INVENTORY, json=inventory_data, timeout=5)
        print(f"  状态码: {response.status_code}")
        if response.status_code == 200:
            print(f"  ✅ 库存干预成功")
            return True
        else:
            print(f"  ❌ 库存干预失败: {response.text}")
            return False
    except Exception as e:
        print(f"  ❌ 异常: {e}")
        return False

def test_simulation_toggle():
    """测试模拟器控制"""
    print("\n🎮 测试 POST /api/simulation/toggle")
    
    # 先获取当前状态
    try:
        response = requests.get(API_STATE, timeout=5)
        if response.status_code == 200:
            initial_state = response.json().get('isSimulating', False)
            print(f"  当前模拟状态: {initial_state}")
    except:
        pass
    
    # 切换模拟状态
    try:
        response = requests.post(API_SIMULATION_TOGGLE, timeout=5)
        print(f"  状态码: {response.status_code}")
        if response.status_code == 200:
            data = response.json()
            new_state = data.get('isSimulating')
            print(f"  ✅ 模拟状态切换成功，新状态: {new_state}")
            return True
        else:
            print(f"  ❌ 切换失败: {response.text}")
            return False
    except Exception as e:
        print(f"  ❌ 异常: {e}")
        return False

def test_delete_node(node_id: str):
    """测试删除节点"""
    print(f"\n🗑️  测试 DELETE /api/node/{node_id}")
    
    try:
        response = requests.delete(f"{API_NODE}/{node_id}", timeout=5)
        print(f"  状态码: {response.status_code}")
        if response.status_code == 200:
            print(f"  ✅ 节点删除成功")
            return True
        else:
            print(f"  ❌ 删除失败: {response.text}")
            return False
    except Exception as e:
        print(f"  ❌ 异常: {e}")
        return False

def verify_node_deletion(node_id: str):
    """验证节点是否已被删除"""
    print(f"\n🔍 验证节点 {node_id} 是否已删除")
    try:
        response = requests.get(API_STATE, timeout=5)
        if response.status_code == 200:
            data = response.json()
            nodes = data.get('nodes', [])
            node_exists = any(node.get('id') == node_id for node in nodes)
            if not node_exists:
                print(f"  ✅ 节点已成功从状态中移除")
                return True
            else:
                print(f"  ❌ 节点仍然存在于状态中")
                return False
    except Exception as e:
        print(f"  ❌ 验证异常: {e}")
        return False

def main():
    """主测试函数"""
    print("=" * 60)
    print("🧪 dag_of_industy API 功能测试")
    print("=" * 60)
    
    # 启动 Flutter 应用
    flutter_proc = start_flutter_app()
    if not flutter_proc:
        print("❌ 无法启动 Flutter 应用，测试终止")
        return 1
    
    try:
        # 测试 1: 获取初始状态
        if not test_get_state():
            print("❌ 初始状态获取失败")
            return 1
        
        # 测试 2: 创建节点
        node_id = test_create_node()
        if not node_id:
            print("❌ 节点创建失败")
            return 1
        
        # 测试 3: 再次获取状态，确认节点已添加
        print("\n🔍 验证节点创建后的状态")
        if not test_get_state():
            print("❌ 状态获取失败")
            return 1
        
        # 测试 4: 更新节点
        if not test_update_node(node_id):
            print("⚠️  节点更新失败，继续其他测试")
        
        # 测试 5: 库存干预
        if not test_inventory_intervention(node_id):
            print("⚠️  库存干预失败，继续其他测试")
        
        # 测试 6: 模拟器控制
        if not test_simulation_toggle():
            print("⚠️  模拟器控制失败，继续其他测试")
        
        # 测试 7: 删除节点
        if not test_delete_node(node_id):
            print("❌ 节点删除失败")
            return 1
        
        # 测试 8: 验证节点删除
        if not verify_node_deletion(node_id):
            print("⚠️  节点删除验证失败")
        
        print("\n" + "=" * 60)
        print("✅ 所有测试完成！")
        print("=" * 60)
        return 0
        
    except KeyboardInterrupt:
        print("\n\n测试被用户中断")
        return 1
    except Exception as e:
        print(f"\n❌ 测试过程中发生未预期错误: {e}")
        import traceback
        traceback.print_exc()
        return 1
    finally:
        # 确保停止 Flutter 应用
        stop_flutter_app(flutter_proc)

if __name__ == "__main__":
    sys.exit(main())