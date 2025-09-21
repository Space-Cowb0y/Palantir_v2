fn main() {
    tonic_build::configure()
        .out_dir("src/pb")
        .compile(&["../../../api/agent.proto"], &["../../../api"])
        .unwrap();
    println!("cargo:rerun-if-changed=../../../api/agent.proto");
}
