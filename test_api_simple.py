#!/usr/bin/env python3
"""
简单 API 测试脚本 - 使用现有节点结构作为模板
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

def test_with_existing_template():
    """使用现有节点结构作为模板进行测试"""
    # 获取现有节点作为模板
    resp = requests.get(f"{BASE_URL}/api/state", timeout=5)
    data = resp.json()
    nodes = data.get('nodes', [])
    if not nodes:
        print("没有现有节点可用作模板")
        return False
    
    template = nodes[0]
    print(f"使用节点模板: {template['name']}")
    
    # 修改模板以创建新节点
    new_node = dict(template)
    new_node['id'] = 'test-node-' + str(int(time.time()))
    new_node['name'] = 'API测试节点'
    new_node['position'] = {'dx': 500.0, 'dy': 500.0}
    
    print(f"创建新节点: {new_node['name']}")
    resp = requests.post(f"{BASE_URL}/api/node", json=new_node, timeout=5)
    print(f"状态码: {resp.status_code}")
    print(f"响应: {resp.text}")
    
    if resp.status_code == 200:
        node_id = resp.json().get('id')
        print(f"✅ 节点创建成功，ID: {node_id}")
        
        # 测试删除
        print(f"\n删除节点 {node_id}")
        resp = requests.delete(f"{BASE_URL}/api/node/{node_id}", timeout=5)
        print(f"状态码: {resp.status_code}")
        print(f"响应: {resp.text}")
        if resp.status_code == 200:
            print("✅ 节点删除成功")
            return True
        else:
            print("❌ 节点删除失败")
            return False
    else:
        print("❌ 节点创建失败")
        return False

def main():
    print("=" * 60)
    print("简单 API 测试 - 使用现有模板")
    print("=" * 60)
    
    proc = start_flutter()
    try:
        time.sleep(2)  # 额外等待
        success = test_with_existing_template()
        if success:
            print("\n✅ 测试通过！")
            return 0
        else:
            print("\n❌ 测试失败")
            return 1
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