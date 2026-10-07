#!/usr/bin/env python3
"""Synchronize weather output revisions and sign the bundled importable shortcuts."""
import json
import plistlib
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
resources = root / "Sources/GlanceCore/Resources"
versions = json.loads((resources / "WeatherShortcutVersions.json").read_text())
for name, version in versions.items():
    if type(version) is not int or version < 1:
        raise ValueError(f"Invalid revision for {name}: {version}")
    source = root / "Support/WeatherShortcuts" / f"{name}.wflow"
    workflow = plistlib.loads(source.read_bytes())
    comment = f'{name}\nVersion / 版本: {version}\n\nUpdate: import with the same name and choose Replace.\n更新：同名导入，并选择“替换”。'
    first = workflow["WFWorkflowActions"][0]
    if first["WFWorkflowActionIdentifier"] != "is.workflow.actions.comment":
        raise ValueError(f"Missing version comment for {name}")
    first["WFWorkflowActionParameters"]["WFCommentActionText"] = comment
    texts = [action for action in workflow["WFWorkflowActions"]
             if action["WFWorkflowActionIdentifier"] == "is.workflow.actions.gettext"]
    output = texts[-1]["WFWorkflowActionParameters"]["WFTextActionText"]["Value"]
    output["string"] = output["string"].split("\nGLANCE_VERSION\n")[0] + f"\nGLANCE_VERSION\n{version}"
    source.write_bytes(plistlib.dumps(workflow, fmt=plistlib.FMT_XML, sort_keys=False))
    subprocess.run(["/usr/bin/shortcuts", "sign", "--mode", "anyone", "--input", str(source),
                    "--output", str(resources / f"{name}.shortcut")], check=True)
