## [2026-07-31 14:30] | Task: 修复截图同步桥迟到完成

### 🤖 Execution Context
* **Agent ID**: `019f899d-355c-7352-9e7f-39883c64c01f`
* **Base Model**: `GPT-5.6`
* **Runtime**: `Codex`

### 📥 User Query
> 将 BlockingAsyncBridge 的当前主线超时缺陷作为独立前置修复，不混入 Dev helper 生命周期 PR；截止时间必须使用单调时钟，并确定性覆盖 main run loop 超时后才到达的完成信号。

### 🛠 Changes Overview
**Scope:** `OpenComputerUseKit`

**Key Actions:**
- **单调截止时间**: 用 `DispatchTime` 计算截图任务的超时边界，避免系统时钟校正延长等待。
- **迟到结果拒绝**: 每次 main run loop pump 返回后先检查截止时间，迟到信号不能覆盖已经发生的超时。
- **确定性回归**: 注入测试时钟和 run loop pump，稳定复现 callback 跨过截止时间且信号同时到达的边界。

### 🧠 Design Intent (Why)
截图同步桥需要在主线程继续 pump run loop，但 callback 可能超过请求的时间片。旧实现先接收 semaphore，再重查时间，因此会把截止时间后的结果当成成功。修复保持原有主线程兼容性，同时让超时上限真正生效。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-07/20260731-1430-fix-screenshot-timeout-deadline.md`
