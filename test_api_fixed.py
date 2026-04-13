#!/usr/bin/env python3
"""
修复的 API 测试脚本 - 手动构建正确的节点结构
"""

import json
import requests
import time
import subprocess
import sys
import os

BASE_URL = "http://localhost:8081"

def start_flutter():
    """启动 Flutter 应用"""
    print("启动 Flutter 应用...")
    proc = subprocess.Popen(
        ["flutter", "run", "-d", "linux", "--debug"],
        cwd=os.path.dirname(os.path.abspath(__file__)),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    time.sleep(10)
    return proc

def stop_flutter(proc):
    """停止 Flutter 应用"""
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()

def create_valid_node():
    """创建符合 Dart 类型要求的有效节点数据"""
    import uuid
    
    node_id = str(uuid.uuid4())
    
    # 基于 models.dart 中的 ProductionNode 结构构建
    node = {
        "id": node_id,
        "name": "API测试节点",
        "category": "reaction",
        "inputs": [
            {
                "id": "原料",
                "itemName": "原料",
                "rate": 10.0,
                "unitCost": 0.0,
                "unit": "kg",
                "isRequired": True
            }
        ],
        "outputs": [
            {
                "id": "产品",
                "itemName": "产品",
                "rate": 5.0,
                "unitCost": 0.0,
                "unit": "kg",
                "isPollutant": False,
                "isDiscarded": False,
                "isConstructionMaterial": False
            },
            {
                "id": "副产品",
                "itemName": "副产品",
                "rate": 4.0,
                "unitCost": 0.0,
                "unit": "kg",
                "isPollutant": False,
                "isDiscarded": False,
                "isConstructionMaterial": False
            }
        ],
        "position": {"dx": 500.0, "dy": 500.0},
        "maxCapacity": 100.0,
        "stackCount": 1,
        "isBuilt": True,
        "isRunning": True,
        "constructionCost": {
            "钢材": 100.0,
            "电子元件": 50.0
        },
        "logicTargetNodeId": None,
        "logicAction": None,
        "logicCondition": None,
        "conditionValue": None,
        "conditionPortId": None,
        "conditionTargetNodeId": None,
        "signalInputs": [],
        "signalOutputs": [],
        "logicOp": "identity",
        "registers": {},
        # 以下字段在 toJson 中未包含，但 fromJson 会使用默认值
        # 为了安全，我们仍然包含它们
        "maintenanceRate": 1.0,
        "failureProbability": 0.0,
        "runningCost": 0.0,
        "progress": 0.0,
        "status": "idle",
        "inputInventory": {},
        "outputInventory": {}
    }
    
    # 确保所有数值都是浮点数，但保留布尔值
    def ensure_floats(obj):
        if isinstance(obj, dict):
            return {k: ensure_floats(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [ensure_floats(v) for v in obj]
        elif isinstance(obj, int) and not isinstance(obj, bool):
            return float(obj)
        else:
            return obj
    
    return ensure_floats(node)

def test_creation_and_deletion():
    """测试节点创建和删除"""
    node_data = create_valid_node()
    
    print("创建节点...")
    print(f"节点数据摘要: name={node_data['name']}, category={node_data['category']}")
    
    resp = requests.post(f"{BASE_URL}/api/node", json=node_data, timeout=5)
    print(f"状态码: {resp.status_code}")
    if resp.status_code != 200:
        print(f"响应: {resp.text}")
        return None
    
    result = resp.json()
    node_id = result.get('id')
    print(f"✅ 节点创建成功，ID: {node_id}")
    
    # 验证节点已添加
    resp = requests.get(f"{BASE_URL}/api/state", timeout=5)
    data = resp.json()
    nodes = data.get('nodes', [])
    found = any(n.get('id') == node_id for n in nodes)
    if found:
        print("✅ 节点已成功添加到状态")
    else:
        print("⚠️  节点未在状态中找到")
    
    return node_id

def test_deletion(node_id):
    """测试节点删除"""
    print(f"\n删除节点 {node_id}")
    resp = requests.delete(f"{BASE_URL}/api/node/{node_id}", timeout=5)
    print(f"状态码: {resp.status_code}")
    if resp.status_code != 200:
        print(f"响应: {resp.text}")
        return False
    
    print("✅ 节点删除成功")
    
    # 验证节点已删除
    resp = requests.get(f"{BASE_URL}/api/state", timeout=5)
    data = resp.json()
    nodes = data.get('nodes', [])
    found = any(n.get('id') == node_id for n in nodes)
    if not found:
        print("✅ 节点已从状态中移除")
        return True
    else:
        print("❌ 节点仍然存在于状态中")
        return False

def main():
    print("=" * 60)
    print("修复的 API 测试 - 手动构建节点结构")
    print("=" * 60)
    
    proc = start_flutter()
    try:
        time.sleep(2)  # 额外等待
        
        # 测试创建
        node_id = test_creation_and_deletion()
        if not node_id:
            print("\n❌ 节点创建测试失败")
            return 1
        
        # 测试删除
        success = test_deletion(node_id)
        if not success:
            print("\n❌ 节点删除测试失败")
            return 1
        
        print("\n" + "=" * 60)
        print("✅ 所有测试通过！")
        print("=" * 60)
        return 0
        
    except Exception as e:
        print(f"\n❌ 测试异常: {e}")
        import traceback
        traceback.print_exc()
        return 1
    finally:
        print("\n停止 Flutter 应用...")
        stop_flutter(proc)

if __name__ == "__main__":
    sys.exit(main())