#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
gh_ci.py —— 把工程推到 GitHub 并触发云端 macOS 编译，最后把未签名 IPA 取回本地。

用法（在 Windows PowerShell 里）：
    $env:GITHUB_TOKEN = "ghp_xxx"
    python Tools\\gh_ci.py

环境变量：
    GITHUB_TOKEN  必填，classic PAT，需要 repo + workflow 权限
    GH_OWNER      默认 filmlab26lab
    GH_REPO       默认 filmlab
    SRC_DIR       默认本工程根目录（App/ .github/ Tools/ docs/）
    WORK_DIR      产物落地目录，默认 <SRC_DIR>\\out

依赖：仅标准库，不需要 pip 安装任何东西。
"""

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

API = "https://api.github.com"

TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()
OWNER = os.environ.get("GH_OWNER", "filmlab26lab").strip()
REPO = os.environ.get("GH_REPO", "filmlab").strip()
SRC = os.environ.get("SRC_DIR", os.path.dirname(os.path.dirname(os.path.abspath(__file__)))).strip()
WORK = os.environ.get("WORK_DIR", os.path.join(SRC, "out")).strip()
BRANCH = "main"
WORKFLOW_FILE = "build-test-ipa.yml"

# 不上传的东西：本地产物、缓存、说明性大文件不必推
SKIP_DIRS = {".git", "out", "build", "__pycache__", ".venv"}
SKIP_EXT = {".pyc", ".zip"}


def log(msg):
    print(msg, flush=True)


def api(method, path, data=None, timeout=60):
    url = API + path
    body = json.dumps(data).encode("utf-8") if data is not None else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Authorization", "token " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "filmlab-ci")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return json.loads(raw.decode("utf-8")) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        return {"_error": e.code, "_body": detail[:500]}
    except Exception as e:  # 网络问题
        return {"_error": "net", "_body": repr(e)}


def ensure_repo():
    log("== 1/4 建仓库 ==")
    me = api("GET", "/user")
    if me.get("_error"):
        log("读取当前用户失败：%s %s" % (me["_error"], me.get("_body")))
        sys.exit(2)
    login = me.get("login")
    if login and login != OWNER:
        log("警告：令牌所属账号是 %s，与 GH_OWNER=%s 不一致，改用 %s" % (login, OWNER, login))
    owner = login or OWNER

    r = api("GET", "/repos/%s/%s" % (owner, REPO))
    if r.get("_error") == 404:
        r = api("POST", "/user/repos", {
            "name": REPO,
            "private": False,
            "auto_init": False,
            "description": "FilmLab 胶片模拟 iOS 测试工程（云端 macOS 编译产出未签名 IPA）",
        })
        if r.get("_error"):
            log("建仓库失败：%s %s" % (r["_error"], r.get("_body")))
            sys.exit(3)
        log("已创建公开仓库：%s/%s" % (owner, REPO))
    elif r.get("_error"):
        log("查询仓库失败：%s %s" % (r["_error"], r.get("_body")))
        sys.exit(3)
    else:
        log("仓库已存在：%s/%s" % (owner, REPO))
    return owner


def collect_files():
    files = []
    for root, dirs, names in os.walk(SRC):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for n in names:
            ext = os.path.splitext(n)[1].lower()
            if ext in SKIP_EXT:
                continue
            full = os.path.join(root, n)
            rel = os.path.relpath(full, SRC).replace("\\", "/")
            if rel.startswith("out/"):
                continue
            files.append((rel, full))
    return files


def upload(owner):
    log("== 2/4 上传代码 ==")
    files = collect_files()
    log("共 %d 个文件" % len(files))
    ok = 0
    for rel, full in files:
        with open(full, "rb") as f:
            content = base64.b64encode(f.read()).decode("ascii")
        # 先看是否已存在（拿到 sha 才能更新）
        q = urllib.parse.quote(rel)
        existing = api("GET", "/repos/%s/%s/contents/%s" % (owner, REPO, q))
        payload = {"message": "add %s" % rel, "content": content, "branch": BRANCH}
        if isinstance(existing, dict) and existing.get("sha"):
            payload["sha"] = existing["sha"]
            payload["message"] = "update %s" % rel
        r = api("PUT", "/repos/%s/%s/contents/%s" % (owner, REPO, q), payload)
        if r.get("_error"):
            log("  上传失败 %s -> %s %s" % (rel, r["_error"], r.get("_body")))
        else:
            ok += 1
            log("  ok  %s" % rel)
    log("上传成功 %d/%d" % (ok, len(files)))
    return ok


BASE_ID = 0  # 触发前已有的最大 run id：只认比它新的，避免把上一次的旧结论当成这一次的


def trigger(owner):
    global BASE_ID
    log("== 3/4 触发云端编译 ==")
    runs = api("GET", "/repos/%s/%s/actions/workflows/%s/runs?per_page=10" % (owner, REPO, WORKFLOW_FILE))
    BASE_ID = max([r["id"] for r in runs.get("workflow_runs", [])], default=0)
    log("  基线 run id = %s" % BASE_ID)
    repo_info = api("GET", "/repos/%s/%s" % (owner, REPO))
    default_branch = repo_info.get("default_branch") or "main"
    r = api("POST", "/repos/%s/%s/actions/workflows/%s/dispatches" % (owner, REPO, WORKFLOW_FILE),
            {"ref": default_branch})
    if r.get("_error"):
        log("触发失败：%s %s" % (r["_error"], r.get("_body")))
        log("（若提示 workflow 不存在，通常是默认分支还不是 %s，或 Actions 未启用）" % default_branch)
        sys.exit(4)
    log("已触发，默认分支 %s" % default_branch)
    return default_branch


def wait_run(owner, branch, timeout_min=25):
    log("== 4/4 等待编译并取回 IPA ==")
    deadline = time.time() + timeout_min * 60
    run_id = None
    while time.time() < deadline:
        runs = api("GET", "/repos/%s/%s/actions/runs?per_page=10&branch=%s" % (owner, REPO, branch))
        if runs.get("_error"):
            log("查询运行记录失败：%s" % runs.get("_body"))
        else:
            items = [x for x in runs.get("workflow_runs", []) if x["id"] > BASE_ID]
            if items:
                run_id = items[0]["id"]
                st, concl = items[0]["status"], items[0]["conclusion"]
                log("  运行 #%s 状态=%s 结论=%s" % (run_id, st, concl))
                if st == "completed":
                    if concl != "success":
                        log("编译失败（结论=%s）。请到 Actions 页面看红色日志。" % concl)
                        return None
                    return run_id
        time.sleep(20)
    log("等待超时，到 https://github.com/%s/%s/actions 看看" % (owner, REPO))
    return None


def fetch_artifact(owner, run_id):
    arts = api("GET", "/repos/%s/%s/actions/runs/%s/artifacts" % (owner, REPO, run_id))
    if arts.get("_error") or not arts.get("artifacts"):
        log("没找到产物：%s" % arts.get("_body", arts))
        return None
    art = arts["artifacts"][0]
    log("产物：%s (%s bytes)" % (art["name"], art["size_in_bytes"]))
    url = "%s/repos/%s/%s/actions/artifacts/%s/zip" % (API, owner, REPO, art["id"])
    req = urllib.request.Request(url, method="GET")
    req.add_header("Authorization", "token " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "filmlab-ci")

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *_a, **_k):
            return None

    opener = urllib.request.build_opener(NoRedirect)
    try:
        opener.open(req, timeout=60)
        log("没有拿到重定向地址（异常）")
        return None
    except urllib.error.HTTPError as e:
        if e.code in (301, 302, 303, 307, 308):
            signed = e.headers["Location"]
        else:
            log("下载产物失败 %s %s" % (e.code, e.read()[:200]))
            return None
    # 签名地址不需要 Authorization
    with urllib.request.urlopen(signed, timeout=300) as r:
        data = r.read()
    if not os.path.isdir(WORK):
        os.makedirs(WORK)
    zpath = os.path.join(WORK, "artifact.zip")
    with open(zpath, "wb") as f:
        f.write(data)
    log("已下载 %s (%d bytes)" % (zpath, len(data)))
    ipa = None
    with zipfile.ZipFile(zpath) as z:
        for name in z.namelist():
            if name.lower().endswith(".ipa"):
                z.extract(name, WORK)
                ipa = os.path.join(WORK, os.path.basename(name))
                break
    return ipa


def main():
    if not TOKEN:
        log("缺少环境变量 GITHUB_TOKEN")
        sys.exit(1)
    owner = ensure_repo()
    if upload(owner) == 0:
        log("一个文件都没传上去，中止")
        sys.exit(5)
    branch = trigger(owner)
    run_id = wait_run(owner, branch)
    if not run_id:
        sys.exit(6)
    ipa = fetch_artifact(owner, run_id)
    if ipa:
        log("")
        log("完成：%s" % ipa)
    else:
        log("没取到 IPA")


if __name__ == "__main__":
    main()
