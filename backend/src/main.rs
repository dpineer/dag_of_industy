mod models;

use axum::{
    extract::State,
    http::{HeaderValue, Method},
    routing::{get, post},
    Json, Router,
};
use models::*;
use sqlx::{sqlite::SqlitePoolOptions, SqlitePool};
use std::{net::SocketAddr, sync::Arc};
use tokio::net::TcpListener;
use tower_http::cors::CorsLayer;
use tracing_subscriber;

// 应用状态
#[derive(Clone)]
struct AppState {
    db_pool: SqlitePool,
}

#[tokio::main]
async fn main() {
    // 初始化日志
    tracing_subscriber::fmt::init();

    // 初始化数据库
    let db_pool = init_database().await.expect("Failed to initialize database");

    // 创建应用状态
    let state = Arc::new(AppState { db_pool });

    // 配置 CORS
    let cors = CorsLayer::new()
        .allow_origin("http://localhost:3000".parse::<HeaderValue>().unwrap())
        .allow_methods([Method::GET, Method::POST, Method::PUT, Method::DELETE])
        .allow_headers([axum::http::header::CONTENT_TYPE]);

    // 路由注册映射5项需求
    let app = Router::new()
        // 1. 录入 Atom，并给出信源/辅助信息
        .route("/api/atoms", post(create_atom))
        // 2. 手工构造 Struct (提交带连接关系的图校验其逻辑合法性)
        .route("/api/structs/manual", post(verify_manual_struct))
        // 3. 自动生成 Struct (调用底层求解器)
        .route("/api/structs/auto", post(generate_struct_from_solver))
        // 4. 模拟/推理 Diagram (启动推演时钟)
        .route("/api/simulation/start", post(start_simulation))
        // 获取实时推演状态 (可改为 WebSocket)
        .route("/api/simulation/state", get(get_simulation_state))
        // 5. 数据分析功能
        .route("/api/analysis/metrics", get(get_analysis_metrics))
        .layer(cors)
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], 8080));
    println!("🚀[Logic Backend] 线性逻辑引擎运行于 http://{}", addr);
    
    let listener = TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

