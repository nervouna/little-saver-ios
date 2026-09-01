# 小小存钱罐

小小存钱罐是一款开源的 iPhone 个人收支与预算应用。它专注于快速记账、预算管理和清晰的消费回顾，数据默认保存在你的设备上，并可通过私人 CloudKit 数据库在同一 Apple 账户的设备间同步。

## 功能

- 记录收入、支出和备注
- 自定义分类与预算
- 周期交易和时间范围统计
- CSV 导入与导出
- iCloud 同步状态
- 主屏幕与锁屏小组件
- Siri、Intent 和 App Shortcut
- 本地记账提醒
- 系统生物识别应用锁

## 构建

需要 macOS 和 Xcode。克隆仓库后打开 `app/LittleSaver.xcodeproj`，等待 Xcode 按仓库中的 `Package.resolved` 解析依赖，然后选择 `LittleSaver` Scheme 构建。Simulator 构建不需要开发者账号；真机构建需要可用的 Apple 开发者账号。

应用使用以下标识：

- App Bundle ID：`io.damao.littlesaver`
- App Group：`group.io.damao.littlesaver`
- CloudKit Container：`iCloud.io.damao.littlesaver`

使用自己的开发者账号构建时，需要在 Xcode 中为 App、Widget、Intent 和 Intent UI 配置相应签名。不要把个人证书、描述文件或密钥提交到仓库。

## 隐私

应用不包含广告或分析 SDK。交易、分类、预算与设置保存在设备和你的私人 CloudKit 数据库中；通知由系统在本地安排。详细说明见[隐私说明](docs/privacypolicy.md)。

## 开源与上游

本项目是 [Dime](https://github.com/rarfell/dimeApp) 的 fork。Dime 由 Rafael Soh 创建；本项目保留原作者署名，并感谢所有上游贡献者。

小小存钱罐沿用 GNU General Public License v3.0，完整条款见 [LICENSE](LICENSE)。第三方组件与许可见 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)。

## 参与贡献

源代码托管在 [nervouna/little-saver-ios](https://github.com/nervouna/little-saver-ios)。问题与建议请提交到 [GitHub Issues](https://github.com/nervouna/little-saver-ios/issues)。
