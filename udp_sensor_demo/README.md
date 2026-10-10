# udp_loop_demo — BME280 環境センサ UDP 送信 (micro T-Kernel + lwIP)

JASA-1 (SWC1, RV32I) 上の micro T-Kernel 3 で lwIP + ENC424J600 (PmodNIC100) を動かし、
BME280 の温度・湿度・気圧を 1 秒ごとに UDP で PC に送信するデモ。
受信側は `pc/sensor_monitor.py` (説明は `pc/README.md`)。

ベアメタル版 (`../pmodnic_test`) のセンサドライバを micro T-Kernel のタスク上に移植したもの。

## 準備: micro T-Kernel と lwIP

このディレクトリには micro T-Kernel 本体と lwIP 本体は含まれていない。ビルド前に次の名前で置く
(元の udp_loop_demo では git submodule)。

```sh
git clone https://github.com/risc-v-wg/mtkernel_3_for_swc1 mtkernel_3_for_swc1
git -C mtkernel_3_for_swc1 checkout f1bbb096df7356f291b53c3aef48c8ac14c8daa6
git clone https://github.com/lwip-tcpip/lwip lwip
git -C lwip checkout 3d896ba0a37ff3ce73270ca5e230707fe47f60e3   # STABLE-2_2_1_RELEASE-34
```

上のコミットは udp_loop_demo の submodule が指しているもの (ローカル変更なし)。

既存のチェックアウトを使うならシンボリックリンクでもよい。別の場所に置く場合は
`make -f Makefile.swc1_ether LWIPDIR=/path/to/lwip/src` のように指定する (micro T-Kernel の場所は `SRCDIR` だが Makefile で固定)。
リンカスクリプト (`mtkernel_3_for_swc1/etc/linker/iote_swc1/tkernel_map*.ld`) も micro T-Kernel 側にある。
2026-10-10 時点で udp_loop_demo 内の submodule を使ってビルドし、元と同じイメージになることを確認した。

## 構成

| パス | 内容 |
|---|---|
| `mtkernel_3_for_swc1/` | micro T-Kernel 3 (submodule) |
| `lwip/` | lwIP (submodule) |
| `ether_task/` | ether_task 本体、ウォッチドッグ (`ether_wdt.c`)、usermain、printf / libc シム、lwipopts.h |
| `lwip_port/drivers/` | SWC1 SPI / FRC タイマ、ENC424J600 ドライバ |
| `lwip_port/netif/` | lwIP netif グルー |
| `lwip_port/app/sensor_send.c` | センサ値を読んで UDP 送信 |
| `sensor/` | BME280 ドライバ (pmodnic_test/sensor から移植) |
| `pc/` | PC 側の受信プログラム (`sensor_monitor.py`、`sensor_sim.py`、`static/index.html`) |
| `zero` | `.2.hex` 作成用のゼロ埋めデータ (Makefile の hex ターゲットが使う) |
| `a.sh` | elf からダンプ / hex を作る補助スクリプト |

`ether_task` (優先度 8) が lwIP のポーリングループを回し、その中で `sensor_send_poll()` を呼ぶ。
BME280 の読み出しと ENC424J600 の SPI はどちらも ether_task からだけ呼ばれる。
`ether_wdt_task` (優先度 7) が ether_task を監視する (後述の「ウォッチドッグ」)。

## 動作状況 (2026-10-10)

| 項目 | 状態 |
|---|---|
| BME280 の値を UDP 送信 (RAM 実行版) | 実機で動作確認済み |
| ウォッチドッグによる ether_task 再起動 (検知 10 秒) | 実機で動作確認済み |
| 40 秒ごとのわざとハング + GPIO[3] LED 点滅 | 実機で動作確認済み |
| `LWIP_TCP 0` で本来のハングが減るか | 確認中 (わざとのハングを `ETHER_HANG_INTERVAL_MS=0` で止めて長時間動かす必要あり) |
| Flash XIP 版 | ビルドのみ |
| git | 未コミット |

現在の設定:

