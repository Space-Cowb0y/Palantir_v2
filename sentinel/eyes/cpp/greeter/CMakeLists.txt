cmake_minimum_required(VERSION 3.20)
project(greeter)
set(CMAKE_CXX_STANDARD 17)

find_package(Protobuf CONFIG REQUIRED)
find_package(gRPC CONFIG REQUIRED)

add_executable(greeter main.cpp)
target_include_directories(greeter PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
target_link_libraries(greeter PRIVATE gRPC::grpc++ protobuf::libprotobuf)

# Gere os stubs a partir de ../../api/agent.proto antes (protoc):
# protoc --grpc_out=. --plugin=protoc-gen-grpc=<path_grpc_cpp_plugin> --cpp_out=. -I ../../api ../../api/agent.proto
# Isso criarÃ¡ agent.pb.h/.cc e agent.grpc.pb.h/.cc; adicione-os ao target:
# target_sources(greeter PRIVATE agent.pb.cc agent.grpc.pb.cc)
