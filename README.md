# STM32CubeIDE 汉化

STM32CubeIDE 1.19.0（Eclipse 2024-06 / 4.32）界面汉化方案，机制对标「Proteus汉化」——**走官方语言包机制，不碰二进制、不反编译**。

## 一句话结论

STM32CubeIDE 是 Eclipse RCP 应用，汉化走 Eclipse 官方 **NLS 语言片段（`nl_zh`）** 机制：把中文资源以「片段包」形式挂在宿主插件上，启动时加 `-nl zh_CN` 即生效。共两层：

| 层 | 内容 | 来源 |
|---|---|---|
| Eclipse / CDT 层 | 平台、SWT、JFace、帮助、团队、C/C++ 编辑器与构建 | Eclipse 官方 **Babel** 中文语言包（R0.20.0） |
| ST 自有层 | 82 个 `com.st.*` 插件（SWV、FreeRTOS、ThreadX、构建分析器、工程向导等） | ST **自带中文 37.5%** ＋ 本项目**自建片段包补齐 94.7% 缺口** |

## 关键发现（本次接管后查明）

1. **ST 自己已经翻译了一部分**。82 个 ST 插件里有 25 个带 `messages_zh.properties` / `OSGI-INF/l10n/bundle_zh.properties`，共 578 / 1544 条（**37.5%**，其中 FreeRTOS、Live Watch、Fault Analyzer、ST-LINK、JLINK、SFR 视图、Debug Launch 为 100%）。
2. 这部分中文由区域（locale）决定是否加载。本机 `configuration/org.eclipse.osgi/framework.info.3` 记录的 `osgi.nl` 已是 `zh_CN`（中文 Windows 的 OS 区域所致），所以这部分中文**本来就可能在生效**；IDE 整体仍显得是英文，主因是**平台层没有中文包**（占可见界面的大头）＋ **ST 未译的 62%**。
3. 其余 966 条（738 条独立文案）ST 未翻译，本项目已补齐 **915 条（94.7%）**，编译为 38 个 `nl_zh` 片段包。
4. Eclipse 官方 Babel 中文包最新为 **R0.20.0（2022-12，对应 Eclipse 4.26）**；其片段包声明 `Fragment-Host: org.eclipse.ui` **不带版本约束**，因此可挂到本 IDE 的 4.32 上，缺失的新增文案自动回退英文。

## 目录结构

```
STM32CubeIDE汉化/
├─ README.md                本文件
├─ .gitignore               把运行时生成目录 runtime\ 排除出仓库
├─ docs/
│  ├─ 原理与兼容性.md        Eclipse NLS 机制、两层方案、版本兼容性分析
│  └─ 验证记录.md            实测数据与验证步骤（引用的界面截图同目录）
├─ 词库/
│  ├─ st_strings.tsv         从 82 个 ST 插件抽出的 1544 条文案（英文 / ST 自带中文 / 缺口标记）
│  ├─ st_strings.summary.tsv 逐插件条数与缺口统计
│  └─ zh/                    中文词库（en<TAB>zh，按主题分三份，可继续增补）
│     ├─ 01-构建与工具链.tsv
│     ├─ 02-调试与运行时.tsv
│     └─ 03-工程与视图.tsv
├─ 工具/
│  ├─ 导出词条.ps1           从插件 JAR 抽取文案，区分英文与 ST 自带中文
│  ├─ 生成语言包.ps1         由词库编译出 nl_zh 片段包
│  ├─ 生成零写入运行环境.ps1  生成 runtime\ 与「零写入」启动器（见方式一）
│  ├─ 安装汉化.cmd / .ps1    装入 dropins 并启用 zh_CN（**写入安装目录**）
│  ├─ 还原英文.cmd / .ps1    一键还原
│  ├─ 以中文启动.cmd         零改动启动（不写入任何文件）
│  └─ 以汉化启动-零写入.cmd   由上面脚本生成的「零写入」启动器
└─ 成品/
   ├─ babel/                 5 个 Eclipse 官方中文语言包（eclipse / tools.cdt / egit / jgit / tm）
   └─ fragments/             38 个自建 nl_zh 片段包（+ fragments.list.tsv 清单）
```