| 設定 | 値 | 場所 |
|---|---|---|
| ハング検知時間 `ETHER_WDT_TIMEOUT_MS` | 10000 ms | `ether_task/ether_wdt.c` |
| わざとハングする間隔 `ETHER_HANG_INTERVAL_MS` | 40000 ms (メインループ開始から) | `ether_task/ether_task.c` |
| 送信周期 / LED 反転周期 | 1000 ms (1 秒点灯 / 1 秒消灯) | `lwip_port/app/sensor_send.c` |
| `LWIP_TCP` | 0 | `ether_task/lwipopts.h` |
| PC 側の表示タイムアウト `--stale` | 5 秒 (`pmodnic_test/pcdemo`) | `sensor_monitor.py` |

1 周期は「40 秒動作 → ハング → 10 秒後に再起動 → 初期化約 1 秒」で約 51 秒。
ハング中は PC 側の表示タイムアウト (5 秒) を超えるので、モニタの室内の値は stale 表示になる。

設定の変遷: ハング検知 3 → 6 → 12 → 10 秒、ハング間隔 2 分 → 1 分 → 40 秒。
LED は rgb_led[1] → GPIO[3] に移し、点滅はメインループ内 → 周期ハンドラ → UDP 送信周期ごとの反転、と変えた (経緯は「デモ」の節)。

## ハードウェア接続

| 信号 | JASA-1 | 備考 |
|---|---|---|
| ENC424J600 CS | GPIO[0] | `swc1_spi.c` が使用 |
| BME280 SCL | GPIO[1] | ビットバング I2C (オープンドレイン動作) |
| BME280 SDA | GPIO[2] | 同上 |
| 動作確認 LED | GPIO[3] | Arty H4。High で点灯。外付け LED を接続する (元のドライバでは GPIO_DUMMY として LOW 出力していた) |

BME280 の I2C アドレスは 0x76。ボードの IP は 192.168.0.221/24 固定 (`ether_task.c`)。

## ビルド

```sh
make -f Makefile.swc1_ether           # RAM 実行版 → mtkernel_swc1_ether.{elf,hex,2.hex,bhex}
make -f Makefile.swc1_ether_flash     # Flash XIP 版 → mtkernel_swc1_ether_flash.*
```

ソースは共通で、`Makefile.swc1_ether_flash` は `Makefile.swc1_ether` を include してメモリ配置だけ変えている。

### ビルドオプション

| 変数 | 既定値 | 内容 |
|---|---|---|
| `SENSOR_DEST_IP` | 192.168.0.255 | 送信先 (既定はサブネットブロードキャスト) |
| `SENSOR_DEST_PORT` | 5005 | 送信先ポート |
| `SENSOR_FORMAT` | 0 | 0=JSON, 1=key=value, 2=CSV, 3=binary (`sensor_sim.py --format` と同じ) |
| `EXTRA_DEFS=-DI2C_DELAY_US=<us>` | 1000 | I2C のエッジ間ウェイト (SCL 半周期)。1000 で動作確認済み |
| `EXTRA_DEFS=-DSENSOR_TRACE` | 無効 | 診断ログを有効にする (後述) |
| `EXTRA_DEFS=-DETHER_WDT_TIMEOUT_MS=<ms>` | 10000 | ウォッチドッグのタイムアウト |
| `EXTRA_DEFS=-DETHER_HANG_INTERVAL_MS=<ms>` | 40000 | デモ用: ether_task が (再)起動からこの時間後にわざとハングする。0 で無効 |

例: `make -f Makefile.swc1_ether SENSOR_DEST_IP=192.168.0.18 SENSOR_FORMAT=3`

`EXTRA_DEFS` などのフラグを変えただけでは make はオブジェクトを再ビルドしない。
フラグを変えたら `make -f Makefile.swc1_ether clean` (または該当する `build_*/` を削除) してからビルドすること。

## 送信データ

1 データグラムに 1 測定。単位は温度 0.01 ℃、湿度 0.01 %RH、気圧 Pa の固定小数点整数で持ち、
浮動小数点は使わない。JSON の例:

```text
{"temp": 24.83, "hum": 52.10, "press": 1008.42}
```

BME280 は normal モード (オーバーサンプリング各 x1、スタンバイ 1000 ms) で動かし、
送信周期ごとに 0xF7〜0xFE をバースト読み出しして補正計算する。
読み出しに失敗した周期は送信しない。初期化に失敗した場合は次の周期で再初期化を試みる。

