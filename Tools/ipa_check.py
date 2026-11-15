#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ipa_check.py —— IPA 体检工具（Windows / macOS 都能跑，只需要 Python 3.8+）

它是干什么的
    在把任何 .ipa 往手机上装之前，先花 3 秒把它拆开看清楚：
      · 包结构对不对（Payload/*.app 是不是真的应用包）
      · Bundle ID / 版本 / 最低系统版本 / 支持设备
      · 二进制有没有被 App Store 加密（加密包重签后一定启动不了）
      · 里面带没带描述文件、描述文件绑了哪些 UDID、什么时候到期
      · 有没有签名（_CodeSignature）

为什么需要它
    重签失败的 90% 原因，在装之前就能查出来：加密包、缺描述文件、描述文件没绑你的 UDID、
    最低系统版本高于手机系统。做成脚本，是因为每次上包都该查一遍。

用法
    python ipa_check.py "C:\\path\\app.ipa"
    python ipa_check.py "app.ipa" --udid 00008120-001A7016XXXXXXXX --ios-version 26.7.3
    python ipa_check.py "app.ipa" --json            # 额外输出 JSON

退出码
    0 通过   1 有阻塞项（装上大概率起不来）   2 参数/读文件出错
"""

import argparse
import json
import os
import plistlib
import struct
import sys
import zipfile

LC_ENCRYPTION_INFO = 0x21
LC_ENCRYPTION_INFO_64 = 0x2C
MH_MAGIC = 0xFEEDFACE
MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF

CPU_TYPE_ARM = 12
CPU_TYPE_ARM64 = 0x0100000C
CPU_TYPE_X86 = 7
CPU_TYPE_X86_64 = 0x01000007


def cpu_name(cputype, cpusubtype):
    subtype = cpusubtype & 0x00FFFFFF
    if cputype == CPU_TYPE_ARM64:
        return "arm64e" if subtype == 2 else "arm64"
    if cputype == CPU_TYPE_ARM:
        return "armv7(s)" if subtype == 9 else "armv7"
    if cputype == CPU_TYPE_X86_64:
        return "x86_64"
    if cputype == CPU_TYPE_X86:
        return "i386"
    return "cputype=0x%X" % cputype


def _parse_thin(data, offset):
    """解析单个 Mach-O 切片，返回 (架构名, cryptid 或 None)"""
    if offset + 28 > len(data):
        return None
    magic = struct.unpack_from("<I", data, offset)[0]

    if magic == MH_MAGIC_64:
        _, cputype, cpusubtype, _filetype, ncmds, _sizeofcmds, _flags, _rsv = \
            struct.unpack_from("<IiiIIIII", data, offset)
        cmd_off = offset + 32
    elif magic == MH_MAGIC:
        _, cputype, cpusubtype, _filetype, ncmds, _sizeofcmds, _flags = \
            struct.unpack_from("<IiiIIII", data, offset)
        cmd_off = offset + 28
    else:
        return None

    cryptid = None
    for _ in range(ncmds):
        if cmd_off + 8 > len(data):
            break
        cmd, cmdsize = struct.unpack_from("<II", data, cmd_off)
        if cmd in (LC_ENCRYPTION_INFO, LC_ENCRYPTION_INFO_64) and cmdsize >= 20:
            cryptid = struct.unpack_from("<I", data, cmd_off + 16)[0]
        if cmdsize <= 0:
            break
        cmd_off += cmdsize

    return cpu_name(cputype, cpusubtype), cryptid


def macho_slices(data):
    """返回 [(架构, cryptid)]，兼容 FAT 与单架构二进制"""
    if not data:
        return []
    magic_be = struct.unpack_from(">I", data, 0)[0]
    slices = []

    if magic_be in (FAT_MAGIC, FAT_MAGIC_64):
        nfat = struct.unpack_from(">I", data, 4)[0]
        is64 = magic_be == FAT_MAGIC_64
        for i in range(nfat):
            try:
                if is64:
                    _ct, _cst, off, _size, _al, _rsv = struct.unpack_from(">iIQQII", data, 8 + i * 32)
                else:
                    _ct, _cst, off, _size, _al = struct.unpack_from(">iIIII", data, 8 + i * 20)
            except struct.error:
                break
            parsed = _parse_thin(data, off)
            if parsed:
                slices.append(parsed)
        return slices

    parsed = _parse_thin(data, 0)
    return [parsed] if parsed else []


def extract_profile_plist(raw):
    """从 .mobileprovision（CMS 签名容器）里抠出 XML plist 段"""
    start = raw.find(b"<?xml")
    end = raw.find(b"</plist>")
    if start == -1 or end == -1:
        return None
    try:
        return plistlib.loads(raw[start:end + len(b"</plist>")])
    except Exception:
        return None


def fmt_size(num):
    for unit in ("B", "KB", "MB", "GB"):
        if num < 1024 or unit == "GB":
            return "%.1f %s" % (num, unit) if unit != "B" else "%d B" % num
        num /= 1024.0
    return "%d B" % num


def check_ipa(path, device_udid=None, device_ios=None):
    result = {"file": os.path.abspath(path), "problems": [], "warnings": [], "ok": True}
    try:
        zf = zipfile.ZipFile(path)
    except Exception as exc:
        result["ok"] = False
        result["problems"].append("打不开这个包：%s" % exc)
        return result

    names = zf.namelist()
    app_dirs = sorted({n.split("/")[1] for n in names
                       if n.startswith("Payload/") and n.count("/") >= 2 and n.split("/")[1].endswith(".app")})
    if not app_dirs:
        result["ok"] = False
        result["problems"].append("包结构不对：根目录下没有 Payload/*.app（这不是一个标准 IPA）")
        return result

    app_dir = "Payload/" + app_dirs[0]
    result["app_bundle"] = app_dir
    if len(app_dirs) > 1:
        result["warnings"].append("包里有多个 .app（%s），只检查第一个" % ", ".join(app_dirs))

    # ---- Info.plist ----
    info = {}
    info_name = app_dir + "/Info.plist"
    if info_name in names:
        try:
            info = plistlib.loads(zf.read(info_name))
        except Exception as exc:
            result["warnings"].append("Info.plist 解析失败：%s" % exc)
    else:
        result["problems"].append("找不到 Info.plist")

    result["bundle_id"] = info.get("CFBundleIdentifier")
    result["app_name"] = info.get("CFBundleDisplayName") or info.get("CFBundleName")
    result["version"] = "%s (build %s)" % (info.get("CFBundleShortVersionString", "?"),
                                          info.get("CFBundleVersion", "?"))
    result["min_os"] = info.get("MinimumOSVersion")
    result["platforms"] = info.get("CFBundleSupportedPlatforms")
    family = info.get("UIDeviceFamily")
    result["device_family"] = {1: "iPhone", 2: "iPad", 3: "Apple TV"}.get(
        family[0], "未知") if isinstance(family, list) and family else "未知"

    # ---- 二进制加密状态 ----
    exe = info.get("CFBundleExecutable")
    slices = []
    if exe:
        exe_path = "%s/%s" % (app_dir, exe)
        if exe_path in names:
            try:
                slices = macho_slices(zf.read(exe_path))
            except Exception as exc:
                result["warnings"].append("读主二进制失败：%s" % exc)
        else:
            result["problems"].append("找不到可执行文件 %s" % exe)
    archs = [s[0] for s in slices]
    cryptids = [s[1] for s in slices if s[1] is not None]
    result["architectures"] = archs
    encrypted = any(c != 0 for c in cryptids)
    result["encrypted"] = encrypted if cryptids else None
    if encrypted:
        result["problems"].append("二进制是 App Store 加密过的（cryptid=%s），重签后启动必闪退；"
                                  "需要先脱壳的版本" % ", ".join(str(c) for c in cryptids))
    if archs and not any(a.startswith("arm64") for a in archs):
        result["problems"].append("二进制里没有 arm64 切片（%s），真机上跑不了" % ", ".join(archs))

    # ---- 描述文件 ----
    result["has_profile"] = False
    profile_path = app_dir + "/embedded.mobileprovision"
    if profile_path in names:
        raw = zf.read(profile_path)
        pl = extract_profile_plist(raw)
        if pl:
            result["has_profile"] = True
            result["profile"] = {
                "name": pl.get("Name"),
                "team": pl.get("TeamName") or pl.get("TeamIdentifier"),
                "expires": pl.get("ExpirationDate").strftime("%Y-%m-%d %H:%M")
                if pl.get("ExpirationDate") else None,
                "device_count": len(pl.get("ProvisionedDevices") or []),
                "udid_match": None,
                "provisions_all_devices": pl.get("ProvisionsAllDevices", False),
            }
            devices = pl.get("ProvisionedDevices") or []
            if device_udid:
                result["profile"]["udid_match"] = device_udid.upper() in [d.upper() for d in devices]
                if not result["profile"]["udid_match"] and not pl.get("ProvisionsAllDevices"):
                    result["problems"].append("描述文件里没有你这台设备的 UDID，装不上")
            ent = pl.get("Entitlements") or {}
            result["profile"]["app_id"] = ent.get("application-identifier")
            result["profile"]["get_task_allow"] = ent.get("get-task-allow")
            if pl.get("ExpirationDate"):
                import datetime
                if pl["ExpirationDate"] < datetime.datetime.now():
                    result["problems"].append("描述文件已经过期，需要重新签")
        else:
            result["warnings"].append("有 embedded.mobileprovision，但没能解出 plist（可能是新版 CMS 封装）")

    if not result["has_profile"]:
        result["warnings"].append("包内没有描述文件 —— 正常，说明必须自己签（Apple ID 免证书或证书签名）")

    # ---- 签名 ----
    result["signed"] = (app_dir + "/_CodeSignature/CodeResources") in names
    if not result["signed"]:
        result["warnings"].append("没有 _CodeSignature —— 未签名包，必须签完才能装")

    # ---- 系统版本核对 ----
    if device_ios and result["min_os"]:
        try:
            if tuple(int(x) for x in device_ios.split(".")[:2]) < \
               tuple(int(x) for x in str(result["min_os"]).split(".")[:2]):
                result["problems"].append("最低系统要求 iOS %s，比手机上的 %s 高"
                                          % (result["min_os"], device_ios))
        except ValueError:
            pass

    # ---- 体积 / 组件 ----
    result["ipa_size"] = fmt_size(os.path.getsize(path))
    result["frameworks"] = len([n for n in names if n.startswith(app_dir + "/Frameworks/") and n.endswith(".framework/")])
    result["extensions"] = len([n for n in names if n.startswith(app_dir + "/PlugIns/") and n.endswith(".appex/")])
    result["has_assets"] = (app_dir + "/Assets.car") in names

    result["ok"] = not result["problems"]
    return result


def print_report(r):
    line = "─" * 62
    print(line)
    print(" IPA 体检报告")
    print(line)
    print(" 文件        : %s" % r["file"])
    if "app_bundle" in r:
        print(" 应用包      : %s" % r["app_bundle"])
    print(" 应用名      : %s" % (r.get("app_name") or "-"))
    print(" Bundle ID   : %s" % (r.get("bundle_id") or "-"))
    print(" 版本        : %s" % (r.get("version") or "-"))
    print(" 最低系统    : iOS %s" % (r.get("min_os") or "-"))
    print(" 设备类型    : %s" % (r.get("device_family") or "-"))
    print(" 架构        : %s" % (", ".join(r.get("architectures") or []) or "未识别"))
    enc = r.get("encrypted")
    print(" 加密状态    : %s" % ("已加密（重签也起不来）" if enc else
                                ("未加密，可以重签" if enc is False else "未能判断")))
    if r.get("has_profile") and r.get("profile"):
        p = r["profile"]
        print(" 描述文件    : %s" % (p.get("name") or "-"))
        print(" 团队        : %s" % (p.get("team") or "-"))
        print(" 到期时间    : %s" % (p.get("expires") or "-"))
        print(" 绑定设备数  : %s%s" % (p.get("device_count"),
                                    "" if p.get("udid_match") is None
                                    else ("（含本机：是）" if p["udid_match"] else "（含本机：否）")))
        print(" App ID      : %s" % (p.get("app_id") or "-"))
    else:
        print(" 描述文件    : 无（需自签名）")
    print(" 已签名      : %s" % ("是" if r.get("signed") else "否"))
    print(" 包体积      : %s" % r.get("ipa_size"))
    print(" 内嵌框架    : %s 个    扩展(Appex): %s 个" %
          (r.get("frameworks"), r.get("extensions")))
    print(line)
    if r["problems"]:
        print(" 阻塞项（不解决就装不上或打不开）：")
        for p in r["problems"]:
            print("   ✗ %s" % p)
    if r["warnings"]:
        print(" 提示（不影响安装，需要知道）：")
        for w in r["warnings"]:
            print("   · %s" % w)
    print(line)
    print(" 结论：%s" % ("通过，可以直接进入签名/安装流程" if r["ok"]
                        else "不通过，先解决上面的阻塞项"))
    print(line)


def main():
    ap = argparse.ArgumentParser(description="IPA 体检工具：装之前先查清楚包是什么、缺什么")
    ap.add_argument("ipa", help="要检查的 .ipa 文件路径")
    ap.add_argument("--udid", help="目标设备的 UDID，用来核对描述文件是否绑了这台机器")
    ap.add_argument("--ios-version", dest="ios_version", help="目标设备系统版本，例如 26.7.3")
    ap.add_argument("--json", action="store_true", help="同时输出 JSON")
    ap.add_argument("--report", help="把文本报告另存到这个路径")
    args = ap.parse_args()

    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    if not os.path.isfile(args.ipa):
        print("找不到文件：%s" % args.ipa)
        return 2

    result = check_ipa(args.ipa, args.udid, args.ios_version)
    print_report(result)

    text = json.dumps(result, ensure_ascii=False, indent=2, default=str)
    if args.json:
        print(text)

    if args.report:
        with open(args.report, "w", encoding="utf-8") as fh:
            fh.write(text)

    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
