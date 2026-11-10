#!/usr/bin/env python3
"""LumenNotes preflight for machines without Xcode.

This is intentionally *not* a compiler. It catches the low-level mistakes that
cost a full Xcode build to discover: unbalanced delimiters, invalid plists,
missing entitlement/usage strings, accidental hard-coded system font sizes and
Liquid Glass leaking into content surfaces.
"""
from __future__ import annotations

import json
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAILS: list[str] = []
CHECKS = 0


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        FAILS.append(message)
        print(f"  FAIL  {message}")
    else:
        print(f"  ok    {message}")


def strip_swift(source: str) -> str:
    """Remove comments and string literals while preserving newlines."""
    out: list[str] = []
    i = 0
    n = len(source)
    while i < n:
        c = source[i]
        if c == '"':
            triple = source.startswith('"""', i)
            quote = '"""' if triple else '"'
            out.extend("\n" * source[i:i + len(quote)].count("\n"))
            i += len(quote)
            while i < n:
                if triple and source.startswith('"""', i):
                    i += 3
                    break
                if not triple and source[i] == '"':
                    i += 1
                    break
                if source[i] == "\\":
                    i += 2
                    continue
                if source[i] == "\n":
                    out.append("\n")
                i += 1
            continue
        if source.startswith("//", i):
            while i < n and source[i] != "\n":
                i += 1
            continue
        if source.startswith("/*", i):
            depth = 1
            i += 2
            while i < n and depth:
                if source.startswith("/*", i):
                    depth += 1
                    i += 2
                elif source.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    if source[i] == "\n":
                        out.append("\n")
                    i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def balance(path: Path) -> None:
    text = strip_swift(path.read_text(encoding="utf-8"))
    pairs = {")": "(", "]": "[", "}": "{"}
    stack: list[tuple[str, int]] = []
    line = 1
    in_block_comment = False
    for ch in text:
        if ch == "\n":
            line += 1
        elif ch in "([{":
            stack.append((ch, line))
        elif ch in ")]}":
            if not stack or stack[-1][0] != pairs[ch]:
                FAILS.append(f"{path.relative_to(ROOT)}:{line} unmatched {ch}")
                return
            stack.pop()
    if stack:
        ch, line = stack[-1]
        FAILS.append(f"{path.relative_to(ROOT)}:{line} unclosed {ch}")
    else:
        global CHECKS
        CHECKS += 1
        print(f"  ok    {path.relative_to(ROOT)} delimiters balanced")


