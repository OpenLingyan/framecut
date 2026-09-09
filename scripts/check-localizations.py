#!/usr/bin/env python3
"""Validate language catalogs and prevent common untranslated UI regressions."""

import json
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parent.parent
LANGUAGES = ("en", "zh-Hans")
TOKEN = re.compile(r"\{(\d+)\}")


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def read_catalog(path):
    source = path.read_text(encoding="utf-8")
    keys = re.findall(r'^\s*"([^"\n]+)"\s*=', source, re.MULTILINE)
    require(len(keys) == len(set(keys)), f"Duplicate keys in {path.relative_to(ROOT)}")
    values = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)]))
    require(values and all(isinstance(value, str) and value.strip() for value in values.values()),
            f"Empty or invalid translations in {path.relative_to(ROOT)}")
    return values


def check():
    catalogs = {
        language: read_catalog(ROOT / f"Sources/FrameCut/Resources/{language}.lproj/Localizable.strings")
        for language in LANGUAGES
    }
    reference = catalogs["en"]
    for language, values in catalogs.items():
        require(set(values) == set(reference), f"Language keys differ: {language}")
        for key, value in values.items():
            tokens = sorted(TOKEN.findall(value))
            require(tokens == sorted(TOKEN.findall(reference[key])),
                    f"Placeholders differ: {language}/{key}")
            indexes = {int(token) for token in tokens}
            require(not indexes or indexes == set(range(max(indexes) + 1)),
                    f"Non-contiguous placeholders: {language}/{key}")

    for path in (ROOT / "Sources/FrameCut").rglob("*.swift"):
        source = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT)
        for key in re.findall(r'L10n\.(?:text|format)\(\s*"([^"\n]+)"', source):
            require(key in reference, f"Unknown localization key in {relative}: {key}")
        for line_number, line in enumerate(source.splitlines(), 1):
            if line.lstrip().startswith("//"):
                continue
            require(not re.search(r"[\u3400-\u4dbf\u4e00-\u9fff]", line),
                    f"Move Chinese UI text to a language catalog: {relative}:{line_number}")
            require(not re.search(
                r'(?:Text|Label|Button|Picker|CommandMenu|Section)\(\s*"|'
                r'\.(?:help|accessibilityLabel|navigationTitle)\(\s*"|'
                r'panel\.(?:title|message|prompt)\s*=\s*"', line),
                f"Use L10n for displayed text: {relative}:{line_number}")

    native_catalogs = [read_catalog(ROOT / f"Resources/{language}.lproj/InfoPlist.strings")
                       for language in LANGUAGES]
    require(set(native_catalogs[0]) == set(native_catalogs[1]), "Native app localization keys differ")
    print(f"Localization checks passed: {len(reference)} strings per language ({', '.join(LANGUAGES)}).")


if __name__ == "__main__":
    check()
