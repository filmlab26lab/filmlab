#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
gh_wait.py —— 只做三件事：把（改过的）workflow 推上去 → 触发 → 等编译完成并把 IPA 拉回本地。

    $env:GITHUB_TOKEN = "ghp_xxx"
    python Tools\\gh_wait.py

适用于已经上传过代码、只想重跑一次编译的场景（修了代码/改了 YAML 之后用）。
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
WORK = os.path.join(SRC, "out")
WF_REL = ".github/workflows/build-test-ipa.yml"
WF_NAME = "build-test-ipa.yml"


def api(method, path, data=None, timeout=60):
    body = json.dumps(data).encode("utf-8") if data is not None else None
    req = urllib.request.Request(API + path, data=body, method=method)
    req.add_header("Authorization", "token " + TOKEN)
    req.add_header("User-Agent", "filmlab-ci")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        raw = urllib.request.urlopen(req, timeout=timeout).read().decode("utf-8")
        return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return {"_error": e.code, "_body": e.read().decode("utf-8", "replace")[:400]}


def push_workflow():
    local = os.path.join(SRC, WF_REL.replace("/", os.sep))
    with open(local, "rb") as f:
        content = base64.b64encode(f.read()).decode("ascii")
    q = urllib_request_quote(WF_REL)
    existing = api("GET", "/repos/%s/%s/contents/%s" % (OWNER, REPO, q))
    payload = {"message": "fix ci: use macos-latest (macos-14 retired)", "content": content, "branch": "main"}
    if isinstance(existing, dict) and existing.get("sha"):
        payload["sha"] = existing["sha"]
    r = api("PUT", "/repos/%s/%s/contents/%s" % (OWNER, REPO, q), payload)
    if r.get("_error"):
        print("推送 workflow 失败：", r["_error"], r.get("_body"), flush=True)
        sys.exit(2)
    print("workflow 已更新：", r.get("commit", {}).get("sha"), flush=True)


def urllib_request_quote(s):
    return urllib.parse.quote(s)


BASE_ID = 0  # 触发前已有的最大 run id；只认比它新的运行，避免把上一次的旧结果当成这次的


def trigger():
    global BASE_ID
    runs = api("GET", "/repos/%s/%s/actions/workflows/%s/runs?per_page=10" % (OWNER, REPO, WF_NAME))
    items = runs.get("workflow_runs", [])
    BASE_ID = max([r["id"] for r in items], default=0)
    print("基线 run id =", BASE_ID, flush=True)
    r = api("POST", "/repos/%s/%s/actions/workflows/%s/dispatches" % (OWNER, REPO, WF_NAME), {"ref": "main"})
    if r.get("_error"):
        print("触发失败：", r["_error"], r.get("_body"), flush=True)
        sys.exit(3)
    print("已触发编译", flush=True)


def wait(timeout_min=30):
    deadline = time.time() + timeout_min * 60
    last = None
    while time.time() < deadline:
        runs = api("GET", "/repos/%s/%s/actions/workflows/%s/runs?per_page=10&branch=main" % (OWNER, REPO, WF_NAME))
        items = [r for r in runs.get("workflow_runs", []) if r["id"] > BASE_ID]
        if items:
            r = items[0]
            cur = (r["status"], r["conclusion"])
            if cur != last:
                print("  运行 #%s %s/%s" % (r["id"], r["status"], r["conclusion"]), flush=True)
                last = cur
            if r["status"] == "completed":
                return (r["id"], r["conclusion"]) if r["conclusion"] == "success" else (None, r["conclusion"])
        time.sleep(15)
    return (None, "timeout")


def fetch(run_id):
    arts = api("GET", "/repos/%s/%s/actions/runs/%s/artifacts" % (OWNER, REPO, run_id))
    if arts.get("_error") or not arts.get("artifacts"):
        print("没有产物：", arts, flush=True)
        return None
    a = arts["artifacts"][0]
    url = "%s/repos/%s/%s/actions/artifacts/%s/zip" % (API, OWNER, REPO, a["id"])
    req = urllib.request.Request(url, method="GET")
    req.add_header("Authorization", "token " + TOKEN)
    req.add_header("User-Agent", "filmlab-ci")

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *_a, **_k):
            return None

    try:
        urllib.request.build_opener(NoRedirect).open(req, timeout=60)
        return None
    except urllib.error.HTTPError as e:
        if e.code not in (301, 302, 303, 307, 308):
            print("下载失败：", e.code, flush=True)
            return None
        signed = e.headers["Location"]
    os.makedirs(WORK, exist_ok=True)
    zpath = os.path.join(WORK, "artifact.zip")
    with urllib.request.urlopen(signed, timeout=300) as r, open(zpath, "wb") as f:
        f.write(r.read())
    print("下载完成：", zpath, os.path.getsize(zpath), "bytes", flush=True)
    ipa = None
    with zipfile.ZipFile(zpath) as z:
        for n in z.namelist():
            if n.lower().endswith(".ipa"):
                z.extract(n, WORK)
                ipa = os.path.join(WORK, os.path.basename(n))
    return ipa


def main():
    if not TOKEN:
        print("缺少 GITHUB_TOKEN")
        sys.exit(1)
    push_workflow()
    trigger()
    run_id, concl = wait()
    if not run_id:
        print("编译没成功，结论 =", concl)
        print("去这里看日志：https://github.com/%s/%s/actions" % (OWNER, REPO))
        sys.exit(4)
    ipa = fetch(run_id)
    print("IPA:", ipa if ipa else "未取到")


if __name__ == "__main__":
    main()
