#!/bin/bash

# 先构建，注意初次构建前就需要改 esp sr 的版本为 =2.1.3
# 不然后续必须 cargo clean 后才能切换版本
cargo build --release -vv

# 然后烧录模型，地址 0x710000 和路径的 f3ef57aae54527db 只是我的主机的情况
# 需要根据实际情况查看固件烧录日志得到地址，翻找 target 文件夹得到路径
espflash write-bin \
    0x710000 \
    "target/xtensa-esp32s3-espidf/release/build/esp-idf-sys-f3ef57aae54527db/out/build/srmodels/srmodels.bin"

# 然后烧录固件
espflash flash  --monitor --partition-table ./partitions.csv --flash-size 16mb "target/xtensa-esp32s3-espidf/release/echokit"