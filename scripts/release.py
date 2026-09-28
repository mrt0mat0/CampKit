#!/usr/bin/env python3
"""Cut a CampKit release: bump the version, build the zip, upload it to
CurseForge, then commit, tag, push and publish a GitHub release.

    python3 scripts/release.py 1.2 --notes "Flyout now defaults to round."
    python3 scripts/release.py 1.2 --dry-run      # build the zip only, change nothing
    python3 scripts/release.py --game-versions    # list CurseForge game version IDs

The CurseForge upload happens before anything is committed, so a failed upload
leaves the repo exactly as it was.

Setup (once):
  - CurseForge API token in $CURSEFORGE_TOKEN or ~/.config/curseforge/token
    (create one at https://legacy.curseforge.com/account/api-tokens)
  - "## X-Curse-Project-ID: <id>" in CampKit.toc
  - game version IDs in scripts/release_config.json (find them with --game-versions)
"""
import argparse
import json
import os
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = "CampKit"
TOC = ROOT / f"{ADDON}.toc"
CONFIG = ROOT / "scripts" / "release_config.json"
DIST = ROOT / "dist"
TOKEN_FILE = Path.home() / ".config" / "curseforge" / "token"
CF_API = "https://wow.curseforge.com/api"
EXTRA_FILES = ["LICENSE"]  # shipped in the zip alongside the files the .toc loads


def fail(msg):
    sys.exit(f"release: {msg}")


def redact(text, secret):
    return text.replace(secret, "<token>") if secret else text


def run(*cmd, capture=False, secret=None):
    """Run a command; on failure show its output, with `secret` (the API token) hidden."""
    result = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=capture)
    if result.returncode != 0:
        detail = "\n".join(x for x in (result.stdout, result.stderr) if x)
        fail(redact(f"`{' '.join(cmd)}` failed\n{detail}".rstrip(), secret))
    return result.stdout.strip() if capture else None


def upload_form(metadata, zip_path):
    """curl form fields for an upload. --form-string sends the metadata verbatim: with -F,
    curl treats ';' in a value as the start of options and cuts the changelog off there."""
    return ("--form-string", f"metadata={metadata}", "-F", f"file=@{zip_path}")


def toc_field(text, name):
    m = re.search(rf"^## {re.escape(name)}:\s*(.+?)\s*$", text, re.M)
    return m.group(1) if m else None


def toc_files(text):
    return [line.strip() for line in text.splitlines()
            if line.strip() and not line.startswith("#")]


def token():
    tok = os.environ.get("CURSEFORGE_TOKEN")
    if not tok and TOKEN_FILE.exists():
        tok = TOKEN_FILE.read_text().strip()
    return tok


def curseforge(path, tok, extra=()):
    out = run("curl", "-sS", "--fail-with-body", "-H", f"X-Api-Token: {tok}",
              *extra, f"{CF_API}{path}", capture=True, secret=tok)
    return json.loads(out)


def list_game_versions():
    tok = token() or fail("no CurseForge token (see the setup notes at the top of this script)")
    types = {t["id"]: t["name"] for t in curseforge("/game/version-types", tok)}
    for v in sorted(curseforge("/game/versions", tok), key=lambda v: v["id"]):
        print(f"{v['id']:>6}  {v['name']:<12}  {types.get(v['gameVersionTypeID'], '?')}")


def notes_since_last_tag():
    last = subprocess.run(["git", "describe", "--tags", "--abbrev=0"], cwd=ROOT,
                          text=True, capture_output=True).stdout.strip()
    span = f"{last}..HEAD" if last else "HEAD"
    subjects = run("git", "log", "--no-merges", "--format=%s", span, capture=True)
    return "\n".join(f"- {s}" for s in subjects.splitlines()) or "- Maintenance release"


def build_zip(version, toc_text):
    DIST.mkdir(exist_ok=True)
    path = DIST / f"{ADDON}-{version}.zip"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(f"{ADDON}/{TOC.name}", toc_text)
        for name in toc_files(toc_text) + EXTRA_FILES:
            src = ROOT / name
            if not src.exists():
                fail(f"{name} is missing")
            z.write(src, f"{ADDON}/{name}")
    return path


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("version", nargs="?", help="new version, e.g. 1.2")
    p.add_argument("--notes", help="changelog (Markdown); defaults to commit subjects since the last tag")
    p.add_argument("--type", default="release", choices=["release", "beta", "alpha"])
    p.add_argument("--dry-run", action="store_true", help="build the zip only; no upload, commit or push")
    p.add_argument("--skip-curseforge", action="store_true", help="GitHub release only")
    p.add_argument("--game-versions", action="store_true", help="list CurseForge game version IDs and exit")
    args = p.parse_args()

    if args.game_versions:
        return list_game_versions()
    if not args.version:
        p.error("version is required")

    version = args.version.lstrip("v")
    tag = f"v{version}"
    if not re.fullmatch(r"\d+(\.\d+)*", version):
        fail(f"'{version}' doesn't look like a version number")

    toc_text = TOC.read_text()
    current = toc_field(toc_text, "Version")
    if not args.dry_run:
        if run("git", "status", "--porcelain", capture=True):
            fail("working tree has uncommitted changes")
        if run("git", "branch", "--show-current", capture=True) != "main":
            fail("releases are cut from main")
        if run("git", "tag", "--list", tag, capture=True):
            fail(f"tag {tag} already exists")

    new_toc = re.sub(r"^(## Version:\s*).*$", rf"\g<1>{version}", toc_text, count=1, flags=re.M)
    notes = args.notes or notes_since_last_tag()
    zip_path = build_zip(version, new_toc)
    print(f"Built {zip_path.relative_to(ROOT)} ({current} -> {version})")
    print(f"Notes:\n{notes}\n")

    if args.dry_run:
        print("Dry run: nothing uploaded, committed or pushed.")
        return

    if not args.skip_curseforge:
        tok = token() or fail("no CurseForge token (use --skip-curseforge for a GitHub-only release)")
        project = toc_field(toc_text, "X-Curse-Project-ID") or fail("CampKit.toc has no ## X-Curse-Project-ID")
        game_versions = json.loads(CONFIG.read_text()).get("game_version_ids") if CONFIG.exists() else None
        if not game_versions:
            fail(f"set game_version_ids in {CONFIG.relative_to(ROOT)} (find them with --game-versions)")
        metadata = json.dumps({
            "changelog": notes, "changelogType": "markdown", "displayName": f"{ADDON} {version}",
            "gameVersions": game_versions, "releaseType": args.type,
        })
        result = curseforge(f"/projects/{project}/upload-file", tok,
                            upload_form(metadata, zip_path))
        print(f"Uploaded to CurseForge (file id {result.get('id')})")

    TOC.write_text(new_toc)
    run("git", "commit", "-qam", f"Release {ADDON} {version}")
    run("git", "tag", "-a", tag, "-m", f"{ADDON} {version}")
    run("git", "push", "-q", "origin", "main", tag)
    prerelease = ["--prerelease"] if args.type != "release" else []
    run("gh", "release", "create", tag, str(zip_path), "--title", f"{ADDON} {version}",
        "--notes", notes, *prerelease)
    print(f"Released {tag}")


if __name__ == "__main__":
    main()
