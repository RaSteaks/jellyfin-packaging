# 群晖按分支更新 Jellyfin

在群晖 Container Manager 中导入本目录的 `docker-compose.yml`，或把内容粘贴到项目的 YAML 编辑器。镜像、仓库、分支、端口和挂载路径都在这份文件里填写。入口脚本已包含在镜像内。Jellyfin 容器负责查询分支和启动服务，项目里的 rootless BuildKit 容器负责在 NAS 上编译。

## 首次部署

1. 核对旧 Jellyfin 版本到目标 Server 分支的升级路径。停止旧服务，在 File Station 复制整个旧 `/config` 对应的 NAS 文件夹。在 `jellyfin.volumes` 中，找到 `target: /config`，将同一项的 `source` 改为副本的绝对路径，保留原目录用于回退。
2. 在 `services.jellyfin` 下，将 `image` 改为发布镜像的完整名称和标签，在 `environment` 填写三个 fork 的地址和分支。按需修改 `ports` 映射左侧的 NAS 端口。
3. 在媒体挂载项填写宿主机路径 `source` 和旧容器内路径 `target`。有多个媒体库时，按模板复制媒体挂载段并逐项填写。若使用硬件转码，从旧项目补上设备映射和组权限。需要出站代理时，填写 `services.builder.environment` 中的代理字段，两个服务会共用这些值。
4. 在 Container Manager 中创建并启动项目。在 `jellyfin` 服务日志查看每个提交的编译输出。首次构建会下载三个 fork 和依赖。FFmpeg 会编译编解码器、驱动和 Debian 包，占用较多时间和存储。首次成功后 Web 端口才会就绪。
5. 在浏览器访问群晖地址和你选择的端口，用原账号核对媒体库、观看进度和播放。如果旧实例在过渡期产生了新数据，正式切换前请停两边服务，并用旧实例最新的完整备份做最终迁移。

## 指定仓库和分支

在 `services.jellyfin.environment` 中填写以下六个变量。修改变量后，在 Container Manager 重新部署项目以应用新配置。之后推送源码，只需重启 `jellyfin` 服务。

| 组件 | 仓库变量 | 分支变量 |
| --- | --- | --- |
| Server | `JELLYFIN_SERVER_REPO` | `JELLYFIN_SERVER_BRANCH` |
| Web | `JELLYFIN_WEB_REPO` | `JELLYFIN_WEB_BRANCH` |
| FFmpeg | `JELLYFIN_FFMPEG_REPO` | `JELLYFIN_FFMPEG_BRANCH` |

构建配方适配 .NET 10 Server、Node 24 Web 和带 Debian `Dockerfile.in` 及 `jellyfin-disc-info` 的 FFmpeg 8 源码。公开仓库可匿名读取。私有 fork 需要给容器中的 Git 单独配置只读凭证。

## 重启和恢复

每次重启会检查三个分支的提交，以及镜像里各组件的构建配方摘要。日志中的 `Building` 表示准备新产物，`Reusing` 表示复用相同架构、提交和配方的产物。三项都就绪后才切换版本。第一次从旧缓存格式升级时，三个组件各重编一次，成功切换前可继续回退到原版本。

首次编译或产物检查失败时，容器保留日志并等待人工重试，Web 服务尚未启动。修正原因后，在 Container Manager 重启 `jellyfin` 即可再次尝试。已经完成的组件会留到下次重试。若已有完整版本，拉取或构建失败时会启动上次选定的版本。HTTPS 源码下载持续 120 秒低于 1 KiB/s 时会中止该次拉取。

组件和 BuildKit 缓存分别存放在 `components`、`builder-cache` 卷。`/components/current/commits` 逐行记录组件名、源码提交和配方 SHA-256。每次成功检查后，更新器保留当前和上一组已启用的版本，清理两者都未引用的组件。失败的更新不会触发清理。上一组版本的目录名记录在 `/components/current/previous`。Server 如果已经迁移数据库，回退时还需要与旧版本匹配的配置备份。

## 构建环境

发布镜像覆盖 `linux/amd64` 和 `linux/arm64`。默认构建器要求 DSM 内核支持非特权用户命名空间。若 `builder` 日志报告 `unshare: operation not permitted` 或 `newuidmap` 失败，请先确认该机型的内核支持。ARM64 的 FFmpeg 沿用 fork 的 amd64 交叉编译环境，还要求构建器能够执行 amd64 构建步骤。编译时可以在 `builder` 日志里定位平台或内核错误。

如果 DSM 内核不支持 rootless，而你接受专用构建容器拥有 NAS 级特权，可以在同一份 Compose 里仅修改 `builder` 服务。把镜像换成 `moby/buildkit:v0.33.1`，删除 `security_opt`，加入 `privileged: true`，保留同一个 `--addr` 和 `builder-run` 套接字卷。将该服务的缓存挂载改为 `builder-cache-rootful:/var/lib/buildkit`，并在顶层 `volumes` 增加 `builder-cache-rootful:`。这样可以使用新的缓存目录及其对应的用户权限。此模式会扩大构建器的权限，默认配置使用 rootless。

只有配置的 fork 会提供源码。BuildKit 能执行这些源码中的构建命令，因此应选择你信任的仓库和分支。构建器只挂载自己的运行目录和缓存。详见 [BuildKit rootless 配置](https://github.com/moby/buildkit/blob/master/docs/rootless.md) 和 [多架构编译说明](https://github.com/moby/buildkit/blob/master/docs/multi-platform.md)。
