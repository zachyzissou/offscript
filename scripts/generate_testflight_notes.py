#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import textwrap
from pathlib import Path


DEFAULT_OUTPUT_DIR = Path("build/TestFlight/notes")


def run_git(args: list[str]) -> str:
    result = subprocess.run(["git", *args], check=True, capture_output=True, text=True)
    return result.stdout.strip()


def safe_git(args: list[str]) -> str:
    try:
        return run_git(args)
    except subprocess.CalledProcessError:
        return ""


def commit_subjects(revision_range: str, limit: int) -> list[str]:
    if revision_range:
        output = safe_git(["log", "--no-merges", f"--max-count={limit}", "--pretty=format:%s", revision_range])
        if output:
            return [line.strip() for line in output.splitlines() if line.strip()]

    output = safe_git(["log", "--no-merges", f"--max-count={limit}", "--pretty=format:%s"])
    return [line.strip() for line in output.splitlines() if line.strip()]


def changed_files(revision_range: str) -> list[str]:
    output = safe_git(["diff", "--name-only", revision_range]) if revision_range else ""
    if not output:
        output = safe_git(["show", "--pretty=", "--name-only", "HEAD"])
    return sorted({line.strip() for line in output.splitlines() if line.strip()})


def bullets(items: list[str], fallback: str, limit: int | None = None) -> list[str]:
    selected = items[:limit] if limit else items
    if not selected:
        return [f"- {fallback}"]
    return [f"- {item}" for item in selected]


def categorized_test_prompts(files: list[str]) -> list[str]:
    prompts: list[str] = []
    joined = "\n".join(files).lower()

    if any(token in joined for token in ["queue", "playback", "player", "download", "podcastservices"]):
        prompts.append("Queue several episodes, use Play Next/Add to End, and confirm playback advances in the expected order.")
    if any(token in joined for token in ["library", "episode", "cardcomponents"]):
        prompts.append("Open Library and a show detail page; verify episode rows, filters, search, and batch actions behave correctly.")
    if any(token in joined for token in ["recommendation", "home", "search", "onboarding", "import", "taste"]):
        prompts.append("Complete onboarding/import, then confirm Home recommendations explain why each episode is surfaced.")
    if any(token in joined for token in ["download", "offline"]):
        prompts.append("Download an episode, relaunch, and confirm offline status and playback from the downloaded file.")
    if any(token in joined for token in ["settings", "telemetry", "sync"]):
        prompts.append("Open Settings diagnostics and confirm sync/feed-build events are visible after import or playback activity.")
    if any(token in joined for token in ["theme", "assets", "appicon", "design", "view"]):
        prompts.append("Check the main tabs on a small iPhone simulator for clipping, overlap, readable text, and usable tap targets.")

    prompts.append("Run a smoke pass through Home, Library, Queue, Search, mini-player, and full player.")
    return list(dict.fromkeys(prompts))


def truncate(text: str, max_chars: int) -> str:
    if len(text) <= max_chars:
        return text
    suffix = "\n\nMore detail is available in the GitHub release-notes artifact."
    return text[: max(0, max_chars - len(suffix))].rstrip() + suffix


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + "\n", encoding="utf-8")


def build_notes(args: argparse.Namespace) -> tuple[str, str, str]:
    commits = commit_subjects(args.revision_range, args.commit_limit)
    files = changed_files(args.revision_range)
    test_prompts = categorized_test_prompts(files)

    title = f"OffScript beta {args.version} ({args.build})" if args.version and args.build else "OffScript beta"
    summary = args.summary.strip() or "Automated beta candidate from the latest main branch changes."
    custom_what_to_test = args.what_to_test.strip()

    changelog = "\n".join(
        [
            f"# {title}",
            "",
            "## Summary",
            summary,
            "",
            "## Changes",
            *bullets(commits, "Latest main branch changes.", args.commit_limit),
            "",
            "## Changed Files",
            *bullets(files, "No changed files detected.", 60),
        ]
    )

    what_to_test_sections = [
        f"# What To Test: {title}",
        "",
        "## Primary Pass",
        *bullets(test_prompts, "Run the core app smoke flow."),
    ]
    if custom_what_to_test:
        what_to_test_sections.extend(["", "## Release-Specific Notes", custom_what_to_test])
    what_to_test = "\n".join(what_to_test_sections)

    testflight_parts = [
        title,
        "",
        "What changed:",
        *bullets(commits, "Latest main branch changes.", 8),
        "",
        "What to test:",
        *bullets(test_prompts, "Run the core app smoke flow.", 8),
    ]
    if custom_what_to_test:
        testflight_parts.extend(["", "Release-specific focus:", textwrap.shorten(custom_what_to_test, width=700, placeholder="...")])
    testflight = truncate("\n".join(testflight_parts), args.max_testflight_chars)

    return changelog, what_to_test, testflight


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate TestFlight changelog and tester notes.")
    parser.add_argument("--range", dest="revision_range", default="", help="Git revision range, e.g. before..sha")
    parser.add_argument("--version", default="")
    parser.add_argument("--build", default="")
    parser.add_argument("--summary", default="")
    parser.add_argument("--what-to-test", default="")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--commit-limit", type=int, default=18)
    parser.add_argument("--max-testflight-chars", type=int, default=3800)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    changelog, what_to_test, testflight = build_notes(args)

    write(args.output_dir / "CHANGELOG.md", changelog)
    write(args.output_dir / "WHAT_TO_TEST.md", what_to_test)
    write(args.output_dir / "testflight-notes.txt", testflight)

    print(f"Wrote {args.output_dir / 'CHANGELOG.md'}")
    print(f"Wrote {args.output_dir / 'WHAT_TO_TEST.md'}")
    print(f"Wrote {args.output_dir / 'testflight-notes.txt'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
