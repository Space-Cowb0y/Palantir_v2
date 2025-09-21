#include <iostream>
#include <memory>
#include <string>
#include <chrono>
#include <thread>

// #include "agent.grpc.pb.h" // gere os stubs conforme instruÃ§Ãµes no CMake

int main(int argc, char** argv) {
    std::string addr = std::getenv("SENTINEL_GRPC") ? std::getenv("SENTINEL_GRPC") : "127.0.0.1:50060";
    std::cout << "greeter-cpp skeleton. Set up gRPC stubs and send heartbeats to " << addr << std::endl;

    // PseudocÃ³digo:
    // auto channel = grpc::CreateChannel(addr, grpc::InsecureChannelCredentials());
    // std::unique_ptr<agent::Sentinel::Stub> stub = agent::Sentinel::NewStub(channel);
    // RegisterRequest req; req.set_name("greeter-cpp"); ...
    // auto reg = stub->Register(ctx, req);
    // auto stream = stub->StreamHeartbeats(&ctx);
    // loop: cria Heartbeat (started_unix fixo + now_unix variÃ¡vel), stream->Write(hb)

    // MantÃ©m vivo para teste
    std::this_thread::sleep_for(std::chrono::seconds(5));
    return 0;
}
