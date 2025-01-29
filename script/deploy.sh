#!/bin/bash
source .env

# 创建记录部署地址的函数
record_addresses() {
    local network=$1
    local log_file="broadcast/Deploy.s.sol/$network/run-latest.json"
    
    # 检查日志文件是否存在
    if [ ! -f "$log_file" ]; then
        echo "Deployment log not found for $network"
        return
    }
    
    # 使用 jq 从日志中提取地址并更新 deployments/addresses.json
    # 这里需要根据实际的日志格式调整 jq 命令
    # TODO: 添加提取和更新地址的逻辑
}

# 部署到 Sepolia
echo "Deploying to Sepolia..."
forge script script/Deploy.s.sol:Deploy --rpc-url sepolia --broadcast --verify -vvvv
record_addresses "sepolia"

# 部署到 Base
echo "Deploying to Base..."
forge script script/Deploy.s.sol:Deploy --rpc-url base --broadcast --verify -vvvv
record_addresses "base"

# 部署到 BSC
echo "Deploying to BSC..."
forge script script/Deploy.s.sol:Deploy --rpc-url bsc --broadcast --verify -vvvv
record_addresses "bsc"

# 部署到 Arbitrum
echo "Deploying to Arbitrum..."
forge script script/Deploy.s.sol:Deploy --rpc-url arbitrum --broadcast --verify -vvvv
record_addresses "arbitrum"

# 部署到 Optimism
echo "Deploying to Optimism..."
forge script script/Deploy.s.sol:Deploy --rpc-url optimism --broadcast --verify -vvvv
record_addresses "optimism" 
