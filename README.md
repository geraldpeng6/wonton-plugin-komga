# 云吞插件：Komga

[云吞](https://github.com/geraldpeng6/wonton)插件：[Komga](https://komga.org) 漫画和电子书媒体库服务器。开发流程见[插件开发指南](https://github.com/geraldpeng6/wonton-docs/blob/main/develop.md)。

- 登录：`sso: oidc`，由云吞的身份提供方登录，打开即管理员本人。Komga 按邮箱匹配用户，首次安装用上游自己的
  `/api/v1/claim` 接口（网页首次创建管理员的同一条路）以主人邮箱建好管理员；家人经 OIDC 登录时自动建普通用户。
- 漫画库：media 共享文件夹，只读挂载到容器的 `/data`；配置和数据库在插件数据目录的 `config/` 下。
- 镜像：上游官方镜像 `gotson/komga`，按多架构清单摘要固定（amd64、arm64）。

## 图标

`icon.svg` 是 Komga 官方标志，来源、许可和商标说明见 [NOTICE](NOTICE)。
