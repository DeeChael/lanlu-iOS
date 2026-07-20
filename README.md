# lanlu iOS
这是为[兰鹿](https://cnb.cool/copurx/lanlu)开发的 iOS 客户端，使用 Swift 开发。

## 通行密钥域名配置

使用自己的兰鹿服务器时，需要同时配置客户端的 Associated Domains 和服务器的 AASA 文件，否则 iOS 无法使用该域名完成通行密钥注册或登录。

Github Actions 中编译的客户端没有配置任何服务器域名支持。

### 客户端配置

1. 在 Xcode 中打开 `lanlu` target 的 **Signing & Capabilities**，添加 **Associated Domains** capability。
2. 添加自己的服务器域名，格式为 `webcredentials:服务器域名`，不要包含协议、端口或路径。例如：

   ```text
   webcredentials:example.com
   ```

   也可以直接在 `lanlu/lanlu.entitlements` 的 `com.apple.developer.associated-domains` 数组中添加该值。
3. 使用自己的 Apple Developer Team 签名应用，并确认 Bundle Identifier。后续 AASA 中使用的 App ID 格式为 `Team ID.Bundle Identifier`，例如 `ABCDE12345.com.example.lanlu`。

### 服务器配置

在对应域名部署以下任一地址，推荐使用第一个：

```text
https://example.com/.well-known/apple-app-site-association
https://example.com/apple-app-site-association
```

文件名没有 `.json` 后缀，内容如下，将 App ID 替换为自己的值：

```json
{
  "webcredentials": {
    "apps": [
      "ABCDE12345.com.example.lanlu"
    ]
  }
}
```

AASA 必须通过有效的 HTTPS 直接访问，不能发生重定向，并应返回 `application/json` 或 `application/pkcs7-mime` Content-Type。服务器用于 WebAuthn 的 RP ID 也必须与这里配置的域名一致。修改 AASA 后，Apple 和系统可能存在缓存，测试时可等待缓存更新后重新安装应用。

## 已知问题

- 条漫模式下，自动阅读在显示控制栏后不会暂停；
- 阅读 epub 文件内容时切换文件时会闪，这是使用 webview 导致的。
- 自动阅读 epub 文件翻页时会闪烁
