# 复验

环境：Python 3.10+ 标准库、Godot **4.6.1 stable / 14d19694e**。图形测试需要真实渲染器；本次为 Windows、OpenGL Compatibility、RTX 4060。无需原游戏、godot_devtool 或 Python 图像库。

在仓库根目录运行，`--output` 每次选择一个尚不存在的目录：

```powershell
$env:GODOT_BIN='H:\godot4.61\Godot_v4.6.1-stable_win64_console.exe'
python -X utf8 tests/run.py --suite unit --output H:/NEW-MAP-TOOL_checks/unit
python -X utf8 tests/run.py --suite ui --output H:/NEW-MAP-TOOL_checks/ui
python -X utf8 tests/run.py --suite pixels --output H:/NEW-MAP-TOOL_checks/pixels
python -X utf8 tests/run.py --suite background --output H:/NEW-MAP-TOOL_checks/background
python -X utf8 tests/run.py --suite editor --output H:/NEW-MAP-TOOL_checks/editor
python -X utf8 tests/run.py --suite profile --output H:/NEW-MAP-TOOL_checks/profile
python -X utf8 tests/run.py --suite soak --output H:/NEW-MAP-TOOL_checks/soak
python -X utf8 tests/run.py --suite art --output H:/NEW-MAP-TOOL_checks/art
python -X utf8 tests/verify_sources.py --output H:/NEW-MAP-TOOL_checks/integrity.json
```

图形测试按顺序运行；性能采样期间避免另开图形测试。每个测试使用临时项目副本及独立用户目录。`RESULT.json` 记录退出码、日志、实际副本 SHA256 和副本完整性；原工作目录的同期变化单独记录。Windows 超时会结束本次测试的子进程树，不重置或写入用户游戏项目。

| 套件 | 内容 | 范围限制 |
| --- | --- | --- |
| unit | 19个脚本，含53条本轮针对性检查；事务、路径、区域、地形、模板回归 | 命令层检查，不等于51项完整验收 |
| ui | 原入口；四个样板控件编辑、撤销、保存重开、导出、独立预览；5000对象台地／密度控件 | 自动化原生输入回放，未提供人工验收录像 |
| pixels | 冻结、分页与连续层序重组、只读重绘、取消、写入失败、损坏包 | 预设最大通道差2，超过1的通道占比≤0.0001 |
| background | 最小化窗口导出、小数比例清单 | 独立渲染边界回归 |
| profile | 原UI-Core 5000／120画布拖动、候选阶段、可见反馈、撤销重做 | 事件耗时和整帧分开，不混充完整UI响应时间 |
| soak | 300秒：路径点、后台密度／台地、撤销重做、保存、切换、导出 | 与原纯平移／名称编辑的历史口径不同 |
| art | 固定镜头空地、建设、缺口、地形独显及近景 | 缺口是几何示意，画风认可待确认 |

`fixtures/core.shwork.json.gz` 保留原冻结5000／120夹具，约80KB；`editing_core.shwork.json.gz` 为编辑变体，加入路径、零密度林区、空台地，初始同为5000对象／120配方。运行器解压到临时目录，复用样板PNG；输入hash及文件hash分别记录。

## 旧版反例

```powershell
python -X utf8 tests/run.py --baseline c7e0a4b --script tests/review_c7e0/test_original_counterexamples.gd --output H:/NEW-MAP-TOOL_checks/red
python -X utf8 tests/run.py --script tests/review_c7e0/test_original_counterexamples.gd --output H:/NEW-MAP-TOOL_checks/green
```

基线预期退出1、4项失败；修复版预期退出0。`--baseline` 只在临时副本替换该提交的addons，不切换工作目录。脚本来自审查草案，修正了内置类型 `Projection` 的命名冲突；实际结果另存。

可另用 `--baseline c7e0a4b --suite profile` 复跑旧画布拖动；20次旧版事件可能耗时约3分钟，套件超时为240秒。该命令与反例的“预期失败”含义不同。

`review_c7e0/build_art_candidate.gd` 可在独立输出目录重建新关口。配方和素材固定，创建时项目ID随机；发布JSON有独立SHA256。生成图片已固定，无需重新调用图像工具。

原始日志、轨迹、截图、导出文件在本机证据包，摘要见 `docs/review_c7e0/RESULTS.json`。未覆盖的矩阵条件及人工审核不据此自动通过。
