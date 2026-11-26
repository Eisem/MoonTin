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

在单曲面样本中加入 90,000 个无关 `CgPoint` 元素后，文件大小约 3.77 MB。Windows Release 交替运行五次，优化前后 JSON 报告逐字节一致。中位耗时由 509 ms 降至 465 ms，采样峰值工作集由 78.1 MiB 降至 33.9 MiB。上述数据适用于该合成输入和本地环境。

同一 160 × 160 合成网格用于对比连通片统计。Windows Release 交替运行五次，改用并查集后 JSON 报告逐字节一致，中位耗时由 575 ms 降至 542 ms，五次采样中的最大峰值工作集由 72.2 MiB 降至 65.1 MiB。

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

## 提取直线高程剖面

```sh
moon run cmd/main -- profile examples/terrain.xml 100.25 199.75 100.25 201.25 --format json
```

命令接收起终点的 Northing、Easting 坐标，按沿线距离输出每个可见三角面内的线性高程区间，以及未覆盖区间。重叠或共享边上的多个三角面分别保留。`--surface NAME` 限定曲面。退出码 `0` 表示存在覆盖区段，`1` 表示整条线无覆盖，`2` 表示输入错误。

曲面 JSON 摘要中的 `geometry` 汇总通过几何检查的唯一可见面，包含投影面积、三维面积和最小、最大坡度百分比。面积沿用文件线性单位的平方，重叠三角面各自计入。若计算超出浮点范围，受影响的面积汇总为 `null`，`overflow_faces` 记录局部溢出的面数。

## 导出 TIN 网格

```sh
moon run cmd/main -- export examples/terrain.xml --format ply --local-origin > terrain.ply
```

支持 OBJ 和 ASCII PLY，坐标轴依次为 Easting、Northing、Elevation。导出保留可见面的顶点顺序，以曲面为单位重用同一测点。OBJ 分组和 PLY 面属性记录曲面序号，PLY 还保留面序号。`--local-origin` 减去首个可见面首点的坐标，并在文件注释记录原点。

## 批量验收测点高程

```sh
moon run cmd/main -- survey examples/terrain.xml examples/survey-points.json 0.1 --format json
```

测点文件是 JSON 数组，每项包含字符串 `id` 和数值 `northing`、`easting`、`elevation`。容差沿用地形线性单位。若多个可见面覆盖同一测点，所有插值高程都须落在容差内。报告按输入顺序记录每个点的覆盖数、插值范围和偏差最大的面。退出码 `0` 表示全部通过，`1` 表示存在超差或无覆盖测点，`2` 表示输入错误。

## 提取等高线

```sh
moon run cmd/main -- contour examples/terrain.xml 10.5 --level 11.5 --format json
```

每条线沿相邻可见三角面的共享边拼接。分叉点处会拆成独立路径。整面高程与等高线重合时计入 `skipped_flat_faces`，单点接触不会形成路径。退出码 `1` 表示没有线段，`2` 表示输入或计算错误。

## 计算相对基准面的挖填方量

```sh
moon run cmd/main -- volume examples/terrain.xml 11 --format json
```

默认使用指定高程的水平面。`--anchor NORTH EAST` 设置锚点，`--grade NORTH EAST` 设置两个方向的单位坡降系数，即每单位水平距离对应的高程变化。工具切分跨过基准面的可见三角面，对上下两侧分别积分，报告挖方、填方、净挖方和投影面积。方量为文件线性单位的立方。重叠曲面分别计量。

## 回写 LandXML TIN

```sh
moon run cmd/main -- rewrite examples/terrain.xml --timestamp 2026-11-21 09:00:00 --project Road > normalized.xml
```

