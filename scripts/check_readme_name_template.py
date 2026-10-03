#!/usr/bin/env python3
"""README content-aware default must match ContentNameTemplate.defaultTemplate.

Fails when:
- the Swift default drops {subject}
- README.md does not quote that exact default template string
- the content-aware example filename has no subject token beyond date/type/org
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE_REL = "Intake/IntakeCore/Sources/IntakeCore/ContentNameTemplate.swift"
README_REL = "README.md"

TEMPLATE_RE = re.compile(r'public static let defaultTemplate = "([^"]*)"')
EXAMPLE_RE = re.compile(r"`(\d{4}-\d{2}-\d{2} [^`\n]+\.pdf)`")


def load_template(text: str) -> str:
    matches = TEMPLATE_RE.findall(text)
    if len(matches) != 1:
        raise SystemExit(
            "readme-name-template: expected exactly one defaultTemplate, "
            f"found {len(matches)} in {TEMPLATE_REL}"
        )
    return matches[0]


def check(template: str, readme: str) -> list[str]:
    errors: list[str] = []
    if "{subject}" not in template:
        errors.append(
            "readme-name-template: ContentNameTemplate.defaultTemplate is "
            f"`{template}` and does not include `{{subject}}`.\n"
            f"  source: {TEMPLATE_REL}\n"
            "  The content-aware default must keep a subject token."
        )
    if template not in readme:
        errors.append(
            "readme-name-template: README.md does not contain ContentNameTemplate.defaultTemplate "
            f"`{template}`.\n"
            f"  source: {TEMPLATE_REL}\n"
            "  Update the content-aware sentence in README.md so it quotes the default template exactly."
        )
    examples = EXAMPLE_RE.findall(readme)
    subject_bearing: list[str] = []
    too_short: list[str] = []
    for name in examples:
        tokens = name[: -len(".pdf")].split()
        if len(tokens) >= 4:
            subject_bearing.append(name)
        else:
            too_short.append(name)
    if not subject_bearing:
        found = ", ".join(f"`{name}`" for name in too_short) or "(none)"
        errors.append(
            "readme-name-template: content-aware example has no subject token beyond "
            "date, type, and organization.\n"
            f"  found: {found}\n"
            "  expected shape: `2026-09-14 Invoice Acme September Hosting.pdf` "
            "(date, type, organization, and a subject)."
        )
    return errors


def self_test() -> list[str]:
    print("readme-name-template self-test")
    errors: list[str] = []
    good_template = "{date} {type} {organization} {subject}"
    good_readme = (
        "Optional content-aware names, such as "
        "`2026-09-14 Invoice Acme September Hosting.pdf`. "
        "The default template is `{date} {type} {organization} {subject}`."
    )
    cases = (
        ("aligned", good_template, good_readme, False),
        (
            "readme-dropped-template",
            good_template,
            "The default template includes `{subject}`. "
            "Example `2026-09-14 Invoice Acme September Hosting.pdf`.",
            True,
        ),
        (
            "example-missing-subject",
            good_template,
            "The default template is `{date} {type} {organization} {subject}`. "
            "Example `2026-09-14 Invoice Acme.pdf`.",
            True,
        ),
        (
            "constant-dropped-subject",
            "{date} {type} {organization}",
            "The default template is `{date} {type} {organization}`. "
            "Example `2026-09-14 Invoice Acme September Hosting.pdf`.",
            True,
        ),
    )
    for name, template, readme, should_fail in cases:
        found = check(template, readme)
        if should_fail and not found:
            errors.append(f"self-test: expected {name} to fail")
            print(f"  FAIL expected rejection, got pass: {name}")
        elif not should_fail and found:
            errors.append(f"self-test: expected {name} to pass: {found}")
            print(f"  FAIL expected pass: {name}")
        else:
            print(f"  correctly {'rejected' if should_fail else 'accepted'} {name}")
            for block in found:
                print("  " + block.replace("\n", "\n  "))
    return errors


def main() -> int:
    problems = self_test()
    template = load_template((ROOT / TEMPLATE_REL).read_text(encoding="utf-8"))
    readme = (ROOT / README_REL).read_text(encoding="utf-8")
    real = check(template, readme)
    if real:
        print("readme-name-template: current tree")
        for block in real:
            print(block)
    problems.extend(real)
    if problems:
        print(f"\n{len(problems)} readme-name-template problem(s).", file=sys.stderr)
        return 1
    print(f"readme-name-template: ok (defaultTemplate `{template}`)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
