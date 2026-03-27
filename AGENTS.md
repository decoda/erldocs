# erldocs Agent 协作说明

本仓库当前的主要目标是生成并维护 Erlang/OTP 28+ 的文档输出。后续 Agent、自动化脚本与协作者在本仓库内工作时，应优先围绕 OTP 28 及以上版本的采集、渲染、模板兼容性和生成结果展开，避免把精力分散到过旧版本的兼容细节上，除非任务明确要求。

## 当前工作重点

- 主要关注 Erlang/OTP 28+ 文档生成链路。
- 优先理解并维护现代文档采集路径，即 `src/erldocs_collect_modern.erl` 所在流程。
- 对 OTP 28+ 输出有影响的改动，应优先验证：
  - 模块文档采集是否完整。
  - 函数、类型、回调、链接重写是否正确。
  - HTML 渲染结果是否稳定。
- 如果某项修改只改善 OTP 28+ 行为，而对更旧版本没有覆盖，不应默认视为问题；只有在任务明确要求兼容旧版本时才扩展处理范围。

## 推荐优先阅读的文件

- `src/erldocs_collect.erl`
  入口分发逻辑，决定是否启用现代采集路径。当前代码中对 OTP 28+ 有明确分支判断。

- `src/erldocs_collect_modern.erl`
  OTP 28+ 的核心采集实现。涉及模块文档读取、HTML 处理、链接修正等问题时，优先从这里定位。

- `src/erldocs_render.erl`
  渲染出口，负责把采集结果写入页面输出。

- `priv/templates/erldocs.dtl`
  页面结构模板。页面布局、字段显示、导航区域、输出片段异常通常从这里检查。

- `test/erldocs_collect_modern_tests.erl`
  OTP 28+ 现代采集路径的核心测试，修改现代文档链路时应优先补充这里。

## 项目结构

- `src/`：Erlang 源码目录。
- `include/`：头文件、record、宏定义。
- `priv/templates/`：HTML/CSS/JS/DTL 模板。
- `test/`：EUnit 与 shell 回归测试。
- `doc/<otp-version>/`：已生成并提交的文档快照，属于构建产物。
- `_build/default/bin/erldocs`：构建后生成的 escript。

## 修改原则

- 先确认问题发生在采集、模型整理、渲染还是模板层，再动手修改。
- 优先修改源码或模板，不要直接手工编辑 `doc/<otp-version>/` 下的生成文件。
- 涉及 OTP 28+ 的问题时，默认先检查现代采集路径，不要一开始就把问题归因到旧兼容逻辑。
- 不做与当前任务无关的大面积重构、重排、全量格式化或模板美化。
- 若仓库中已有未提交改动，除非任务明确要求，不要回退、覆盖或清理。

## 常用命令

- `make`
  常规构建，执行 `rebar3 compile` 并产出 `_build/default/bin/erldocs`。

- `make test`
  推荐的基础验证命令，会编译项目、检查 escript 打包内容，并运行 `rebar3 eunit`。

- `./_build/default/bin/erldocs .`
  为当前项目生成文档，适合本地快速验证基础输出。

- `./otp.sh otp_src_28.3/`
  针对本地 OTP 28+ 源码目录生成 OTP 风格文档。目录名按实际版本调整，例如 `otp_src_28.0/`、`otp_src_28.3/`。

- `make fmt TO_FMT=src test`
  仅在确有必要时使用，避免制造无关格式 diff。

## 针对 OTP 28+ 的验证建议

- 修改 `src/erldocs_collect_modern.erl` 后，优先运行：
  - `make test`
  - 与现代采集相关的 EUnit 测试，尤其是 `test/erldocs_collect_modern_tests.erl`

- 修改 `src/erldocs_render.erl` 或 `priv/templates/` 后，除测试外还应关注：
  - 页面是否能正确展示模块文档与函数文档。
  - 独立链接、模块间链接、站内路径是否被正确重写。
  - 生成 HTML 是否出现编码、空区块、错位或缺字段问题。

- 如果输出确实应变化，再更新 `doc/<otp-version>/`，并检查 diff 是否只包含预期结果。

## 测试要求

- 逻辑变更优先补充 EUnit，测试文件放在 `test/*_tests.erl`。
- 现代文档路径相关变更，优先在 `test/erldocs_collect_modern_tests.erl` 增补用例。
- 测试函数使用 `_test` 后缀。
- 输出回归问题可结合 `test/check.sh`、`test/reproduce.sh` 或实际生成的 OTP 28+ 文档做验证。
- 提交前至少执行一次 `make test`；如果未执行，必须在结果说明里明确写出原因。

## 代码风格

- 维持现有 Erlang 风格：4 空格缩进、列表和记录字段尽量对齐。
- 保持仓库已有函数定义习惯，在函数名与参数列表之间留空格，例如 `main (Args) ->`。
- 模块名、文件名、函数名使用 `snake_case`。
- 仅在已有兼容性文件中沿用双下划线命名。
- 优先写小函数、纯函数和可测试函数，避免把复杂分支堆在单个函数里。

## 生成产物约束

- `doc/<otp-version>/` 是构建结果，不是源码。
- 非必要不要提交与任务无关的生成文档 diff。
- 只有在确认输出变化属于预期行为时，才更新并提交生成结果。
- 不要手工修补生成 HTML 来掩盖源码或模板中的真实问题。

## 何时需要暂停并确认

- 需要同时改变 OTP 28+ 现代路径与旧版本兼容路径，而且影响边界不清晰。
- 需要批量更新大量 `doc/` 产物，但暂时无法确认差异是否合理。
- 发现现有测试无法覆盖改动风险，且补测试需要改变较多基础行为。
- 发现用户已有本地修改与你的目标文件直接冲突。

## 输出结果时应说明的内容

- 改动影响的是采集、渲染还是模板。
- 是否主要针对 OTP 28+。
- 实际运行了哪些验证命令。
- 是否更新了 `doc/<otp-version>/` 生成产物。
- 还有哪些风险未覆盖，例如未验证旧版本 OTP、未跑完整生成流程等。
