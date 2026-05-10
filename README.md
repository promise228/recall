# 时间相册

这是一个可以直接部署到 GitHub Pages 的静态相册网站。

## 本地结构

- `index.html`：站点入口
- `assets/`：样式、脚本、相册数据
- `地名_日期/`：每个相册的图片或视频目录
- `build-gallery.ps1`：重新生成相册数据

## 更新相册数据

如果你新增、删除或修改了相册文件夹，先在当前目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\build-gallery.ps1
```

这会刷新 `assets/gallery-data.js`。

## 发布到 GitHub Pages

1. 在 GitHub 新建一个仓库。
2. 打开当前目录终端，执行下面命令。

```powershell
git init
git branch -M main
git add .
git commit -m "Initial album site"
git remote add origin https://github.com/你的用户名/你的仓库名.git
git push -u origin main
```

3. 推送后，GitHub 会自动运行仓库里的 Pages 工作流。
4. 在 GitHub 仓库里打开 `Settings` -> `Pages`。
5. 确认 `Source` 使用 `GitHub Actions`。
6. 等待工作流完成后，网站地址通常是：

```text
https://你的用户名.github.io/你的仓库名/
```

## 说明

- 这个项目已经使用相对路径，适合直接部署到 GitHub Pages。
- 当前相册页使用 `#album=...` 哈希跳转，所以部署后不需要额外配置路由重写。
