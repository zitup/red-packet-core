pragma circom 2.0.0;

include "../lib/circomlib/circuits/poseidon.circom";

template CodeHasher() {
    signal input redPacketAddress;  // 红包地址
    signal input userAddress;   // 用户地址
    signal input password;     // 用户输入的密码

    signal output part1;
    signal output part2;
    signal output part3;

    // 计算密码哈希
    component poseidon = Poseidon(1);
    poseidon.inputs[0] <== password;

    // 输出三个部分
    part1 <== poseidon.out;
    part2 <== redPacketAddress;
    part3 <== userAddress;

    // // 计算最终哈希
    // signal combinedBytes;
    // component finalHasher = Poseidon(3); // 使用Poseidon对3个输入进行哈希
    // finalHasher.inputs[0] <== poseidon.out; // Poseidon输出
    // finalHasher.inputs[1] <== userAddress;   // 用户地址
    // finalHasher.inputs[2] <== redPacketAddress;    // 红包地址

    // out <== finalHasher.out; // 最终哈希输出

    // 将三个值拼接在一起
    // passwordHash (32 bytes) + redPacketAddress (20 bytes) + userAddress (20 bytes)
    // out <== poseidon.out * (1 << 320) + // 先移位 (20+20)*8 位
    //             redPacketAddress * (1 << 160) + // 再移位 20*8 位
    //             userAddress; // 最后放用户地址
}

component main = CodeHasher();
