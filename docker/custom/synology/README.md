# 群晖单容器按分支编译 Jellyfin

在 Container Manager 项目的 YAML 编辑器中粘贴本目录的 `docker-compose.yml`。填写镜像、三个 fork 的 HTTPS 地址和目标分支、端口及挂载路径。镜像标签为 `synology-native-v2`，支持 Linux AMD64 和 ARM64。项目只运行 `jellyfin` 一个服务。

## 部署或迁移

1. 核对旧服务器到目标分支的数据库升级路径。停止旧服务，复制整个旧 `/config` 对应的 NAS 文件夹，将副本填入 Compose 的配置挂载。为各媒体库保留原容器内路径。需要硬件转码时，沿用原项目的 GPU 设备映射和权限。
2. 在 `services.jellyfin.environment` 中填写三个仓库和分支，按需填写出站代理。公开仓库可匿名访问。私有 fork 需要为入口脚本中的 Git 提供只读凭证。FFmpeg 默认以两个并行任务编译，可按 NAS 内存调整 `JELLYFIN_BUILD_JOBS`。
3. 从 `synology-source-v1` 切换时，停止原项目，保留 `components`、`cache` 卷和配置目录，在同一项目应用新的单服务 Compose 并重新部署。若 DSM 仍列出旧的 builder 容器，单独停止并移除它。原 v1 镜像继续保留。
4. 在 `jellyfin` 日志查看各组件的 `Building` 或 `Reusing`。首次编译完成后，使用配置的群晖端口访问。切换到原生工具链时三个组件各重编一次。

## 构建和重启

| 组件 | 仓库变量 | 分支变量 | 在 NAS 上执行的构建 |
| --- | --- | --- | --- |
| Server | `JELLYFIN_SERVER_REPO` | `JELLYFIN_SERVER_BRANCH` | .NET 10 SDK 自包含发布 |
| Web | `JELLYFIN_WEB_REPO` | `JELLYFIN_WEB_BRANCH` | Node.js 24、npm ci、生产版 Web 构建 |
| FFmpeg | `JELLYFIN_FFMPEG_REPO` | `JELLYFIN_FFMPEG_BRANCH` | 应用 fork 的 Debian quilt 补丁，原生编译 FFmpeg、FFprobe 和 jellyfin-disc-info |

FFmpeg 配方适配提供 `debian/rules`、quilt 补丁及光盘导航工具的 Jellyfin FFmpeg 8 fork。镜像在 `/opt/jellyfin-codecs` 中提供 libplacebo v7.360.1 的头文件和共享库，并应用 fork 的 P01x 位移补丁。更新这项依赖只改变 FFmpeg 的缓存键。ARM64 在本机编译。可用硬件编码器仍取决于 NAS 的芯片、内核驱动和容器映射。

向选定分支推送后重启 Jellyfin。更新器按架构、源码提交和该组件的构建配方及工具链摘要复用产物。NAS 只在本地缺少对应产物时获取源码并编译；更新同一镜像的 Web 分支时可复用 Server 与 FFmpeg。构建在容器内以专用非 root 用户执行，与运行中的服务共用文件系统。只配置可信的 fork 和分支。下载依赖需要 NAS 能访问相应仓库、NuGet 和 npm。编译期间 Web 服务尚未启动。

## 恢复

三个组件均就绪后才切换整组版本。`/components/current/commits` 记录各组件的提交与配方摘要。成功检查后保留当前和上一组组件，构建用户的包缓存保存在 `components` 卷中。已有完整版本时，网络或编译失败会继续启用上次选定的版本。首次编译失败时保留日志并等待人工重试，修正原因后重启容器。若服务器已经迁移数据库，回退服务器镜像时还需要匹配的配置备份。