## UART ログ

正常時:

```text
--- Initialise driver
setup BME280 sensor
bme280_setup: start
bme280_setup: done
bme280_get_calib_data: start
bme280_get_calib_data: end                     ← I2C 1ms ウェイトなので約 1 秒かかる
sensor_send: sending to 192.168.0.255:5005 every 1000 ms
hwaddr=...
ether_task: lwIP up, static IP 192.168.0.221/24, polling...
ether_task: link UP
sensor_send: #1 {"temp": 24.83, "hum": 52.10, "press": 1008.42}
```

`[send] N` / `[recv] N` は usermain の sender / receiver タスクの出力。

BME280 が応答しないとき (配線・アドレス違い):

```text
bme280_setup: failed (no ACK from 0x76?)
sensor_send_init: BME280 init FAILED -- check I2C wiring (GPIO1=SCL, GPIO2=SDA)
sensor_send: BME280 init FAILED, retrying next interval     ← 以後 1 秒ごと
```

`-DSENSOR_TRACE` を付けると、GPIO レジスタ値、`swc1_delay_us(1000)` の実測サイクル数
(正常なら約 50000)、各レジスタ書き込みと I2C の ACK/NACK が表示される。

## ウォッチドッグ (ether_task の自動再起動)

`ether_task` はループごと (約 50 ms + センサ読み出し) と初期化の各段階で `ether_task_heartbeat` を増やす。
`ether_wdt_task` (`ether_task/ether_wdt.c`) は 100 ms ごとにこれを確認し、10 秒間変化がなければ
`tk_ter_tsk()` で ether_task を強制終了し、`tk_sta_tsk()` でエントリから再起動する
(stacd に再起動回数を渡す)。ether_task が自分で終了していた場合 (netif_add 失敗など) も同様に再起動する。
ether_task より優先度が高いので、ether_task がビジーループで止まっていても動ける。

再起動時 (stacd != 0) の ether_task の処理:

- `lwip_init()` はヒープとメモリプールを初期化するが、それを指すリストは初期化しない。
  そこで先に ARP テーブル (`etharp_cleanup_netif`)、`netif_list` / `netif_default`、`udp_pcbs`、
  タイマリスト (`sys_timeouts_get_next_timeout()`、このために `lwipopts.h` で `LWIP_TESTMODE` を有効化) をクリアする。
  TCP はアプリで使っていないので対象外。
- ENC424J600 は `netif_add()` → `enc424j600_init()` でチップをリセットして初期化し直す。
- BME280 は `sensor_send_init()` で初期化し直す。`i2c_init()` は、I2C 読み出し中に殺されて
  BME280 が SDA を Low に保持していても解放されるよう、SCL を最大 9 パルス出してから STOP を送る。

再起動時の UART ログ:

```text
ether_wdt: no heartbeat for 10000 ms -- restarting ether_task (#1)
ether_task: restarted by watchdog (#1), resetting lwIP
--- Initialise driver
...
sensor_send: #1 {...}
```

カーネル自体が止まる種類のハング (割り込み禁止のまま止まる、タイマキューが壊れる) は、
ウォッチドッグタスクも動けなくなるので回復できない。その場合は `[send]` / `[recv]` も止まる。

### デモ: 40 秒ごとのハングと動作確認 LED

ウォッチドッグを見せるため、ether_task はメインループ開始から `ETHER_HANG_INTERVAL_MS` (既定 40 秒) 後に
わざとビジーループで止まる。再起動後も同じなので、約 40 秒ごとにハングと復帰を繰り返す。
本番で使うときは `EXTRA_DEFS=-DETHER_HANG_INTERVAL_MS=0` でビルドする。

GPIO[3] の LED は `sensor_send_poll()` が送信周期 (1 秒) を迎えるたびに反転する (1 秒点灯 / 1 秒消灯)。
ハングすると送信と一緒に止まり、点灯または消灯のままになる。
送信周期はサイクルカウンタで管理しているので、ループ時間がばらついても間隔はずれない。

