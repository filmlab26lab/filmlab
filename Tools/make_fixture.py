# 生成一个自测用的假 IPA，用来验证 ipa_check.py 的解析逻辑有没有写错。
# 它只用于工具自检，不是能装的包。
#
# 用法： python make_fixture.py

import os
import plistlib
import struct
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "_fixture")
OUT_IPA = os.path.join(OUT_DIR, "DemoFixture.ipa")

MH_MAGIC_64 = 0xFEEDFACF
LC_ENCRYPTION_INFO_64 = 0x2C
CPU_TYPE_ARM64 = 0x0100000C


def build_minimal_macho(cryptid=0):
    """造一个只有 header + LC_ENCRYPTION_INFO_64 的 arm64 Mach-O（够解析器跑通）"""
    header_size = 32
    cmd_size = 24  # encryption_info_64: cmd(4)+cmdsize(4)+cryptoff(4)+cryptsize(4)+cryptid(4)+pad(4)
    header = struct.pack(
        "<IiiIIIII",
        MH_MAGIC_64, CPU_TYPE_ARM64, 0, 2,  # magic, cputype, cpusubtype, filetype(2=execute)
        1, cmd_size, 0, 0
    )
    cmd = struct.pack("<IIIIII", LC_ENCRYPTION_INFO_64, cmd_size, 0, 0, cryptid, 0)
    return header + cmd + b"\x00" * 32


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    app = "Payload/DemoFixture.app"
    info = {
        "CFBundleIdentifier": "com.filmlab.demo.fixture",
        "CFBundleName": "DemoFixture",
        "CFBundleDisplayName": "体检样例",
        "CFBundleExecutable": "DemoFixture",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "1",
        "MinimumOSVersion": "17.0",
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "UIDeviceFamily": [1, 2],
    }
    with zipfile.ZipFile(OUT_IPA, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(app + "/Info.plist", plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
        zf.writestr(app + "/DemoFixture", build_minimal_macho(cryptid=0))
        zf.writestr(app + "/Assets.car", b"\x00" * 16)
    print("已生成：%s" % OUT_IPA)


if __name__ == "__main__":
    main()