async fn init_database() -> Result<SqlitePool, sqlx::Error> {
    // 创建数据库连接池
    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect("sqlite:backend.db")
        .await?;

    // 创建表
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS atoms (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            metadata TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
        "#,
    )
    .execute(&pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS diagrams (
            id TEXT PRIMARY KEY,
            diagram_type TEXT NOT NULL,
            data JSON NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
        "#,
    )
    .execute(&pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS simulation_states (
            id TEXT PRIMARY KEY,
            diagram_id TEXT NOT NULL,
            step INTEGER NOT NULL,
            state_data JSON NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (diagram_id) REFERENCES diagrams(id)
        )
        "#,
    )
    .execute(&pool)
    .await?;

    Ok(pool)
}

// --- Handlers ---

async fn create_atom(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<CreateAtomRequest>,
) -> Json<CreateAtomResponse> {
    let id = uuid::Uuid::new_v4().to_string();
    
    match sqlx::query(
        "INSERT INTO atoms (id, name, metadata) VALUES (?, ?, ?)"
    )
    .bind(&id)
    .bind(&payload.name)
    .bind(&payload.metadata)
    .execute(&state.db_pool)
    .await
    {
        Ok(_) => Json(CreateAtomResponse {
            id,
            status: "success".to_string(),
        }),
        Err(e) => {
            tracing::error!("Failed to create atom: {}", e);
            Json(CreateAtomResponse {
                id: "".to_string(),
                status: format!("error: {}", e),
            })
        }
    }
}

async fn verify_manual_struct(
    Json(payload): Json<VerifyStructRequest>,
) -> Json<VerifyStructResponse> {
    // TODO: 执行割公理校验，确保输入输出资源严格匹配(无弱化/无收缩)
    // 这里实现简单的校验逻辑
    let diagram = payload.diagram;
    let mut errors = Vec::new();
    
    match diagram {
        Diagram::Atom { premise, conclusion, .. } => {
            // 检查资源守恒
            let total_input = premise.len();
            let total_output = conclusion.len();
            
            if total_input != total_output {
                errors.push(format!("资源不守恒: 输入 {} 项, 输出 {} 项", total_input, total_output));
            }
            
            // 检查是否有重复资源
            let input_names: Vec<String> = premise.iter()
                .filter_map(|item| match item {
                    Item::Atom { name, .. } => Some(name.clone()),
                    _ => None,
                })
                .collect();
            
            let output_names: Vec<String> = conclusion.iter()
                .filter_map(|item| match item {
                    Item::Atom { name, .. } => Some(name.clone()),
                    _ => None,
                })
                .collect();
            
            if input_names.len() != input_names.iter().collect::<std::collections::HashSet<_>>().len() {
                errors.push("输入资源有重复".to_string());
            }
            
            if output_names.len() != output_names.iter().collect::<std::collections::HashSet<_>>().len() {
                errors.push("输出资源有重复".to_string());
            }
        }
        Diagram::Struct { sub_diagrams, .. } => {
            if sub_diagrams.is_empty() {
                errors.push("Struct Diagram 不能为空".to_string());
            }
        }
    }
    
    let valid = errors.is_empty();
    Json(VerifyStructResponse {
        status: if valid { "verified".to_string() } else { "failed".to_string() },
        valid,
        errors,
    })
}

async fn generate_struct_from_solver(
    Json(_params): Json<serde_json::Value>,
) -> Json<Diagram> {
    // TODO: 转换为 SMT-LIB 格式送入 Z3，求解满足约束的 Space Time Struct Diagram
    // 这里返回一个示例 Diagram
    Json(Diagram::Struct {
        id: uuid::Uuid::new_v4().to_string(),
        sub_diagrams: vec![
            Diagram::Atom {
                id: "atom1".to_string(),
                premise: vec![Item::new_atom("原料A".to_string(), "".to_string())],
                conclusion: vec![Item::new_atom("中间品B".to_string(), "".to_string())],
            },
            Diagram::Atom {
                id: "atom2".to_string(),
                premise: vec![Item::new_atom("中间品B".to_string(), "".to_string())],
                conclusion: vec![Item::new_atom("成品C".to_string(), "".to_string())],
            },
        ],
        time_constraint: Some(TimeConstraint {
            start: 0,
            end: 100,
            duration: 100,
        }),
        space_constraint: Some(SpaceConstraint {
            x: 0.0,
            y: 0.0,
            width: 1000.0,
            height: 800.0,
        }),
    })
}

async fn start_simulation() -> Json<serde_json::Value> {
    // TODO: 初始化状态机，按照线性推演规则消费和生产 Item
    Json(serde_json::json!({
        "status": "started",
        "simulation_id": uuid::Uuid::new_v4().to_string()
    }))
}

async fn get_simulation_state() -> Json<SimulationStateResponse> {
    // TODO: 返回模拟状态
    Json(SimulationStateResponse {
        step: 0,
        nodes: vec![
            SimulationNode {
                id: "node1".to_string(),
                name: "生产节点A".to_string(),
                position: (100.0, 100.0),
                status: "running".to_string(),
                inventory: [("原料A".to_string(), 50.0)].iter().cloned().collect(),
            },
            SimulationNode {
                id: "node2".to_string(),
                name: "生产节点B".to_string(),
                position: (300.0, 100.0),
                status: "running".to_string(),
                inventory: [("中间品B".to_string(), 30.0)].iter().cloned().collect(),
            },
        ],
        connections: vec![
            SimulationConnection {
                source_node_id: "node1".to_string(),
                source_port_id: "output1".to_string(),
                target_node_id: "node2".to_string(),
                target_port_id: "input1".to_string(),
                flow_rate: 10.0,
            },
        ],
    })
}

async fn get_analysis_metrics() -> Json<serde_json::Value> {
    // TODO: 返回分析指标
    Json(serde_json::json!({
        "total_nodes": 2,
        "total_connections": 1,
        "throughput": 10.0,
        "efficiency": 0.85,
        "resource_utilization": 0.75
    }))
}