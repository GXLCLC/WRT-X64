#!/bin/bash
# 在编译完成后执行：固件后处理

echo "=== DIY Part 2: Post-compile Customization ==="

FIRMWARE_DIR="bin/targets/x86/64"
if [ -d "$FIRMWARE_DIR" ]; then
    cd $FIRMWARE_DIR
    sha256sum *.img.gz > sha256sums 2>/dev/null || true
    echo "Firmware files:"
    ls -lh *.img.gz
fi

echo "=== DIY Part 2 Completed ==="
