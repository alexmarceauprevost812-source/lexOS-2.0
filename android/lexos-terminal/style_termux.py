#!/usr/bin/env python3
"""Style de la source Termux. Ne change ni package, ni bootstrap, ni permissions."""
import sys
from pathlib import Path
import xml.etree.ElementTree as ET


def once(src, old, new, file):
    if src.count(old) != 1:
        raise ValueError(f"{file}: attendu exactement une occurrence de {old!r}")
    return src.replace(old, new, 1)


def apply(directory):
    root = Path(directory) / "app/src/main"
    values = root / "res/values"

    colors = values / "colors.xml"
    source = colors.read_text(encoding="utf-8")
    if 'name="lexos_bg"' not in source:
        additions = """    <color name="lexos_bg">#08101C</color>
    <color name="lexos_panel">#12233A</color>
    <color name="lexos_accent">#29BAFF</color>
    <color name="lexos_text">#EDF7FF</color>
    <color name="lexos_active">#245172</color>
"""
        source = once(source, "</resources>", additions + "</resources>", colors)
        colors.write_text(source, encoding="utf-8")

    strings = values / "strings.xml"
    source = strings.read_text(encoding="utf-8")
    if '<!ENTITY TERMUX_APP_NAME "LexOS Terminal">' not in source:
        source = once(source, '<!ENTITY TERMUX_APP_NAME "Termux">',
                      '<!ENTITY TERMUX_APP_NAME "LexOS Terminal">', strings)
        strings.write_text(source, encoding="utf-8")

    replacement = {
        '<item name="colorPrimary">@color/black</item>':
            '<item name="colorPrimary">@color/lexos_panel</item>',
        '<item name="colorPrimaryVariant">@color/black</item>':
            '<item name="colorPrimaryVariant">@color/lexos_panel</item>',
        '<item name="android:windowBackground">@color/black</item>':
            '<item name="android:windowBackground">@color/lexos_bg</item>',
        '<item name="extraKeysButtonActiveTextColor">@color/red_400</item>':
            '<item name="extraKeysButtonActiveTextColor">@color/lexos_accent</item>',
        '<item name="extraKeysButtonBackgroundColor">@color/black</item>':
            '<item name="extraKeysButtonBackgroundColor">@color/lexos_panel</item>',
        '<item name="extraKeysButtonActiveBackgroundColor">@color/grey_500</item>':
            '<item name="extraKeysButtonActiveBackgroundColor">@color/lexos_active</item>',
    }
    for name in ("values/themes.xml", "values-night/themes.xml"):
        path = root / "res" / name
        source = path.read_text(encoding="utf-8")
        for old, new in replacement.items():
            if old in source:
                source = once(source, old, new, path)
            elif new not in source:
                raise ValueError(f"{path}: theming incompatible (missing {old})")
        source = source.replace(
            '<item name="termuxActivityDrawerBackground">@color/white</item>',
            '<item name="termuxActivityDrawerBackground">@color/lexos_panel</item>')
        source = source.replace(
            '<item name="termuxActivityDrawerBackground">@color/black</item>',
            '<item name="termuxActivityDrawerBackground">@color/lexos_panel</item>')
        source = source.replace(
            '<item name="termuxActivityDrawerImageTint">@color/black</item>',
            '<item name="termuxActivityDrawerImageTint">@color/lexos_text</item>')
        source = source.replace(
            '<item name="termuxActivityDrawerImageTint">@color/white</item>',
            '<item name="termuxActivityDrawerImageTint">@color/lexos_text</item>')
        path.write_text(source, encoding="utf-8")
        ET.parse(path)

    layout = root / "res/layout/activity_termux.xml"
    source = layout.read_text(encoding="utf-8")
    source = source.replace('android:layout_marginHorizontal="3dp"',
                            'android:layout_marginHorizontal="6dp"')
    source = source.replace('android:layout_height="37.5dp"',
                            'android:layout_height="44dp"')
    source = source.replace('android:background="@color/black"',
                            'android:background="@color/lexos_panel"')
    layout.write_text(source, encoding="utf-8")
    ET.parse(layout)
    ET.parse(colors)
    print(f"Interface LexOS appliquee : {directory}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: style_termux.py /chemin/vers/termux-app")
    apply(sys.argv[1])
