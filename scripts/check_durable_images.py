#!/usr/bin/env python3
"""Fail when evidence images depend on a ref other than the default branch.

Feature-branch blob/raw URLs 404 after the branch is deleted (PR #51 did this
with docs/media on cursor/in-30-pdf-subject-default). User-attachments and
images already on main/master are allowed. Relative links in committed
markdown are allowed.

Fenced code blocks are ignored so a writeup can quote a bad URL without
embedding it as a rendered image.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

DEFAULT_BRANCHES = {"main", "master"}
IMAGE_EXT = re.compile(r"\.(?:png|jpe?g|gif|webp|svg)(?:$|[?#])", re.IGNORECASE)

FENCE_RE = re.compile(
    r"(^|\n)(?P<fence>`{3,}|~{3,})[^\n]*\n.*?\n(?P=fence)[ \t]*(?=\n|$)",
    re.DOTALL,
)
MD_IMAGE_RE = re.compile(r"!\[[^\]]*\]\(\s*<?([^)\s>]+)>?")
HTML_IMG_RE = re.compile(
    r"<img\b[^>]*\bsrc\s*=\s*['\"]([^'\"]+)['\"]",
    re.IGNORECASE,
)
BARE_URL_RE = re.compile(r"https?://[^\s<>)\]\"']+")

FAIL_FIXTURES = (
    "fail-blob-branch.md",
    "fail-raw-sha.md",
    "fail-html-img.md",
)
PASS_FIXTURES = (
    "pass-user-attachments.md",
    "pass-relative.md",
    "pass-main-and-badge.md",
    "pass-fenced-example.md",
    "pass-non-image-blob.md",
)


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def strip_fences(text: str) -> str:
    return FENCE_RE.sub(lambda match: match.group(1), text)


def looks_like_image(url: str) -> bool:
    return IMAGE_EXT.search(urlparse(url).path) is not None


def ephemeral_ref(url: str) -> str | None:
    """Non-default ref when this image URL dies with a branch or commit. Else None."""
    if not looks_like_image(url):
        return None
    parsed = urlparse(url.strip())
    if parsed.scheme not in ("http", "https"):
        return None
    host = parsed.netloc.lower().split("@")[-1].split(":")[0]
    parts = [part for part in parsed.path.split("/") if part]
    if host in ("github.com", "www.github.com"):
        if parts[:1] == ["user-attachments"]:
            return None
        # /{owner}/{repo}/blob|raw/{ref}/...
        if len(parts) >= 5 and parts[2] in ("blob", "raw"):
            ref = parts[3]
            if ref not in DEFAULT_BRANCHES:
                return ref
        return None
    if host == "raw.githubusercontent.com" and len(parts) >= 4:
        ref = parts[2]
        if ref not in DEFAULT_BRANCHES:
            return ref
    return None


def extract_image_urls(text: str) -> list[str]:
    visible = strip_fences(text)
    found: list[str] = []
    for pattern in (MD_IMAGE_RE, HTML_IMG_RE):
        found.extend(pattern.findall(visible))
    for url in BARE_URL_RE.findall(visible):
        url = url.rstrip(".,;:")
        if looks_like_image(url):
            found.append(url)
    seen: set[str] = set()
    unique: list[str] = []
    for url in found:
        if url not in seen:
            seen.add(url)
            unique.append(url)
    return unique


def findings_for(text: str, source: str) -> list[str]:
    found: list[str] = []
    for url in extract_image_urls(text):
        ref = ephemeral_ref(url)
        if ref is None:
            continue
        found.append(
            "durable-images: ephemeral evidence image "
            f"(ref {ref!r} is not the default branch 'main')\n"
            f"  source: {source}\n"
            f"  url: {url}\n"
            "  Fix: upload the image on the pull request so GitHub hosts it at\n"
            "  https://github.com/user-attachments/assets/..., or link a file that\n"
            "  already exists on the default branch. Feature-branch blob/raw URLs\n"
            "  404 after that branch is deleted."
        )
    return found


def iter_markdown(root: Path):
    fixtures = (root / "scripts" / "fixtures").resolve()
    for path in root.rglob("*.md"):
        resolved = path.resolve()
        if resolved == fixtures or fixtures in resolved.parents:
            continue
        parts = path.relative_to(root).parts
        if any(part.startswith(".") or part == "dist" for part in parts):
            continue
        yield path


def scan_repo(root: Path) -> list[str]:
    found: list[str] = []
    for path in sorted(iter_markdown(root)):
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(root).as_posix()
        found.extend(findings_for(text, rel))
    return found


def pr_body_from_event(event_path: Path) -> str | None:
    payload = json.loads(event_path.read_text(encoding="utf-8"))
    pull_request = payload.get("pull_request")
    if not isinstance(pull_request, dict):
        return None
    body = pull_request.get("body")
    return body if isinstance(body, str) else ""


def self_test(root: Path) -> list[str]:
    errors: list[str] = []
    fixture_dir = root / "scripts" / "fixtures" / "durable-images"
    print("durable-images self-test")
    for name in FAIL_FIXTURES:
        text = (fixture_dir / name).read_text(encoding="utf-8")
        found = findings_for(text, f"fixture:{name}")
        if not found:
            errors.append(f"self-test: expected {name} to fail but it passed")
            print(f"  FAIL expected rejection, got pass: {name}")
            continue
        print(f"  correctly rejected {name}:")
        for block in found:
            print("  " + block.replace("\n", "\n  "))
    for name in PASS_FIXTURES:
        text = (fixture_dir / name).read_text(encoding="utf-8")
        found = findings_for(text, f"fixture:{name}")
        if found:
            errors.append(
                f"self-test: expected {name} to pass but it failed:\n" + "\n".join(found)
            )
            print(f"  FAIL expected pass: {name}")
            continue
        print(f"  correctly accepted {name}")
    return errors


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--body-file",
        type=Path,
        help="Markdown to treat as the pull request body (local dry-run)",
    )
    parser.add_argument(
        "--skip-self-test",
        action="store_true",
        help="Skip fixture self-test (debug only)",
    )
    args = parser.parse_args(argv)
    root = repo_root()
    problems: list[str] = []
    if not args.skip_self_test:
        problems.extend(self_test(root))
    problems.extend(scan_repo(root))

    if args.body_file is not None:
        text = args.body_file.read_text(encoding="utf-8")
        problems.extend(findings_for(text, f"PR body file {args.body_file}"))
    else:
        event = os.environ.get("GITHUB_EVENT_PATH")
        if event:
            try:
                body = pr_body_from_event(Path(event))
            except (OSError, json.JSONDecodeError) as exc:
                problems.append(f"durable-images: could not read GITHUB_EVENT_PATH ({exc})")
            else:
                if body is not None:
                    problems.extend(findings_for(body, "PR body"))

    if problems:
        print("\n".join(problems), file=sys.stderr)
        print(f"\n{len(problems)} durable-images problem(s).", file=sys.stderr)
        return 1
    print("durable-images: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
