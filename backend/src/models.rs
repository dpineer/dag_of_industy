use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// 线性逻辑二元算符
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum LinearOp {
    /// 离散乘法 (Tensor / 逗号, 代表并发与资源累加)
    Tensor,
    /// 加法合取 (With / &, 代表消费者选择/外选择)
    AdditiveConjunction,
    /// 加法析取 (Plus / ⊕, 代表生产者选择/内选择)
    AdditiveDisjunction,
}

/// Item (命题 / 资源类型)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Item {
    Atom {
        id: String,
        name: String,
        metadata: String,
    },
    Struct {
        left: Box<Item>,
        op: LinearOp,
        right: Box<Item>,
    },
}

/// Diagram (相继式 / 生产过程)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Diagram {
    Atom {
        id: String,
        premise: Vec<Item>,    // 输入资源
        conclusion: Vec<Item>, // 输出产物
    },
    Struct {
        id: String,
        sub_diagrams: Vec<Diagram>,
        // 包含时空约束元数据
        time_constraint: Option<TimeConstraint>,
        space_constraint: Option<SpaceConstraint>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeConstraint {
    pub start: i64,
    pub end: i64,
    pub duration: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpaceConstraint {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

/// 数据库实体：Atom 记录
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct AtomRecord {
    pub id: String,
    pub name: String,
    pub metadata: String,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// 数据库实体：Diagram 记录
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct DiagramRecord {
    pub id: String,
    pub diagram_type: String, // "atom" 或 "struct"
    pub data: serde_json::Value,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// 模拟状态
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationState {
    pub id: String,
    pub diagram_id: String,
    pub step: i32,
    pub state_data: serde_json::Value,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// API 请求/响应类型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateAtomRequest {
    pub name: String,
    pub metadata: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateAtomResponse {
    pub id: String,
    pub status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerifyStructRequest {
    pub diagram: Diagram,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerifyStructResponse {
    pub status: String,
    pub valid: bool,
    pub errors: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GenerateStructRequest {
    pub constraints: Vec<Item>,
    pub goals: Vec<Item>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationStateResponse {
    pub step: i32,
    pub nodes: Vec<SimulationNode>,
    pub connections: Vec<SimulationConnection>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationNode {
    pub id: String,
    pub name: String,
    pub position: (f64, f64),
    pub status: String,
    pub inventory: std::collections::HashMap<String, f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationConnection {
    pub source_node_id: String,
    pub source_port_id: String,
    pub target_node_id: String,
    pub target_port_id: String,
    pub flow_rate: f64,
}

impl Item {
    pub fn new_atom(name: String, metadata: String) -> Self {
        Item::Atom {
            id: Uuid::new_v4().to_string(),
            name,
            metadata,
        }
    }
    
    pub fn new_struct(left: Item, op: LinearOp, right: Item) -> Self {
        Item::Struct {
            left: Box::new(left),
            op,
            right: Box::new(right),
        }
    }
}