# 候选2复验证据

[下载候选2独立证据ZIP](https://github.com/meixin007/NEW-MAP-TOOL/raw/7c5826f78db68f5fe9b32363f2dbdb653f883d84/visual2/NEW-MAP-TOOL_visual2_evidence_20261020.zip) · [191项文件索引](https://github.com/meixin007/NEW-MAP-TOOL/blob/7c5826f78db68f5fe9b32363f2dbdb653f883d84/visual2/INDEX.json)。证据位于已有独立证据分支，不混入插件源码包。

- ZIP：25246416字节，约24.1MiB。
- SHA256：`0a2e59a845af215a0a1ff957ab71d42de0614b4d427a11565c5d074f5d4c795e`。
- 包内INDEX.json SHA256：`95abd9485939c4790ad93321996a5fcfda20b623729a56baa22feada16a72f3e`。
- 输入hash：`53e9c9741819e1a70ccfcfc0107b0bb7d603b8b5241ddfe92f50c743355e01b4`。
- 生成器：`workshop_s1.w5.1.ink-sparse1`，455个派生对象。

解压到新目录，在该目录运行 `python -X utf8 verify_packet.py .`。验证器仅使用标准库，检查191项文件、素材与冻结数据hash、PNG CRC及滤波、分页覆盖和独立float64层序重组。分页通道差0；层序最大通道差2，差值超过1的比例约0.000010014，满足预设0.0001。无需Godot或图像库即可复算。

已从GitHub重新克隆固定附件提交，核对ZIP SHA256，并在新目录独立解压运行验证器，191项文件及像素重组全部通过。

`visual/index.html` 包含素材独显、组合、近景、空地、地形独显、几何缺口及被否定的旧版对照。`project/` 提供候选2可编辑JSON、资产描述及12项PNG依赖。`pixels/` 为完整冻结分页/层序包；`runs/` 保留最终27次原生调用与早期失败；`report/` 保存来源、15条模式合同检查、像素结果、基线完整性与源码hash。

原21个单元脚本、新候选控件回放、新旧像素回归和编辑器导入通过。旧河滨城导出PNG与5fe9f92对应产物SHA256相同，原三个样板JSON和18张PNG仍为原字节。最终运行时/测试hash与本候选一致；记录在 [RESULTS.json](RESULTS.json)。

候选1已被用户否定；候选2素材及组合均为待审核。此前300秒性能证据仍绑定5fe9f92，不把它改称新模式性能证明。下载证据、自动检查和源码推送均不等于视觉接受、合并或稳定版发布。
