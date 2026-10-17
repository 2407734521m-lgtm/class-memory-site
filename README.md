# 我们的班级 · 青春档案（v2 手机部署版）

无需 npm 构建的完整应用：`index.html` 是网站本体（单文件前端），`supabase/schema.sql` 是数据库、权限规则与安全视图。后端是 Supabase（真实注册登录、Postgres 数据库、行级权限），前端是 GitHub Pages 托管的静态页面。

## 功能总览

- 用户名+密码注册/登录（首位注册者自动成为超级管理员），登录态保持、退出、封号拦截
- 班级成员照片卡片墙，支持按名字/用户名/性格搜索
- 点击成员卡片 → 照片 FLIP 共享元素过渡动画进入个人档案（500-800ms，GPU 加速，返回反向动画）
- 个人档案：照片位置自由设计（左/右/居中/全屏背景）、7 种主题（含自定义颜色）
- 档案字段：名字、年龄、性格、个性签名、简介、照片（链接）、爱好、联系方式、社交账号
- 隐私设置：每个公开字段单独开关；联系方式/社交账号永不公开
- 青春时间线：日期/标题/文字/图片/视频，按年份分组展示
- 班级相册：分类（日常/军训/运动会/春游/聚会/毕业/自定义）、瀑布流、全屏查看（支持滑动切换）
- 班级动态：发布文字+图片、点赞、评论、回复，管理员可删除
- 管理后台：用户管理（查看/禁用/删除/任免管理员）、内容管理（公告/动态/评论/相册）、网站设置（班级名称/介绍/邀请码）
- 三级权限：超级管理员 > 管理员 > 普通成员
- 手机端优先：无横向滚动、大按钮、底部导航；桌面端三列自适应

## 第 1 步：创建 Supabase 项目

1. 在手机浏览器打开 https://supabase.com/ ，用 GitHub 账号登录最省事。
2. New project 新建项目：Name 填 `class-memory`，Database Password 自己设一个并记好（不要发给别人），Region 选 Northeast Asia (Tokyo)，免费计划，Create new project，等一两分钟。
3. **关闭邮箱验证**：左侧 Authentication → Providers → Email → 把 "Confirm email" 关掉。本站用用户名+密码注册，开邮箱验证会导致无法登录。
4. 打开项目的 **SQL Editor**，New query 新建查询。
5. 打开本项目 `supabase/schema.sql`（或仓库页面上的同名文件），复制全部内容粘贴进去并 **Run** 运行，看到 Success 即可。如果之前跑过 v1 的 SQL，直接再跑一遍本文件即可升级。
6. 进入 **Project Settings → API**，复制 **Project URL** 与 **anon / public key**。不要复制 `service_role` 或 secret key。

## 第 2 步：配置网站

网站里的两个占位符需要填上才能连上数据库：

- `const SUPABASE_URL = "PASTE_SUPABASE_PROJECT_URL";`
- `const SUPABASE_ANON_KEY = "PASTE_SUPABASE_ANON_KEY";`

把 Project URL 和 anon key 发给管理员（就是我），我来填好重新部署。anon key 设计上就是公开的（本来就要嵌在网页里），直接贴聊天里就行。

## 第 3 步：成为超级管理员

1. 打开网站，注册第一个账号（用户名+密码）。**第一位注册的同学会自动成为超级管理员**。
2. 超管登录后，底部导航会出现「管理」入口，可以任免管理员、禁用用户、管理公告/相册/动态、设置班级邀请码。

## 第 4 步：Supabase Auth 跳转配置（可选）

本站使用用户名+密码（内部映射合成邮箱），不依赖邮件验证，此步可跳过。如需开启邮箱相关功能，再去 Authentication → URL Configuration 把网站地址加为 Site URL / Redirect URL。

## 部署

- 本仓库已开启 GitHub Pages，`index.html` 在 main 分支根目录即自动上线：https://2407734521m-lgtm.github.io/class-memory-site/
- 每次更新 `index.html` 后推送到 main 分支，1-2 分钟自动重新部署。

## 重要限制与上线前检查

- 这是可运行的版本，不是经过第三方安全审计的正式产品。先用测试账号走完注册→建档→发动态→管理后台全流程，确认 SQL 全部成功后再邀请同学。
- 字段级隐私通过 `public_profiles` 安全视图 + 应用层共同保证；联系方式/社交账号从不进入公开视图。
- 照片目前只支持图片链接（图床直链）。本地上传/云存储为后续扩展。
- 不要把学生敏感信息、家庭住址、电话号码等上传到公开字段。
- 免费服务的额度、暂停规则、可用区域可能变化，以 https://supabase.com/pricing 与 GitHub Pages 官方文档为准。