（根目录另有 `runtime\`：「零写入」启动用的独立配置目录，约 50 MB，属可再生成物，已由 `.gitignore` 排除、不入库。）

## 用法

### 方式一：零写入汉化启动（推荐，不改 C 盘任何文件）

先运行一次 `工具\生成零写入运行环境.ps1` 生成 `runtime\`（约 50 MB，含 38 个自建片段 + 435 个 Babel 片段与独立配置目录；该目录属可再生成物，不随仓库分发，换机器或删除后重跑脚本即可）。然后关闭 STM32CubeIDE，双击 `工具\以汉化启动-零写入.cmd`。

该方式让 IDE 用一个**放在工作区里的独立配置目录**（`runtime\configuration`）启动：`bundles.info` 里追加了 38 个自建片段包与 435 个 Babel 片段（用绝对 `file:` 地址指向工作区），`config.ini` 里写上 `osgi.nl=zh_CN`。**C:\stm32ide 下一个文件都不写**，效果与完整安装一致；不想要了直接删 `runtime\` 目录即可。

### 方式二：零改动启动（只启用 ST 自带中文）

双击 `工具\以中文启动.cmd`：仅以 `-nl zh_CN` 启动，不加载任何附加包。只能看到 ST 自带的 37.5% 中文（FreeRTOS 任务/队列/信号量视图、SWV、Live Watch、Fault Analyzer、下载/调试启动等），菜单栏仍是英文。

### 方式三：完整安装（写入 `C:\stm32ide`，需授权）

关闭 STM32CubeIDE 后双击 `工具\安装汉化.cmd`。脚本会：
1. 备份 `stm32cubeide.ini` → `.zhbak`、`bundles.info` → `.zhbak`；
2. 把 38 个自建片段包与 5 个 Babel 包释放到 `<IDE>\dropins\stm32cubeide-zh\`；
3. **把 473 个中文包注册进 `<IDE>\configuration\...\bundles.info`**（实测本产品的 p2 **不接管 dropins**，只放 dropins 不会生效，必须写进包清单）；
4. 在 `stm32cubeide.ini` 的 **`-vmargs` 之前**写 `-nl zh_CN`（启动器参数），在 `-vmargs` 之后写 `-Dosgi.nl=zh_CN`（JVM 参数）。

重启 IDE（桌面快捷方式、开始菜单均可）即为中文界面。

### 还原

双击 `工具\还原英文.cmd`：删除 `dropins\stm32cubeide-zh`（若 dropins 因此变空则一并删除，恢复原始状态），并从 `.zhbak` 恢复启动配置。

### 维护与再生成

```
powershell -ExecutionPolicy Bypass -File 工具\导出词条.ps1     # 重抽文案（换版本后）
powershell -ExecutionPolicy Bypass -File 工具\生成语言包.ps1   # 由词库重编译片段包
```

词库直接改 `词库\zh\*.tsv`（`英文原文<TAB>中文`，与 `st_strings.tsv` 的 `en` 列精确对应），重跑生成脚本即可。IDE 升级后重复这两步即可重新适配，**不因版本变化而失效**。

## 覆盖情况

| 项目 | 条数 |
|---|---|
| ST 自有 UI / 提示文案 | 1544 |
| ST 自带中文（本项目仅需启用） | 578（37.5%） |
| ST 未译缺口 | 966（738 条独立文案） |
| 本项目已补齐 | 915（占缺口 94.7%） |
| 自建片段包 | 38 个 |
| Eclipse/CDT 层 | 由 Babel 官方包覆盖（非本项目翻译） |

未收录的少量文案（约 51 条，主要是 MPU/OpenSTLinux 与个别内部提示）回退为英文，不影响使用。

## 已知限制

- **`fragment.properties` 类插件仍为英文**：50 个有待译缺口的插件里有 6 个把界面文案放在 `fragment.properties`（配合 `fragment.xml` 扩展声明），实测 Eclipse 不会从外挂片段包里取用它们的 `fragment_zh_CN.properties` 覆盖（而 `plugin.properties` 类可以，已实测 `STM32 CMake Project → STM32 CMake 工程` 生效）。受影响的主要是「新建工程向导」的菜单项标签。要吃掉这点残余，需把中文写进这 6 个插件 JAR 内部（带 `.bak` 备份、可还原），属安装目录写入，须获授权。
- **Babel 版本差**：官方中文包停更于 R0.20.0（Eclipse 4.26），本 IDE 为 4.32。片段包无宿主版本约束，可正常挂载；4.26 之后新增的界面词条无中文，回退英文（例如「文件」菜单里的 `Recent Files`）。
- **不翻译的内容**：器件型号、`-fxxx` 编译选项、`VFPv3-D16` 等硬件特性名、URL、版本号保持原文，符合工程习惯。
- **授权要求**：方式三写的是 `C:\stm32ide` 安装目录，属工作区外修改，须先获授权；方式一、方式二都不写安装目录。
