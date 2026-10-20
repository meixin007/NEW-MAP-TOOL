# NEW MAP TOOL · 山河工坊

Godot 4.6.1 地图制作插件，包含 W6—W7 核心版候选和三个最终可编辑样板。

## 打开

1. 用 Godot 4.6.1 导入仓库根目录的 `project.godot`。
2. 进入编辑器顶部“山河工坊”，或运行项目后选择“Canvas 制作 · workshop_s1”。
3. 点击“打开项目”，载入以下任一文件。

| 样板 | 可编辑项目 |
| --- | --- |
| 山口关隘 | [samples/w67_mountain_pass.shwork.json](samples/w67_mountain_pass.shwork.json) |
| 河岸小城 | [samples/w67_riverside_city.shwork.json](samples/w67_riverside_city.shwork.json) |
| 坡地村落 | [samples/w67_hillside_village.shwork.json](samples/w67_hillside_village.shwork.json) |

保留相邻的 `samples/assets/`。其中18个内容寻址PNG是三个项目引用的依赖，原始像素和项目JSON保持最终候选包原样；不要只下载JSON。

## 安装插件

复制 `addons/strategic_map_editor/` 到 Godot 工程的 `addons/`，在“项目设置 → 插件”启用“山河形胜二维地图工坊”。此仓库的 `project.godot` 和 `main.tscn` 提供现成的独立运行入口，`examples/blank.map.json` 是插件默认空白配置。

## 使用

工具提供可编辑路径、区域／树林、台地／崖壁／坡道、院落与街区、组合模板、复制／解组、标签／网格，以及合成PNG、透明地面、所选组、连续层序片、分页和可编辑数据包导出。导出页可打开生成的 `manifest.json` 进行Godot只读预览。

六种树形和灰瓦沿用此前素材；关门、墙段仍包含工程灰盒，地形和部分建筑表面为程序几何。素材来源声明保存在项目的 `asset_refs` 中。该版本为审核C候选，上传不代表新增人工视觉接受。

单图导出上限8192×8192像素，分页64—2048像素，分页裁自同一冻结全图。5000对象／120配方、实际1080p的3×60秒及300秒本机测试中，p95约5.8—6.7ms、p99约7.7—8.2ms；编辑仍存在约1秒长帧，300秒静态内存随撤销历史约234→539MiB。尚未实现灯光／天气、在线分享等扩展。

仓库只保留插件运行文件、独立入口、三个样板及其必需依赖；不含录像、截图、测试与性能日志、导出图、历史包或编辑器缓存。

来源：本地审核C候选，源码基于 `3cfddc6`；三个样板为同一工具和素材通过普通控件制作的游戏设计地理。
