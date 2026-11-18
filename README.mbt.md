# MoonTIN

MoonTIN 检查 LandXML 1.2 地形曲面的测点引用、投影退化和三角面拓扑。

```sh
moon run cmd/main -- check examples/terrain.xml
moon run cmd/main -- check examples/missing-point.xml --format json
moon test --target native
pwsh -NoProfile -File scripts/test-cli.ps1
```

正常样本返回 `0`。悬空引用样本返回 `1`，并报告 `Existing Ground` 曲面的第 `1` 个面引用了不存在的 `99` 号点。输入、参数或文件读取错误返回 `2`。

当前原型支持内联 TIN 点和三角面。CLI 会记录无效点和三角面，并继续验收其余记录。JSON 含曲面边界边数、连通片数及坐标范围。文件验收诊断带打开标签的行号和列号，文本模式输出为 `文件:行:列`，JSON 使用 `location` 对象。行列从 1 开始。使用 `--area-tolerance N` 设置投影面积阈值，单位为文件坐标单位的平方。完整支持矩阵和后续工作见 `DESIGN.md` 与 `TODO.md`。


## 验收选项

- `--strict` 把验收警告视为失败。当前警告包括缺少线性单位和文件中跳过的非 TIN 曲面。
- `--max-diagnostics N` 同时限制记录问题和几何拓扑诊断的输出条数，默认 1000。设为 0 时只保留统计。JSON 中的 `error_count` 和 `warning_count` 是完整计数，`truncated` 表示有详情未输出。
- `--max-input-bytes N` 限制文件大小，默认 16 MiB。CLI 在读取文件内容前检查实际字节数，并以严格 UTF-8 解码。
- `--max-records N` 限制 LandXML 1.2 命名空间中的点与面元素总数，默认 500,000。字节或记录超限时退出 `2`，详情写入 stderr。

### 本地性能基线

Windows 原生 Release 构建处理 160 × 160 合成网格。输入大小为 1,895,456 字节，含 25,600 个点、50,562 个面。一次本地运行含进程启动约 614 ms，运行期间采样到的峰值工作集约 63 MiB。结果为 636 条边界边、1 个连通片。

## 比较两版地形

```sh
moon run cmd/main -- diff examples/terrain.xml examples/terrain-revised.xml --format json
```

`diff` 按曲面名和测点 ID 比较两版 TIN 文件，报告新增、删除和移动的测点，以及三角面的增删、方向和可见性变化。两份文件的线性单位声明必须相同。测点 ID 重新编号会表现为删除和新增。

`--coordinate-tolerance N` 为每个坐标轴设置比较容差，默认 0。`--max-details N` 限制每个曲面的明细条数，默认 1,000。退出码 `0` 表示无变化，`1` 表示有变化，`2` 表示读取、解析或比较失败。

## 抽查坐标高程

```sh
moon run cmd/main -- sample examples/terrain.xml 100.25 200.25 --format json
```

按 Northing、Easting 输入坐标，返回所有覆盖该点的可见三角面与线性插值高程。坐标和结果沿用文件单位。共享边或重叠曲面可返回多条结果，使用 `--surface NAME` 限定曲面。退出码 `0` 表示有命中，`1` 表示坐标没有可见面覆盖，`2` 表示输入错误。