```text
ether_task: deliberate hang (ETHER_HANG_INTERVAL_MS=40000)     ← LED の点滅が止まる
ether_wdt: no heartbeat for 10000 ms -- restarting ether_task (#1)
ether_task: restarted by watchdog (#1), resetting lwIP
...                                                              ← 点滅再開
```

GPIO を操作するのは CS (GPIO[0])、I2C (GPIO[1..2])、LED (GPIO[3]) とも ether_task だけなので、
read-modify-write が競合することはない。

経緯:

- メインループ内で 500 ms ごとに反転 → ループ時間のばらつきで間隔が不規則になった。
- カーネルの周期ハンドラ (`tk_cre_cyc`、500 ms、ハートビートが進んでいるときだけ反転) → 間隔は正確になったが、
  UDP 送信のタイミングで反転する方式に変更した (現在の方式)。
- その前はボードの rgb_led[1] を使っていた。しかし `fpga_top.v` では
  `rgb_led = spi_select_io ? {spi_mosi, spi_csn[0], spi_sck} : LED レジスタ` となっていて、SPI のピン出力中は
  rgb_led[1] に SPI ブロックの CS が出る。ENC424J600 と通信していない間だけ SPI のピン出力を切る工夫もしたが、
  ENC へのアクセスのたびに細かくちらつくのは避けられなかった。そこで GPIO[3] に移し、SPI ドライバは元の動作に戻した。

## 既知の課題

- **まれに ether_task だけがハングする**: 原因は未特定。ウォッチドッグは対症療法。
  `[send]` / `[recv]` が出続けているので、カーネルではなく ether_task 内で止まっていると考えられる。
- **`LWIP_TCP`**: `ether_task.c` 冒頭のコメントには「TCP を有効にしたらカーネルのタイマキューが壊れたので無効にした」とあるのに、
  `lwipopts.h` は `LWIP_TCP 1` になっていた。ハングの原因候補なので `0` にした (2026-10-10)。text は 199,845 → 157,561 バイト。
  これでハングが出なくなるかは、わざとのハングを止めて (`EXTRA_DEFS=-DETHER_HANG_INTERVAL_MS=0`) しばらく動かして確認する。
- **ウォッチドッグで回復できないケース**: カーネルごと止まる場合、およびメインループは回っているのに送信が失敗し続ける場合
  (ハートビートはメインループで進むので検出されない。UART に `udp_sendto() FAILED` などが出続ける)。

## pmodnic_test からの移植で変えた点

- **タイマ**: `timer.c` (`frc_start()` / `wait_ms()`) は使わない。FRC は micro T-Kernel がシステムティックに使っており、
  `FRC_CNTRL` に書くと保留中のティック割り込みがクリアされるため。I2C のウェイトは
  FRC を読むだけの `swc1_delay_us()` を使う。
- **GPIO 共有**: `swc1_spi.c` の CS 操作を GPIO レジスタ全体の書き込みから GPIO[0] だけの read-modify-write に変更
  (pmodnic_test の `jasa1_spi.c` と同じ)。以前は CS を切り替えるたびに I2C の GPIO[1..3] を上書きしていた。
- **GPIO[3]**: 元のドライバの `GPIO_DUMMY` (LOW 出力) をやめ、動作確認 LED (`GPIO_LED`) にした。
- **レジスタ定義**: `reg_rw.h` の代わりに `lwip_port/drivers/swc1_io.h` を使う。
- **`bme280_setup()`**: 書き込みの成否を返すようにし、失敗時に再試行できるようにした。
- **`dig_h4` / `dig_h6`**: Bosch のリファレンスどおり符号拡張する (元は符号なし扱い)。
- **気圧補正**: 64 ビット版から Bosch の 32 ビット整数版 (データシート 8.2) に変更 (次節)。
- **ログ**: 毎回の start / done 表示は削除し、エラーのみ表示。`ether_printf.c` は `%ld` 非対応なので `%d` を使う。
- `sensor.c` は `sensor_init()` (bool を返す) と `sensor_read(&temp, &hum, &press)` にまとめ、
  湿度を 1/1024 %RH から 0.01 %RH に換算する。

## 元のリポジトリからの変更ファイル

