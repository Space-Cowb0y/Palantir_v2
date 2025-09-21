mod pb {
    pub mod agent {
        include!("pb/agent.rs");
    }
}

use pb::agent::{sentinel_client::SentinelClient, RegisterRequest, Heartbeat};
use std::time::{SystemTime, UNIX_EPOCH, Duration};
use tonic::Request;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = std::env::var("SENTINEL_GRPC").unwrap_or_else(|_| "http://127.0.0.1:50060".to_string());
    let mut client = SentinelClient::connect(addr.clone()).await?;

    let hostname = hostname::get().unwrap_or_default().to_string_lossy().to_string();
    let reg = RegisterRequest{
        id: "".into(),
        name: "greeter-rs".into(),
        version: "0.1.0".into(),
        language: "rust".into(),
        hostname,
        description: "hello from greeter-rs".into(),
    };
    let rsp = client.register(Request::new(reg)).await?.into_inner();
    let agent_id = rsp.assigned_id;

    let mut stream = client.stream_heartbeats().await?.into_inner();
    let start = now_unix();

    let mut interval = tokio::time::interval(Duration::from_secs(2));
    loop {
        interval.tick().await;
        let hb = Heartbeat{
            agent_id: agent_id.clone(),
            started_unix: start as i64,
            now_unix: now_unix() as i64,
            status: "running".into(),
            note: "OK".into(),
        };
        if let Err(e) = stream.send(hb).await {
            eprintln!("send hb: {e}");
            break;
        }
    }
    Ok(())
}

fn now_unix() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs()
}
