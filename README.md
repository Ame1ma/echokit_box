# 添加了 WakeNet 语音唤醒的 echokit_box

构建和刷入方法见脚本文件 ```build_and_flash.sh```
成功运行日志示例见 ```success.log```

主要改动如下：
1. 修改 sdkconfig.defaults 文件，将 ns、vad、wakenet 模型打包用于后续烧录。原始的 echokit_box 其实没有打包模型进去，ns 和 vad 是用的回退的 WebRTC 实现，而要启用 WakeNet，就必须要成功载入模型。主要根据 [esp sr 的 Kconfig 文件中的配置项](https://github.com/espressif/esp-sr/blob/master/Kconfig.projbuild) 和 [CMakeLists.txt](https://github.com/espressif/esp-sr/blob/e901d22082242f38a48d8a90f0eb5be364597c55/CMakeLists.txt#L78)，添加如下项
   - 启用提示词，我启用的是 Hi,Lily/Hi,莉莉 这个提示词
   ```
   CONFIG_SR_WN_WN9_HILILI_TTS=y
   ```
   - 仅仅启用如上配置项，还是不会在编译时打包任何模型，原因在[CMakeLists.txt](https://github.com/espressif/esp-sr/blob/e901d22082242f38a48d8a90f0eb5be364597c55/CMakeLists.txt#L78)对 CONFIG_PARTITION_TABLE_CUSTOM 配置项的判断，需要在编译时指定分区表才会触发。所以额外配置以下项，这里就用根目录下的分区表 partitions.csv，并指定 flash 大小为 16MB
   ```
   CONFIG_PARTITION_TABLE_CUSTOM=y
   CONFIG_ESPTOOLPY_FLASHSIZE_16MB=y
   CONFIG_PARTITION_TABLE_CUSTOM_FILENAME="../../../../../../partitions.csv"
   ```
2. 修正程序的 feed() 实现。[原始的 echokit_box](https://github.com/second-state/echokit_box/blob/95528ca2887fec4f2b12694657261cd6be1f1848/src/audio.rs#L219) 在从 i2s 取到数据后立刻就拿原始数据进行了 feed，这在 WebRTC 实现中没问题，但是在模型中就会无法识别。实际需要需要等到 buffer 积累到 audio_chunksize * sizeof(int16_t) * feed_channel 大小，再将整个 chunk 进行 feed 才会有效。具体修改详见 audio.rs 文件的 feed 循环。
3. 修改配置以启用WakeNet， afe_config.wakenet_init = true;
4. 在使用 espflash 刷入固件的时候，用命令行参数指定使用根目录下的分区表 partitions.csv，我试的在 espflash.toml 中指定并不会使用这个分区表，一定要在命令行参数指定。在刷入过程要观察日志中的 model 分区的起始地址，在下一步刷入模型时需要用到，我的为 0x710000
``` 
espflash flash  --monitor --partition-table ./partitions.csv --flash-size 16mb target\xtensa-esp32s3-espidf\release\echokit
```
5. espflash 并不会在刷入固件时同时刷入模型文件，需要额外手动刷入模型文件 srmodels.bin。这里的 esp-idf-sys-* 不同主机会不一样，以及地址要从上一步日志获取
``` 
espflash write-bin 0x710000 target\xtensa-esp32s3-espidf\release\build\esp-idf-sys-4cc70388b55749ff\out\build\srmodels\srmodels.bin
```
刷入成功的话在启动时会显示 pipeline 如下
``` 
I (9546) AFE_CONFIG: Set Noise Suppression Model: nsnet2
I (9551) AFE_CONFIG: Set VAD Model: vadnet1_medium
I (9556) AFE_CONFIG: Set WakeNet Model: wn9_hilili_tts
MC Quantized vadnet1:vadnet1_mediumv1_Speech_1_0.5_0.1, min speech:128 ms, min noise:480 ms, mode:1, threshold:0.400, channel:1, tigger:v1 (May 16 2025 16:07:42)
MC Quantized wakenet9: wakenet9l_tts1h8_Hi,Lily or Hi,莉莉_3_0.633_0.639, tigger:v4, mode:0, p:0, (May 16 2025 16:07:41)
I (9814) AFE: AFE Pipeline: [input] -> |NS(nsnet2)| -> |VAD(vadnet1_medium)| -> |WakeNet(wn9_hilili_tts,)| -> |AGC(WakeNet)| -> [output]
I (9826) echokit::audio: audio chunksize: 512
wakenet9l_tts1h8_Hi,Lily or Hi,莉莉_3_0.633_0.639 set threshold for 1 word: 0.400000
```
而不是原版的 WebRTC
``` 
AFE: AFE Pipeline: [input] -> |NS(WebRTC)| -> |AGC(WebRTC)| -> |VAD(WebRTC)| -> [output]
```
6. 优化 WakeNet 响应，降低触发阈值。不改阈值触发不是那么灵敏。这个首先要把 esp sr 升级到 2.1.3 以上，这样 afe_handle 就会多一个 set_wakenet_threshold 方法，用来调整阈值，见[官方示例](https://github.com/espressif/esp-skainet/tree/master/examples/wake_word_detection/afe#modify-detection-threshold)。esp sr 升级，最好在第一次构建前修改 Cargo.toml，不然后续再改版本前需要先 cargo clean 才能实际起作用。
``` 
(afe_handle.set_wakenet_threshold.unwrap())(afe_data, 1, 0.4);
```
7. 从 AFEResult 拿到 wakeup_state 对 WakeUp 状态进行获取，后续的更改 Idle 状态为 Listening 的部分详见代码，不在这里列出。
``` rust
let is_wakeup = result.wakeup_state == esp_sr::wakenet_state_t_WAKENET_DETECTED;
if result.wakeup_state != 0 {
    log::info!("!!!!!! wakeup detected, {result:?}");
}
```

# 以下是原始的 README


 
# Setup the EchoKit device

## Buttons on the device

The `RST` button is to restart the system. On the EchoKit devkit, it is labeled as `rst` on the main ESP32 board.

The `K0` button is the main action button for the application. On the EchoKit devkit, it is the single button to the left of the LCD screen on the extension board.

> The `boot` button on the ESP32 board is the SAME as the `K0` button.

## Quick start

Flash the `echokit.bin` device image using the web-based [ESP Launchpad](https://espressif.github.io/esp-launchpad/?flashConfigURL=https://echokit.dev/firmware/echokit.toml) tool.

## Install espflash

Assume that you [installed the Rust compiler](https://www.rust-lang.org/tools/install) on your computer.

```
cargo install cargo-espflash espflash ldproxy
```

## Build the firmware

Get a pre-compiled binary version of the firmware. The firmware binary file is `echokit`.

```
curl -L -o echokit https://echokit.dev/firmware/echokit-boards
```

To build the `echokit` firmware file from source, you need to make sure that you install the [OS-specific dependencies](https://docs.espressif.com/projects/rust/book/installation/std-requirements.html) and then [ESP toolchain for Rust](https://docs.espressif.com/projects/rust/book/installation/riscv-and-xtensa.html). You can then build from the source and find the binary firmware in `target/xtensa-esp32s3-espidf/release/`.

```
cargo build --release
```

Optional: Build the device image.

```
espflash save-image --chip esp32s3 --merge --flash-size 16mb target/xtensa-esp32s3-espidf/release/echokit echokit.bin
```

<details>
<summary> Alternative firmware </summary>

If you have the fully integrared box device, you can use the following command to download a pre-built binary.

```
curl -L -o echokit https://echokit.dev/firmware/echokit-box
```

To build it from the Rust source code. 

```
cargo build  --no-default-features --features box
```

</details>

## Flash the firmware

Connect to your computer to the EchoKit device USB port labeled `TTL`. Allow the computer to accept connection from the device when prompted. 

> On many devices, there are two USB ports, but only the `SLAVE` port can take commands from another computer. You must connect to that `SLAVE` USB port. The detected USB serial port should be `JTAG`. IT CANNOT be `USB Single`.

```
espflash flash --monitor --flash-size 16mb echokit
```

The response is as follows.

```
[2025-04-28T16:51:43Z INFO ] Detected 2 serial ports
[2025-04-28T16:51:43Z INFO ] Ports which match a known common dev board are highlighted
[2025-04-28T16:51:43Z INFO ] Please select a port
✔ Remember this serial port for future use? · no
[2025-04-28T16:52:00Z INFO ] Serial port: '/dev/cu.usbmodem2101'
[2025-04-28T16:52:00Z INFO ] Connecting...
[2025-04-28T16:52:00Z INFO ] Using flash stub
Chip type:         esp32s3 (revision v0.2)
Crystal frequency: 40 MHz
Flash size:        8MB
Features:          WiFi, BLE
... ...
I (705) boot: Loaded app from partition at offset 0x10000
I (705) boot: Disabling RNG early entropy source...
I (716) cpu_start: Multicore app
```

> If you have problem with flashing, try press down the `RST` button and, at the same time, press and release the `boot` (or `K0`) button. The device should enter into a special mode and be ready for flashing. 

## Reset the device

Reset the device (simulate the RST button or power up).

```
espflash reset
```

Delete the existing firmware if needed.

```
espflash erase-flash
```

## Next steps

You will need to configure and start up an [EchoKit server](https://github.com/second-state/echokit_server), and then configure your device to connect to the server in order for the EchoKit device to be fully functional.