| ファイル | 変更内容 |
|---|---|
| `sensor/` (新規) | BME280 ドライバ: `gpio_ctrl`、`i2c_ctrl`、`bme280_ctrl`、`sensor` |
| `ether_task/ether_wdt.c`、`ether_task/ether_task.h` (新規) | ウォッチドッグタスク、ハートビート |
| `ether_task/ether_task.c` | UDP エコーからセンサ送信に変更、ハートビート、再起動時の lwIP リセット、40 秒ごとのわざとハング |
| `ether_task/usermain_ether.c` | ウォッチドッグタスクの生成 |
| `ether_task/lwipopts.h` | `LWIP_TESTMODE 1`、`LWIP_TCP 0` |
| `lwip_port/app/sensor_send.c/.h` (新規) | センサ値の UDP 送信 (ダミー値から BME280 に変更)、送信周期ごとの LED 反転 |
| `lwip_port/drivers/swc1_spi.c` | CS を GPIO[0] だけの read-modify-write に |
| `lwip_port/drivers/swc1_time.c` | `swc1_delay_us()` を 32 ビット演算に |
| `Makefile.swc1_ether` | `sensor/`、`ether_wdt.c`、`SENSOR_*` 変数を追加 |

## ハマりどころ: 64 ビット乗除算が正しく動かない

ツールチェーン `/opt/riscv32im.newlib` の libgcc は rv32im 版しかない (`gcc -print-multi-lib` が `.;` のみ)。
`-march=rv32i` でコンパイルしても、64 ビット乗除算は libgcc の `__muldi3` / `__udivdi3` / `__divdi3` が
リンクされ、その中には `mul` / `divu` 命令が入っている。RV32I コアではこれが例外にならず誤った値を返す。

実際に起きた症状: `swc1_delay_us()` が 64 ビット演算でサイクル数を計算していたため、
`swc1_delay_us(1000)` が 50,000 サイクルのはずが 195,354,016 サイクル (約 3.9 秒) かかり、
I2C 通信が極端に遅くなって `bme280_setup: start` の後に止まったように見えた
(他のタスクの `[send]` / `[recv]` は出続ける)。

対策:

- `swc1_delay_us()` を 32 ビット演算 (`us * (SWC1_CLK_HZ / 1000000)`) に変更。ENC424J600 ドライバの待ち時間もこれで正しい長さになった。
- BME280 の気圧補正を 32 ビット版に変更。

32 ビットの乗除算 (`__mulsi3` / `__udivsi3` など) はソフトウェア実装なので問題ない。
コードを変更したら、64 ビットのヘルパーが呼ばれていないことを確認するとよい:

```sh
riscv32-unknown-elf-objdump -d mtkernel_swc1_ether.elf \
  | awk '/^[0-9a-f]+ <.*>:$/{fn=$2} /<__(muldi3|udivdi3|divdi3|umoddi3|moddi3)>/ && /jal/{print fn}' | sort -u
```

何も表示されなければよい。

## 補足: pmodnic_test の気圧計算のバグ

データシートの例題 (期待値 100653 Pa) で PC 上で比較した結果:

| 実装 | 結果 |
|---|---|
| Bosch リファレンス (64 ビット) | 100653 Pa |
| 本デモの 32 ビット版 | 100656 Pa |
| pmodnic_test の元コード | 98605 Pa |

元コードは `dig_p9 * p / 8192 * p` の途中で int64 がオーバーフローし、約 20 hPa 低く出る。
Bosch のリファレンスは `(p >> 13) * (p >> 13)` の順で計算している。pmodnic_test 側は未修正。

## PC 側で受信できないとき

PC 側の `sensor_monitor.py` を WSL2 (NAT モード) で動かすと、LAN へのブロードキャストは Windows には届いても WSL には届かない。
WSL を mirrored ネットワークモードにして `SENSOR_DEST_IP` に PC の IP を指定するか、Windows 上で `sensor_monitor.py` を動かす。
PC のファイアウォールで UDP 5005 を許可すること。

室内の値を stale (古い値) 表示にするまでの時間は `sensor_monitor.py --stale` で決まる。
`pmodnic_test/pcdemo` 版は既定を 10 → 5 秒に変更済み。`demo/sensor_monitor.py` と `udp_sensor_demo/pc/` はまだ 10 秒。
