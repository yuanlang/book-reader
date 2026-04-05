# BookReader - iOS EPUB 阅读器

一款 iOS EPUB 电子书阅读器应用，支持中文 TTS 语音朗读。

## 项目概述

- **平台**: iOS 17.0+
- **语言**: Swift 5.9
- **框架**: SwiftUI + SwiftData
- **构建工具**: XcodeGen (project.yml)

## 核心依赖

- **Readium Swift Toolkit** (3.0.0) - EPUB 解析与渲染
  - ReadiumShared
  - ReadiumStreamer
  - ReadiumNavigator
- **sherpa-onnx** - 神经网络语音合成引擎 (Kokoro TTS)
- **onnxruntime** - ONNX 推理运行时
- **CppJieba** - 中文分词

## 项目结构

```
BookReader/
├── App/
│   ├── BookReaderApp.swift    # App 入口
│   ├── ContentView.swift      # 根视图
│   └── AppDelegate.swift      # 应用代理
├── Models/
│   ├── Book.swift             # 书籍模型 (SwiftData)
│   └── ReadingProgress.swift  # 阅读进度模型
├── Library/
│   ├── LibraryView.swift      # 书架列表视图
│   ├── LibraryViewModel.swift # 书架业务逻辑
│   └── BookCardView.swift     # 书籍卡片组件
├── Reader/
│   ├── ReaderView.swift       # 阅读器视图
│   ├── ReaderViewModel.swift  # 阅读器业务逻辑
│   └── TTSControlPanel.swift  # TTS 控制面板
├── Services/
│   ├── Storage/
│   │   └── BookStorageService.swift  # 文件存储服务
│   ├── TTS/
│   │   ├── SherpaOnnxTTSEngine.swift # TTS 引擎实现
│   │   ├── SherpaOnnxBridge.swift    # C++ 桥接
│   │   └── AudioPlayerService.swift  # 音频播放
│   └── Segmentation/
│       ├── JiebaSegmenter.swift        # 结巴分词封装
│       └── JiebaContentTokenizer.swift # Readium 分词器
├── Resources/
│   └── tts-models/  # Kokoro-82M-v1.1-zh 语音模型
├── CppJieba/        # CppJieba C++ 源码
└── Bridging/
    └── BookReader-Bridging-Header.h
```

## 功能模块

### 书架管理
- EPUB 文件导入与元数据解析
- 书籍列表展示 (封面、标题、作者)
- 自动扫描 Documents/Books 目录

### 阅读器
- EPUB 内容渲染 (Readium Navigator)
- 全屏沉浸式阅读体验
- 导航控制

### TTS 语音朗读
- 中文语音合成 (MeloTTS + sherpa-onnx)
- 英文/其他语言回退到系统 TTS
- 播放/暂停/跳转控制
- 语速调节 (0.5x - 2.0x)
- 自动翻页跟随朗读位置

## 构建说明

```bash
# 生成 Xcode 项目
xcodegen generate

# 编译运行
xcodebuild -project BookReader.xcodeproj -scheme BookReader -destination 'platform=iOS Simulator,name=iPhone 16'
```

## 关键技术点

### Readium 集成
- 使用 `EPUBNavigatorViewController` 渲染 EPUB
- 通过 `PublicationSpeechSynthesizer` 实现 TTS
- 自定义 `TTSEngine` 协议实现对接 sherpa-onnx

### 中文 TTS
- 使用 Kokoro-82M-v1.1-zh 模型 (位于 Resources/tts-models/)
- 通过 sherpa-onnx Kokoro 引擎进行语音合成
- 支持中文+英文双语合成，103个说话人
- 音频输出采样率 24000 Hz

### 数据持久化
- SwiftData 存储书籍信息和阅读进度
- 文件存储在 Documents/Books/ 目录

## 开发工作流程

**重要**: 每次功能开发完成后，必须执行以下自动化流程：

### 触发条件
当用户说 **"完成"**、**"done"** 或 **"测试提交"** 时，自动执行：

### 1. 运行自动化测试
```bash
# 运行 UI 测试
./scripts/run_tests.sh

# 或手动运行
xcodebuild test -project BookReader.xcodeproj -scheme BookReaderUITests -destination 'platform=iOS Simulator,name=iPhone 16'
```

测试内容：
- 启动模拟器并运行应用
- 验证书架加载和书籍显示
- 测试打开书籍和 TTS 控制面板
- 测试 TTS 播放/暂停功能

### 2. 提交代码
测试通过后，自动执行 git commit：
- 分析修改的文件和内容
- 自动生成 commit message（根据功能内容）
- 提交到本地仓库

### 示例 commit message 格式
```
feat: 添加 XXX 功能

- 修改文件1
- 修改文件2

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```