def main() -> int:
    print("== Swift delimiters")
    swift_files = sorted(ROOT.rglob("*.swift"))
    for path in swift_files:
        balance(path)

    print("\n== Property lists")
    plist_paths = [
        ROOT / "Resources/Info.plist",
        ROOT / "Resources/PrivacyInfo.xcprivacy",
        ROOT / "Resources/LumenNotes.entitlements",
        ROOT / "Resources/LumenNotesWidgets.entitlements",
        ROOT / "Resources/LumenNotesWidgets/Info.plist",
    ]
    for path in plist_paths:
        try:
            with path.open("rb") as handle:
                plistlib.load(handle)
            check(True, f"{path.relative_to(ROOT)} is valid plist")
        except Exception as exc:  # noqa: BLE001
            check(False, f"{path.relative_to(ROOT)} invalid plist: {exc}")

    print("\n== Asset catalogs")
    for path in sorted((ROOT / "Resources/Assets.xcassets").rglob("*.json")):
        try:
            json.loads(path.read_text(encoding="utf-8"))
            check(True, f"{path.relative_to(ROOT)} is valid JSON")
        except Exception as exc:  # noqa: BLE001
            check(False, f"{path.relative_to(ROOT)} invalid JSON: {exc}")

    print("\n== Info.plist privacy and integration keys")
    info_text = (ROOT / "Resources/Info.plist").read_text(encoding="utf-8")
    for key in [
        "NSFaceIDUsageDescription",
        "NSCameraUsageDescription",
        "NSMicrophoneUsageDescription",
        "NSSpeechRecognitionUsageDescription",
        "NSPhotoLibraryUsageDescription",
    ]:
        check(f"<key>{key}</key>" in info_text, f"Info.plist declares {key}")
    check("com.lumen.notes.capture" in info_text, "NSUserActivity capture type is declared")
    check("<string>lumen</string>" in info_text, "lumen:// URL scheme is registered")
    check("UIDesignRequiresCompatibility" not in info_text, "Liquid Glass compatibility opt-out is absent")
    check("NSAppTransportSecurity" not in info_text, "no ATS relaxation")

    print("\n== Font discipline")
    hardcoded = []
    for path in swift_files:
        text = path.read_text(encoding="utf-8")
        for match in re.finditer(r"\.system\(\s*size\s*:", text):
            line = text[: match.start()].count("\n") + 1
            hardcoded.append(f"{path.relative_to(ROOT)}:{line}")
    check(not hardcoded, "no hard-coded .system(size:) font calls" + (f" -> {hardcoded}" if hardcoded else ""))
    font_theme = (ROOT / "Sources/DesignSystem/FontTheme.swift").read_text(encoding="utf-8")
    check("Font.custom" in font_theme, "FontTheme uses Font.custom(_:size:relativeTo:)")
    check("fixedSize" in font_theme, "FontTheme supports fixed-size fallback")
    for family in ["SF Pro", "SF Mono", "New York", "Georgia", "Palatino", "PingFang"]:
        check(family in font_theme, f"font family {family} is offered")

    print("\n== Liquid Glass boundary")
    block_text = (ROOT / "Sources/Features/Editor/BlockViews.swift").read_text(encoding="utf-8")
    attachment_text = (ROOT / "Sources/Features/Attachments/AttachmentViews.swift").read_text(encoding="utf-8")
    check("glassEffect" not in block_text and "glassPanel" not in block_text, "editor content blocks contain no glass")
    check("glassEffect" not in attachment_text and "glassPanel" not in attachment_text, "attachment content cards contain no glass")
    glass_text = (ROOT / "Sources/DesignSystem/Glass.swift").read_text(encoding="utf-8")
    check("GlassEffectContainer" in glass_text, "GlassEffectContainer wrapper exists")
    check("ultraThinMaterial" in glass_text, "pre-iOS-26 material fallback exists")
    check("colorSchemeContrast" in glass_text, "increased-contrast fallback exists")
    check(".buttonStyle(.glass)" in glass_text, "native glass button style is used")

    print("\n== iOS 26 feature fallbacks")
    voice_text = (ROOT / "Sources/Features/Speech/VoiceRecorder.swift").read_text(encoding="utf-8")
    check("SpeechAnalyzer" in voice_text and "SFSpeechRecognizer" in voice_text, "SpeechAnalyzer with SFSpeechRecognizer fallback")
    check("if #available(iOS 26.0, *)" in voice_text, "SpeechAnalyzer is availability-gated")
    check("VNDocumentCameraViewController" in attachment_text or "VNDocumentCameraViewController" in (ROOT / "Sources/Features/Attachments/AttachmentServices.swift").read_text(encoding="utf-8"), "VisionKit document scanner is present")
    check("VNRecognizeTextRequest" in (ROOT / "Sources/Features/Attachments/AttachmentServices.swift").read_text(encoding="utf-8"), "Vision OCR is present")
    check("PKCanvasView" in (ROOT / "Sources/Features/Editor/DrawingCanvas.swift").read_text(encoding="utf-8"), "PencilKit canvas is present")
    check("PDFAnnotatorView" in (ROOT / "Sources/Features/Attachments/PDFAnnotator.swift").read_text(encoding="utf-8"), "PDF annotation layer is present")
    check("ControlWidget" in (ROOT / "Widgets/LumenNotesWidgets.swift").read_text(encoding="utf-8"), "Control Center widget is present")
    check("AppShortcutsProvider" in (ROOT / "Sources/Features/System/AppShortcuts.swift").read_text(encoding="utf-8"), "App Shortcuts provider is present")

    print("\n== Project spec")
    project = (ROOT / "project.yml").read_text(encoding="utf-8")
    check("IPHONEOS_DEPLOYMENT_TARGET: \"26.0\"" in project, "deployment target is iOS 26.0")
    check("LumenNotesWidgets" in project, "widget extension target exists")
    check("SWIFT_VERSION: \"5.0\"" in project, "Swift 5 language mode for toolchain tolerance")
    check("SWIFT_STRICT_CONCURRENCY: targeted" in project, "strict concurrency is targeted")
    check("NSExtensionPointIdentifier" in (ROOT / "Resources/LumenNotesWidgets/Info.plist").read_text(encoding="utf-8"), "widget extension point declared")

    print(f"\n{CHECKS - len(FAILS)}/{CHECKS} checks passed")
    if FAILS:
        print("\nFAILURES:")
        for failure in FAILS:
            print(f" - {failure}")
        return 1
    print("Preflight passed. This does not replace xcodebuild.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
