# 可下载复验证据

以下附件固定对应源码5fe9f928961c521e9f4c4279e2c3bec47e6f3920及当时的候选1画面。用户此后已否定候选1素材和组合；后续候选2的独立记录在 [review_visual2](../review_visual2/REVISION.md)。该历史附件、索引与性能数据保持原样，不认证后来新增的疏墨模式。

[下载独立证据附件（ZIP，约23.0MiB）](https://github.com/meixin007/NEW-MAP-TOOL/raw/4704ed00555ebe8123c95dbf9cd38ceed7cc480d/NEW-MAP-TOOL_PR1_evidence_20261020_r2.zip)

[外部附件索引](https://github.com/meixin007/NEW-MAP-TOOL/blob/4704ed00555ebe8123c95dbf9cd38ceed7cc480d/INDEX.json)。证据位于单独分支codex/pr1-review-evidence-20261020，插件PR分支不放ZIP、缓存或工具二进制。该分支不是稳定版发布。

- 文件：NEW-MAP-TOOL_PR1_evidence_20261020_r2.zip
- 字节数：24077668
- ZIP SHA256：c2adb885416f52e8c716ac076a005032f482f3e69047509b00754358c39b5c83
- 包内INDEX.json SHA256：2e8c0bd16d22723dfa81f375861eb225781fa9b12b80a4a61d985d96ad3aa26b
- 索引文件数：398
- 固定附件提交：4704ed00555ebe8123c95dbf9cd38ceed7cc480d

解压到新目录，使用Python 3.10+运行：

    python -X utf8 verify_packet.py .

验证器仅使用标准库，先核对全部文件SHA256及PNG CRC，再独立解码PNG滤波、按manifest重组分页，使用float64 source-over重组连续层序。分页要求通道差0；层序预设最大通道差2、差值超过1的比例不大于0.0001。实际重算为0、2、0.0000035183269651615264。

包内相对路径：

| 路径 | 内容 |
|---|---|
| INDEX.json | 全部文件路径、字节数、SHA256及对应源码hash |
| pixels/ | 完整冻结数据包、PNG、资产和manifest，可重组分页/层序 |
| visual/index.html | 五组固定镜头，素材与组合分开裁定 |
| runs/FINAL_*/ | 原生RESULT、stdout/stderr、日志与机器JSON |
| csv/ | 逐操作前后、重负载控件、3x60秒和300秒原始帧轨迹 |
| earlier_runs/ | 原反例失败、测试设置错误、已修复回归和重跑记录 |
| fixtures/ | 同一冻结5000/120夹具及编辑变体的压缩源 |
| report/ | 本轮修复说明、逐项裁定、源码与结果清单 |

原生复跑命令见 [tests/README.md](../../tests/README.md)。文件索引与轨迹使用相对路径；原始执行命令保留当时的临时绝对路径作为事实记录，这些临时目录不作为下载附件的使用前提。没有打包用户参考原图、API配置、开发插件、编辑器缓存或软件。

该附件中的候选1画面已被用户否定；候选2仍等待用户裁定。原始自动回放、PNG与技术检查不能代替用户接受。源码变更与附件上传均不等于合并PR或稳定版发布。
