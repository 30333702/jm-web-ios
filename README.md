# 禁漫客户端（Flutter / iOS）

原生 Flutter 客户端，直接调用自托管 API 的 `/api/*` 接口，不依赖 WebView。服务端地址与访问密码在登录页填入，会话 Cookie 通过 `shared_preferences` 持久化。

默认配置：

- 服务器：`http://192.168.50.251:3210`
- 访问密码：`admin123`
- 图片走服务端 `/api/img` 代理，章节图片按 `jm-mobile` 的分片算法自动解码

## 功能

- 首页推荐、精选区块与横向书架
- 搜索、分类、热门标签
- 每周期数周榜
- 漫画封面/详情、收藏与点赞
- 章节分页阅读，支持缩放与横向翻页
- 仅在 iOS 上作为原生应用使用，Windows 当前只维护源码与打包说明

## 在本机构建

源码在 Windows 上可以直接写、分析和测试，但 `.ipa` 只能由 macOS + Xcode 产出。

1. 安装 Flutter 与 Xcode，项目根目录执行：

   ```bash
   flutter pub get
   ```

2. 打开 iOS 工程：

   ```bash
   open ios/Runner.xcworkspace
   ```

3. 在 Xcode 的 Signing & Capabilities 中选择自己的 Apple Developer Team。

4. 构建：

   ```bash
   flutter build ipa --release
   ```

   也可以先在模拟器或真机上直接运行：

   ```bash
   flutter run
   ```

## 用 GitHub Actions 免费生成 IPA

仓库里已经内置 `.github/workflows/ios-ipa.yml`。推送到 GitHub 后，在 `Actions` 页面手动触发 `Build iOS IPA`，或者直接推送 `main` 分支即可自动构建。

工作流使用 GitHub 自带的 `macos-14` 免费分钟数构建，产物是未签名的 `.ipa`：

1. 强烈建议使用公开仓库，公开仓库的 macOS Actions 不消耗私有仓库的有限免费分钟。
2. 构建完成后，在 `Actions` 运行记录的 `Artifacts` 里下载 `jm-web-ios-unsigned`。
3. 未签名 IPA 无法直接安装到 iPhone，需要在 macOS 上配置自己的 Apple Developer 证书后重新签名，或按“在本机构建”的流程用 Xcode 打签名包。

## 服务器注意事项

登录成功后客户端会保存服务端下发的 `jmw_auth` Cookie；切换服务器时先在“我的”退出登录，再重新登录。

客户端已为 HTTP 局域网地址开启 iOS 的 `NSAllowsArbitraryLoads`，但正式上架 App Store 前应改为 HTTPS 并移除该放宽项。

iOS 14 及以上首次连接局域网服务器时需要允许“本地网络”权限；如果出现 `No route to host (errno 65)`，请确认 iPhone 与服务器处于同一 Wi-Fi、Windows 防火墙已放行 TCP 3210，并重新允许本地网络访问。