回写结果包含 MoonTIN 支持的 TIN 曲面、点、面和线性单位。默认保留测点 ID、三角面方向及可见性。`--visible-only` 移除隐藏面及其独用测点，`--renumber-points` 将每个曲面的测点重新编号为连续整数。`--timestamp DATE TIME` 和 `--project NAME` 可为交付文件补充元数据。回写的范围限于 TIN 数据，原文件的坐标参考系统、断裂线、路线及其他扩展元数据不会进入输出。往返测试验证 MoonTIN 可重读输出。

调用方需要连续查询多个坐标时，可以先调用 `build_elevation_index` 建立可见面空间索引，再复用 `ElevationIndex::sample`。查询会跳过包围盒不包含该点的子树，返回与直接扫描相同的命中顺序。

## 采样规则高程网格

```sh
moon run cmd/main -- grid examples/terrain.xml 100 200 2 2 0.75 0.75 --format json
```

参数依次为 Northing 起点、Easting 起点、行数、列数和两个方向的正间距。输出按行排列，行列序号从 0 开始，单次最多采样 100,000 个节点。无覆盖节点的高程为 `null`。多面命中的节点保留命中数和高程范围，便于识别重叠曲面或共享边。退出码 `0` 表示至少一个节点有覆盖，`1` 表示全部无覆盖，`2` 表示输入错误。

### 重复高程查询基准

```sh
moon bench --target native --release --package eisem/moontin --file elevation_index_bench_wbtest.mbt
```

在 Windows 原生 Release 构建下，用包含 19,602 个三角面的 100 × 100 合成地形测量。建立索引平均约 24.02 ms。对同一批 100 个坐标，逐点调用直接扫描接口平均约 333.43 ms，复用已建索引平均约 0.064 ms。直接扫描会在每次调用时重新建立点 ID 表，复用索引的查询时间单列，未计入建索引时间。结果取决于查询分布与包围盒重叠程度。

重复提取同一地形上的多条剖面时，可复用 `ElevationIndex::profile`。它先筛选与测线外接矩形相交的三角面，再按原有算法计算高程区段与缺口。

## 比较两版地形的网格高差

```sh
moon run cmd/main -- grid-diff examples/terrain.xml examples/terrain-revised.xml 100 200 2 2 0.75 0.75 0.1 --format json
```

两个文件使用相同的网格和线性单位。末尾的数值是高差容差，高差按新版减旧版计算。有多个面命中时，报告所有新旧高程组合的高差范围。如果整个范围都在容差之上或之下，就记为升高或降低。范围完全落入容差内时记为通过，其余交叠情况记为待复核。覆盖新增和丢失单独统计。退出码 `0` 表示没有待复核节点，`1` 表示存在超差、覆盖变化或重叠歧义，`2` 表示输入错误。

文本摘要逐点累计结果，详细 JSON 也不需要先保存两张完整高程网格。在两份随附样例上比较 250 × 400 节点，本地 Windows Release 预热后交替测量五次，文本摘要中位耗时由 132 ms 降至 112 ms，五次运行中采样到的最大峰值工作集由 47.9 MiB 降至 8.9 MiB。文本摘要逐字节一致，另一个 2 × 2 样例的详细 JSON 也逐字节一致。

### 流式输出网格高差明细

```sh
moon run cmd/main -- grid-diff examples/terrain.xml examples/terrain-revised.xml 100 200 2 2 0.75 0.75 0.1 --format jsonl
```

JSONL 第一行是 `header`，包含网格参数、单位和容差。随后按行优先顺序输出 `cell` 记录，每条内嵌与普通 JSON 相同的节点对象。最后一条 `summary` 包含完整计数和 `needs_review`。退出码沿用普通格式。消费者应同时检查退出码和末尾的 `summary`，计算中途报错时可能只收到已写出的部分记录。

对两份随附样例计算 250 × 400 个节点，在本地 Windows Release 中预热后交替测量五次，完整 JSON 与 JSONL 的采样峰值工作集分别为 384.0 MiB 和 9.3 MiB，中位耗时分别为 1.83 秒和 2.03 秒。测试将输出重定向到本地文件。
