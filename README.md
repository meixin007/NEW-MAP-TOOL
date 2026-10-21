# NEW MAP TOOL · 山河工坊

Godot 4.6.1 地图制作插件，包含 W6—W7 核心版候选和三个最终可编辑样板。

本分支按固定版本 `c7e0a4b` 的审查报告修复，仍为审核 C 候选。技术回归与用户画面认可分别记录；51 项验收没有默认判为通过。

本轮修复：整批资产采用的锁保护；投影／地面接点方向、坡道与缩放；等高吸附；默认保持像素比例的裁切；后台拖动、台地、院落、对象及路径候选；递归只读 UI 视图；共享不可变历史；PNG 后台处理、取消与导出预算；无边框核心分页合同。资产库加入缩略图、alpha 拾取，原型控件折叠，并可展开全部诊断。

[修复报告](docs/review_c7e0/FIX_REPORT.md) · [复验命令](tests/README.md) · [51 项映射](docs/review_c7e0/acceptance_51.json) · [执行结果](docs/review_c7e0/RESULTS.json)

PR #1 复审后续：统一保存拖动与后台修改意图，恢复后重新验证并等待明确应用；项目保存与正常自动恢复备份改为后台写入；导出冻结校验、绘制计划、素材解码与清单编码移到后台，对象列表分帧刷新。强制退出的同步恢复边界保留。

[本次修复与限制](docs/review_pr1/FIX_REPORT.md) · [逐项裁定](docs/review_pr1/ACCEPTANCE.md) · [可下载证据与画面](docs/review_pr1/EVIDENCE.md)

用户已否定关口候选1的素材与组合。候选2重做四件城防素材，重新校准墙门塔接合，并加入可选疏墨道路与坡面；等待新一轮视觉裁定。[候选2变更](docs/review_visual2/REVISION.md) · [候选2画面与证据](docs/review_visual2/EVIDENCE.md)。

## 打开

1. 用 Godot 4.6.1 导入仓库根目录的 `project.godot`。
2. 进入编辑器顶部“山河工坊”，或运行项目后选择“Canvas 制作 · workshop_s1”。
3. 点击“打开项目”，载入以下任一文件。

| 样板 | 可编辑项目 |
| --- | --- |
| 山口关隘 | [samples/w67_mountain_pass.shwork.json](samples/w67_mountain_pass.shwork.json) |
| 河岸小城 | [samples/w67_riverside_city.shwork.json](samples/w67_riverside_city.shwork.json) |
| 坡地村落 | [samples/w67_hillside_village.shwork.json](samples/w67_hillside_village.shwork.json) |
| 独立关口美术候选1（用户已否定，保留对照） | [samples/fortification_candidate1.shwork.json](samples/fortification_candidate1.shwork.json) |
| 独立关口美术候选2（待审核） | [samples/fortification_candidate2.shwork.json](samples/fortification_candidate2.shwork.json) |

保留相邻的 `samples/assets/`。原三个 JSON 和原 18 张 PNG 保持基线字节不变；两轮城防各有四张独立PNG。[候选1美术记录](samples/review_c7e0/ART_PROVENANCE.json) 与 [候选2来源、提示词和用户意见](samples/review_visual2/ART_PROVENANCE.json) 分开保存。

## 安装插件

复制 `addons/strategic_map_editor/` 到 Godot 工程的 `addons/`，在“项目设置 → 插件”启用“山河形胜二维地图工坊”。此仓库的 `project.godot` 和 `main.tscn` 提供现成的独立运行入口，`examples/blank.map.json` 是插件默认空白配置。

## 使用

工具提供可编辑路径、区域／树林、台地／崖壁／坡道、院落与街区、组合模板、复制／解组、标签／网格，以及合成PNG、透明地面、所选组、连续层序片、分页和可编辑数据包导出。导出页可打开生成的 `manifest.json` 进行Godot只读预览。

六种树形和灰瓦沿用此前素材；原样板继续保留工程灰盒，新城防素材只放在独立候选中等待视觉审核。地形和部分建筑仍使用程序几何。“缺口”对照仅示范移除墙段、隐藏屋顶，尚无完整损毁美术系统。素材来源保存在 `asset_refs` 中，上传不代表人工视觉接受。

单图尺寸上限8192×8192，另受工作像素256Mi、图像缓冲估算512MiB的保守预算限制；可先点“估算导出规模”。分页64—2048像素，裁自冻结全图，固定 `gutter:0`，实际 PNG 尺寸等于 `stored_size` 和核心尺寸。alpha 转换和 PNG 编码在后台处理，场景／纹理／读回留在主线程；原生单次 PNG 编码仅在前后检查取消。

拖动显示临时位置，松开后后台完整验证；地形／院落预览仍需明确应用。撤销和重做合计最多20条，目标预算为JSON估算64MiB，至少保留一条；该数值不是进程内存上限。保存、GPU读回和部分UI刷新仍可能出现长帧，具体实测与限制见修复报告。

上传基线的历史测试为5000对象／120配方、1080p的3×60秒及300秒：p95约5.8—6.7ms、p99约7.7—8.2ms，存在约1秒编辑长帧，静态内存随历史约234→539MiB。本轮区分原画布拖动、真实工坊控件和300秒编辑循环，口径详见报告。尚未扩展灯光、天气、在线分享等S2/S3功能。

本轮补充轻量测试、压缩夹具、来源清单和执行摘要。原始轨迹、导出PNG、操作截图与失败日志保留在本地证据包；不提交编辑器缓存、开发工具插件或历史大包。

旧 v4 迁移只支持注记与现有河流桥接。其他旧对象和 `presentation.instances` 请在原地图模式打开；支持的内容导入新项目后另存 `.shwork.json`。本工具不修改导航、GameState、玩法通行或游戏时间。

来源：本地审核C候选，源码基于 `3cfddc6`；三个样板为同一工具和素材通过普通控件制作的游戏设计地理。
