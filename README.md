# 拾光 · 班级纪念馆（手机部署版）

这是一个无需 npm 构建的静态网站起步项目：`index.html` 是网站本体，`supabase/schema.sql` 是数据库和权限规则。采用玻璃拟态渐变视觉、注册/登录、个人资料、私密照片上传、隐私开关、公开同学列表与基础管理员用户限制功能。

## 免费服务
- Supabase Free：账号认证、Postgres 数据库、照片存储。免费套餐额度会变化，项目可能在一段时间不活跃后暂停；请以官方套餐页面为准。
- Cloudflare Pages：免费托管静态网页，提供 `*.pages.dev` 网址。
- 不需要购买域名。免费额度内可零成本试运行。

## 第 1 步：创建 Supabase 项目
1. 在手机浏览器打开 https://supabase.com/ 并注册。
2. 创建一个新项目，记好数据库密码（不要发给别人）。
3. 打开项目的 **SQL Editor**，新建查询。
4. 打开本项目 `supabase/schema.sql`，复制全部内容粘贴进去并运行。
5. 进入 **Project Settings → API**（或 Connect 页面），复制 **Project URL** 与 **anon/public key**。不要复制 `service_role` 或 secret key。

## 第 2 步：配置网站
1. 用手机文本编辑器打开 `index.html`。
2. 找到：
   - `const SUPABASE_URL = "PASTE_SUPABASE_PROJECT_URL";`
   - `const SUPABASE_ANON_KEY = "PASTE_SUPABASE_ANON_KEY";`
3. 将两个占位内容分别替换为你的 Project URL 与 anon/public key，保留引号。
4. 保存文件。不要把数据库密码、service_role key、邮箱密码放进 HTML。

## 第 3 步：创建首个管理员
1. 先通过网站注册你自己的账号并完成邮箱验证（如果开启）。
2. 在 Supabase 打开 **Authentication → Users**，找到自己的用户 UUID。
3. 回到 SQL Editor，运行下面的语句，把 UUID 替换成自己的真实 UUID：

```sql
update public.profiles
set is_admin = true
where id = '把你的用户UUID粘贴在这里';
```

管理员角色只能由数据库管理者设置，不允许普通用户在网页上自行提权。不要把管理员账号借给别人。

## 第 4 步：部署到 Cloudflare Pages（手机浏览器）
1. 打开 https://dash.cloudflare.com/ 并注册/登录。
2. 进入 **Workers & Pages**，选择创建应用/Pages，并选择 **Direct Upload / Drag and drop**（界面名称可能变化）。
3. 本项目部署时只需要上传网站文件 `index.html`。如果页面只接受 ZIP，可创建一个仅包含 `index.html` 的 ZIP 文件并上传；不要把 README 或 SQL 文件当网站首页。
4. 部署成功后会得到 `https://你的项目名.pages.dev` 形式的网址。
5. 用手机无痕窗口打开网址，测试注册、邮箱确认、登录、编辑资料、公开主页和照片上传。

官方说明：https://developers.cloudflare.com/pages/get-started/direct-upload/

## 第 5 步：配置 Supabase Auth
1. Supabase → Authentication → URL Configuration。
2. 把 Cloudflare 的公开网址添加为 Site URL / Redirect URL（按控制台提示填写）。
3. 测试注册邮件。如果收不到邮件，检查垃圾邮件；公开使用前应配置好邮箱验证与邮件发送设置。

## 当前功能
- 邮箱注册和登录；登录态同步。
- 个人资料：昵称、年龄、性格、个人介绍、主题风格。
- 个人主页公开/私密切换，以及年龄、性格、介绍、头像逐项公开设置。
- 私有 Storage 桶；照片按账号 UUID 路径上传，使用限时签名链接显示。
- 同学公开档案卡片、搜索、弹窗个人资料动画。
- 管理员可查看用户列表并通过安全 RPC 限制/解除限制账号。
- 数据库 RLS、公开资料安全视图、图片访问策略。

## 重要限制与上线前检查
- 这是可运行的初始版本，不是经过第三方安全审计的正式产品。先用测试账号验证，确认 SQL 全部成功后再邀请同学。
- 首版管理员可以查看用户列表并限制账号，但尚未实现完整的举报工单、公告发布、批量审核或个人主页布局编辑器。
- 页面当前只显示个人头像照片；照片墙/多张相册可作为下一版扩展。
- 个人资料默认私密；公开资料只允许登录用户查看。不要把学生敏感信息、家庭住址、电话号码等上传。
- 免费服务的额度、暂停规则、可用区域可能变化。查看 https://supabase.com/pricing 与 Cloudflare 官方文档。
- 如果 SQL 运行失败，不要反复运行不清楚的修改语句；先保存错误信息并排查。
