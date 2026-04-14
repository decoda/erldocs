## 项目概述

erldocs 为 Erlang/OTP 项目生成 HTML 文档，格式与 erldocs.com 一致。它是一个 escript，解析 edoc XML 文件并输出可浏览的带搜索功能的文档。

## 支持的 OTP 版本

- **当前支持**：Erlang/OTP 23 及以下版本
- **重构目标**：支持 Erlang/OTP 28+ 版本
- **兼容性策略**：不保留对旧版本的兼容性支持

## 构建和开发

```bash
# 构建项目（创建 _build/default/bin/erldocs escript）
make

# 运行测试（需要先构建 ERLDOCS 可执行文件）
make test

# 格式化代码
make fmt TO_FMT=.

# 清理构建产物
make distclean
```

## 常见用法

```bash
# 为当前应用生成文档（输出到 ./doc/erldocs）
./erldocs .

# 使用自定义输出目录生成文档
./erldocs -o /path/to/output /path/to/app

# 为 Erlang/OTP tarball 生成文档
./otp.sh otp_src_28.3/

# OTP 脚本需要先构建 OTP：
cd otp_src_28.3/ && ./configure && make && make docs
```

## 架构

### 核心模块

- [src/erldocs.erl](src/erldocs.erl) - CLI 入口和参数解析
- [src/erldocs_core.erl](src/erldocs_core.erl) - 主要文档生成逻辑，XML→HTML 转换
- [src/specs_gen__*.erl](src/) - OTP 版本特定的类型规范提取（待重构）

### 构建流程

1. XML 生成：使用 `edoc:application/3` 或 `edoc:file/2` 从 Erlang 源码生成 XML
2. 类型规范：使用 OTP 特定的生成器（根据 OTP 版本选择）提取 `-spec` 和 `-type`
3. XML→HTML：通过 erldocs_core 中的自定义 `tr_erlref/2` 函数转换 edoc XML
4. 模板：使用 [priv/templates/](priv/templates/) 中的 ErlyDTL 模板渲染 HTML

### 输出结构

```
docs-<release>/
├── index.html           # 模块索引
├── erldocs_index.js     # 搜索索引
├── erldocs.css/js       # 静态资源
└── <app_name>/
    └── <module>.html    # 每个模块的文档
```

## 关键技术细节

- **OTP 版本处理**：不同的 specs_gen 模块处理跨 OTP 版本的类型提取（< R15, R15-17, >= 18）
  - **重构方向**：简化为单一实现，仅支持 OTP 28+
- **XML 解析**：使用 xmerl 配合自定义 ETS 表（`?ERLDOCS_XMERL_ETS_TABLE`）处理 DTD 规则
- **并行处理**：使用 `pmapreduce/5` 进行并发模块处理
- **HTML 编码**：输出为 latin-1 编码（非 utf-8）
- **忽略的模块**：kernel:init、kernel:zlib、kernel:erlang、kernel:erl_prim_loader 被排除

## 测试

`test/` 目录包含验证脚本。Travis CI 使用 `test/check.sh` 通过 git diff 比较生成的文档与预期输出。
