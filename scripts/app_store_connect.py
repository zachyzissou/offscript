#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import jwt
import requests

BASE_URL = "https://api.appstoreconnect.apple.com"
DEFAULT_ENV_FILES = (
    Path(".env.appstoreconnect"),
    Path("Config/.env.appstoreconnect"),
    Path("Config/AppStoreConnect.local.env"),
)


class ASCError(RuntimeError):
    pass


def load_env_file(path: Path) -> None:
    if not path.exists():
        return

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def load_default_env() -> None:
    for path in DEFAULT_ENV_FILES:
        load_env_file(path)


def infer_key_id(key_path: Path) -> str | None:
    match = re.search(r"AuthKey_([A-Z0-9]+)\.p8$", key_path.name)
    return match.group(1) if match else None


def required_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise ASCError(f"Missing {name}")
    return value


def make_token(scope: list[str] | None = None) -> str:
    key_path = Path(required_env("ASC_KEY_PATH")).expanduser()
    if not key_path.exists():
        raise ASCError(f"Missing private key file: {key_path}")

    key_id = os.environ.get("ASC_KEY_ID") or infer_key_id(key_path)
    if not key_id:
        raise ASCError("Missing ASC_KEY_ID and could not infer it from ASC_KEY_PATH")

    key_type = os.environ.get("ASC_KEY_TYPE", "individual").lower()
    now = int(time.time())
    payload: dict[str, Any] = {
        "iat": now,
        "exp": now + 20 * 60,
        "aud": "appstoreconnect-v1",
    }

    if scope:
        payload["scope"] = scope

    if key_type == "team":
        payload["iss"] = required_env("ASC_ISSUER_ID")
    elif key_type == "individual":
        payload["sub"] = "user"
    else:
        raise ASCError("ASC_KEY_TYPE must be either individual or team")

    private_key = key_path.read_text(encoding="utf-8")
    token = jwt.encode(
        payload,
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )
    return token if isinstance(token, str) else token.decode("utf-8")


class ASCClient:
    def __init__(self) -> None:
        self.session = requests.Session()
        self.session.headers.update(
            {
                "Authorization": f"Bearer {make_token()}",
                "Accept": "application/json",
            }
        )

    def request(self, method: str, path: str, **kwargs: Any) -> dict[str, Any]:
        response = self.session.request(method, f"{BASE_URL}{path}", timeout=30, **kwargs)
        if response.status_code == 204:
            return {"data": []}

        try:
            body = response.json()
        except ValueError:
            body = {"raw": response.text}

        if response.status_code >= 400:
            message = json.dumps(body, indent=2)
            if response.status_code == 401 and os.environ.get("ASC_KEY_TYPE", "individual").lower() == "individual":
                message += "\nIf this is a team key, set ASC_KEY_TYPE=team and ASC_ISSUER_ID."
            raise ASCError(f"{method} {path} failed with HTTP {response.status_code}:\n{message}")

        return body


def attrs(resource: dict[str, Any]) -> dict[str, Any]:
    return resource.get("attributes") or {}


def is_xcode_cloud_deployment_config_error(exc: ASCError) -> bool:
    return "Deployment configured for unknown action" in str(exc)


def find_app(client: ASCClient, bundle_id: str) -> dict[str, Any]:
    response = client.request(
        "GET",
        "/v1/apps",
        params={
            "filter[bundleId]": bundle_id,
            "fields[apps]": "name,bundleId,sku,primaryLocale",
            "limit": 1,
        },
    )
    apps = response.get("data", [])
    if not apps:
        raise ASCError(f"No App Store Connect app found for bundle ID {bundle_id}")
    return apps[0]


def app_builds(client: ASCClient, app_id: str, limit: int) -> list[dict[str, Any]]:
    response = client.request(
        "GET",
        f"/v1/apps/{app_id}/builds",
        params={
            "limit": limit,
            "fields[builds]": "version,uploadedDate,expirationDate,expired,minOsVersion,processingState,buildAudienceType,usesNonExemptEncryption",
        },
    )
    builds = response.get("data", [])
    return sorted(builds, key=lambda build: attrs(build).get("uploadedDate") or "", reverse=True)


def all_app_builds(client: ASCClient, app_id: str) -> list[dict[str, Any]]:
    response = client.request(
        "GET",
        f"/v1/apps/{app_id}/builds",
        params={
            "limit": 200,
            "fields[builds]": "version,uploadedDate,processingState,buildAudienceType",
        },
    )
    builds = response.get("data", [])
    return sorted(builds, key=lambda build: attrs(build).get("uploadedDate") or "", reverse=True)


def beta_groups(client: ASCClient, app_id: str) -> list[dict[str, Any]]:
    response = client.request(
        "GET",
        f"/v1/apps/{app_id}/betaGroups",
        params={
            "limit": 200,
            "fields[betaGroups]": "name,isInternalGroup,hasAccessToAllBuilds,publicLinkEnabled,feedbackEnabled",
        },
    )
    return response.get("data", [])


def beta_group_builds(client: ASCClient, group_id: str) -> list[dict[str, Any]]:
    response = client.request(
        "GET",
        f"/v1/betaGroups/{group_id}/builds",
        params={
            "limit": 200,
            "fields[builds]": "version,uploadedDate,processingState,buildAudienceType",
        },
    )
    return response.get("data", [])


def beta_group_assignment_map(client: ASCClient, groups: list[dict[str, Any]]) -> dict[str, list[str]]:
    assignments: dict[str, list[str]] = {}
    for group in groups:
        group_attrs = attrs(group)
        kind = "internal" if group_attrs.get("isInternalGroup") else "external"
        label = f"{group_attrs.get('name')}:{kind}"
        for build in beta_group_builds(client, group["id"]):
            assignments.setdefault(build["id"], []).append(label)
    return assignments


def build_beta_detail(client: ASCClient, build_id: str) -> dict[str, Any] | None:
    try:
        response = client.request(
            "GET",
            f"/v1/builds/{build_id}/buildBetaDetail",
            params={"fields[buildBetaDetails]": "autoNotifyEnabled,internalBuildState,externalBuildState"},
        )
    except ASCError:
        return None
    return response.get("data")


def print_app(app: dict[str, Any]) -> None:
    app_attrs = attrs(app)
    print(f"App: {app_attrs.get('name')} ({app_attrs.get('bundleId')})")
    print(f"App Store Connect ID: {app.get('id')}")


def print_groups(groups: list[dict[str, Any]]) -> None:
    if not groups:
        print("Beta groups: none")
        return

    print("Beta groups:")
    for group in groups:
        group_attrs = attrs(group)
        kind = "internal" if group_attrs.get("isInternalGroup") else "external"
        public_link = "public-link" if group_attrs.get("publicLinkEnabled") else "no-public-link"
        print(f"- {group_attrs.get('name')} [{kind}, {public_link}] id={group.get('id')}")


def print_builds(
    client: ASCClient,
    builds: list[dict[str, Any]],
    group_assignments: dict[str, list[str]] | None = None,
) -> None:
    if not builds:
        print("Builds: none")
        return

    print("Builds:")
    for build in builds:
        build_attrs = attrs(build)
        line = (
            f"- {build_attrs.get('version')} "
            f"state={build_attrs.get('processingState')} "
            f"audience={build_attrs.get('buildAudienceType')} "
            f"uploaded={build_attrs.get('uploadedDate')} "
            f"id={build.get('id')}"
        )
        print(line)

        detail = build_beta_detail(client, build["id"])
        if detail:
            detail_attrs = attrs(detail)
            print(
                "  beta: "
                f"internal={detail_attrs.get('internalBuildState')} "
                f"external={detail_attrs.get('externalBuildState')} "
                f"autoNotify={detail_attrs.get('autoNotifyEnabled')}"
            )

        if group_assignments is not None:
            labels = group_assignments.get(build["id"], [])
            if labels:
                print(f"  groups: {', '.join(labels)}")
            else:
                print("  groups: none")


def xcode_build_setting(name: str) -> str:
    command = [
        "xcodebuild",
        "-project",
        "OffScript.xcodeproj",
        "-scheme",
        "OffScript",
        "-configuration",
        "Release",
        "-showBuildSettings",
    ]
    env = os.environ.copy()
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    result = subprocess.run(command, check=True, capture_output=True, text=True, env=env)
    pattern = re.compile(rf"^\s*{re.escape(name)}\s*=\s*(.+?)\s*$")
    for line in result.stdout.splitlines():
        match = pattern.match(line)
        if match:
            return match.group(1)
    raise ASCError(f"Could not read Xcode build setting {name}")


def project_version_and_build() -> tuple[str, str]:
    return xcode_build_setting("MARKETING_VERSION"), xcode_build_setting("CURRENT_PROJECT_VERSION")


def build_exists(builds: list[dict[str, Any]], version: str, build_number: str) -> bool:
    return any(attrs(build).get("version") == build_number for build in builds if attrs(build).get("version"))


def latest_build(builds: list[dict[str, Any]]) -> dict[str, Any] | None:
    return builds[0] if builds else None


def latest_eligible_build(builds: list[dict[str, Any]]) -> dict[str, Any] | None:
    for build in builds:
        build_attrs = attrs(build)
        if build_attrs.get("processingState") == "VALID" and build_attrs.get("buildAudienceType") == "APP_STORE_ELIGIBLE":
            return build
    return None


def find_build_by_number(builds: list[dict[str, Any]], build_number: str) -> dict[str, Any] | None:
    for build in builds:
        if attrs(build).get("version") == build_number:
            return build
    return None


def add_build_to_beta_groups(client: ASCClient, build_id: str, group_ids: list[str]) -> None:
    if not group_ids:
        return

    client.request(
        "POST",
        f"/v1/builds/{build_id}/relationships/betaGroups",
        json={"data": [{"type": "betaGroups", "id": group_id} for group_id in group_ids]},
    )


def beta_build_localizations(client: ASCClient, build_id: str) -> list[dict[str, Any]]:
    response = client.request(
        "GET",
        f"/v1/builds/{build_id}/betaBuildLocalizations",
        params={
            "limit": 200,
            "fields[betaBuildLocalizations]": "whatsNew,locale,build",
        },
    )
    return response.get("data", [])


def upsert_beta_build_localization(client: ASCClient, build_id: str, locale: str, whats_new: str) -> dict[str, Any]:
    existing = next(
        (item for item in beta_build_localizations(client, build_id) if attrs(item).get("locale") == locale),
        None,
    )

    if existing:
        return client.request(
            "PATCH",
            f"/v1/betaBuildLocalizations/{existing['id']}",
            json={
                "data": {
                    "type": "betaBuildLocalizations",
                    "id": existing["id"],
                    "attributes": {"whatsNew": whats_new},
                }
            },
        )

    return client.request(
        "POST",
        "/v1/betaBuildLocalizations",
        json={
            "data": {
                "type": "betaBuildLocalizations",
                "attributes": {
                    "locale": locale,
                    "whatsNew": whats_new,
                },
                "relationships": {
                    "build": {
                        "data": {
                            "type": "builds",
                            "id": build_id,
                        }
                    }
                },
            }
        },
    )


def command_doctor(args: argparse.Namespace) -> None:
    client = ASCClient()
    bundle_id = args.bundle_id or required_env("ASC_BUNDLE_ID")
    app = find_app(client, bundle_id)
    groups = beta_groups(client, app["id"])
    builds = all_app_builds(client, app["id"])
    latest = latest_build(builds)
    project_version, project_build = project_version_and_build()

    print_app(app)
    print(f"Project release build: {project_version} ({project_build})")

    if build_exists(builds, project_version, project_build):
        print(f"WARNING: build number {project_build} already exists in App Store Connect for this app.")
        print("         Bump CURRENT_PROJECT_VERSION before uploading again.")
    else:
        print("OK: project build number has not been uploaded yet.")

    internal_groups = [group for group in groups if attrs(group).get("isInternalGroup")]
    external_groups = [group for group in groups if not attrs(group).get("isInternalGroup")]
    print(f"Beta groups: {len(internal_groups)} internal, {len(external_groups)} external")

    if not external_groups:
        print("WARNING: no external beta group exists.")

    if not latest:
        print("WARNING: no TestFlight builds found.")
        return

    latest_attrs = attrs(latest)
    latest_detail = build_beta_detail(client, latest["id"])
    print(
        "Latest uploaded build: "
        f"{latest_attrs.get('version')} "
        f"state={latest_attrs.get('processingState')} "
        f"audience={latest_attrs.get('buildAudienceType')} "
        f"uploaded={latest_attrs.get('uploadedDate')}"
    )

    if latest_detail:
        detail_attrs = attrs(latest_detail)
        print(
            "Latest beta state: "
            f"internal={detail_attrs.get('internalBuildState')} "
            f"external={detail_attrs.get('externalBuildState')}"
        )

    assignments = beta_group_assignment_map(client, groups)
    latest_groups = assignments.get(latest["id"], [])
    print(f"Latest groups: {', '.join(latest_groups) if latest_groups else 'none'}")

    has_internal_latest = any(label.endswith(":internal") for label in latest_groups)
    has_external_latest = any(label.endswith(":external") for label in latest_groups)
    if has_internal_latest and has_external_latest:
        print("OK: latest build is assigned to both internal and external groups.")
    else:
        print("WARNING: latest build is not assigned to both internal and external groups.")


def command_sync_latest(args: argparse.Namespace) -> None:
    client = ASCClient()
    bundle_id = args.bundle_id or required_env("ASC_BUNDLE_ID")
    app = find_app(client, bundle_id)
    groups = beta_groups(client, app["id"])
    builds = all_app_builds(client, app["id"])
    build = latest_eligible_build(builds)
    if not build:
        raise ASCError("No valid App Store eligible build found")

    build_attrs = attrs(build)
    assignments = beta_group_assignment_map(client, groups)
    assigned_group_labels = set(assignments.get(build["id"], []))
    missing_groups = []
    for group in groups:
        group_attrs = attrs(group)
        kind = "internal" if group_attrs.get("isInternalGroup") else "external"
        label = f"{group_attrs.get('name')}:{kind}"
        if label not in assigned_group_labels:
            missing_groups.append(group)

    print_app(app)
    print(f"Latest eligible build: {build_attrs.get('version')} id={build.get('id')}")
    if not missing_groups:
        print("OK: latest eligible build already has access to every beta group.")
        return

    print("Missing beta group access:")
    for group in missing_groups:
        group_attrs = attrs(group)
        kind = "internal" if group_attrs.get("isInternalGroup") else "external"
        print(f"- {group_attrs.get('name')} [{kind}] id={group.get('id')}")

    if not args.apply:
        print("Dry run only. Re-run with --apply to add build access to these groups.")
        return

    # Apple's TestFlight API does not allow attaching a build to an *internal*
    # beta group — internal groups auto-provision on every newly-uploaded
    # eligible build (the request returns 422 ENTITY_UNPROCESSABLE with
    # "Cannot add internal group to a build"). Only explicit external-group
    # assignment is supported.
    external_missing = [
        g for g in missing_groups
        if not attrs(g).get("isInternalGroup")
    ]
    skipped_internal = [
        g for g in missing_groups
        if attrs(g).get("isInternalGroup")
    ]

    for group in skipped_internal:
        group_attrs = attrs(group)
        print(f"Skipping internal group {group_attrs.get('name')!r} — internal groups auto-receive eligible builds")

    if not external_missing:
        print("Done: no external beta groups need an explicit add (internal groups auto-provision).")
        return

    # External-group attach can fail on a fresh build with HTTP 422
    # "Build is not in an externally assignable state" — that means the build
    # uploaded VALID but Apple hasn't put it through external beta review yet.
    # Internal testers already have the build, so this is a non-fatal warning,
    # not a CI-failure-worthy condition. The external group will pick up the
    # build automatically after review approval.
    try:
        add_build_to_beta_groups(client, build["id"], [group["id"] for group in external_missing])
        print("Applied: latest eligible build now has access to the missing external beta groups.")
    except ASCError as exc:
        message = str(exc)
        non_fatal_signals = (
            "not in an externally assignable state",
            "not assignable",
            "Cannot add internal group",
        )
        if any(signal in message for signal in non_fatal_signals):
            print(f"Warning: external attach skipped — {message.splitlines()[0]}")
            print("Build is in TestFlight for internal testers; external assignment will happen after Apple review.")
            return
        raise


def command_apps(args: argparse.Namespace) -> None:
    client = ASCClient()
    bundle_id = args.bundle_id or required_env("ASC_BUNDLE_ID")
    print_app(find_app(client, bundle_id))


def command_status(args: argparse.Namespace) -> None:
    client = ASCClient()
    bundle_id = args.bundle_id or required_env("ASC_BUNDLE_ID")
    app = find_app(client, bundle_id)
    print_app(app)
    print()
    groups = beta_groups(client, app["id"])
    print_groups(groups)
    print()
    print_builds(client, app_builds(client, app["id"], args.limit), beta_group_assignment_map(client, groups))


def command_builds(args: argparse.Namespace) -> None:
    client = ASCClient()
    bundle_id = args.bundle_id or required_env("ASC_BUNDLE_ID")
    app = find_app(client, bundle_id)
    group_assignments = None
    if args.groups:
        group_assignments = beta_group_assignment_map(client, beta_groups(client, app["id"]))
    print_builds(client, app_builds(client, app["id"], args.limit), group_assignments)


def command_exists(args: argparse.Namespace) -> None:
    client = ASCClient()
    bundle_id = args.bundle_id or required_env("ASC_BUNDLE_ID")
    app = find_app(client, bundle_id)
    version = args.version
    build_number = args.build
    if not version or not build_number:
        version, build_number = project_version_and_build()

    if build_exists(all_app_builds(client, app["id"]), version, build_number):
        print(f"exists: {bundle_id} {version} ({build_number})")
        raise ASCError("Build number already uploaded")

    print(f"available: {bundle_id} {version} ({build_number})")


def command_wait_build(args: argparse.Namespace) -> None:
    client = ASCClient()
    bundle_id = args.bundle_id or required_env("ASC_BUNDLE_ID")
    app = find_app(client, bundle_id)
    deadline = time.time() + args.timeout

    while True:
        build = find_build_by_number(all_app_builds(client, app["id"]), args.build)
        if build:
            build_attrs = attrs(build)
            state = build_attrs.get("processingState")
            audience = build_attrs.get("buildAudienceType")
            print(f"build id={build['id']} number={build_attrs.get('version')} state={state} audience={audience}")
            if not args.require_valid or state == "VALID":
                if args.id_file:
                    args.id_file.parent.mkdir(parents=True, exist_ok=True)
                    args.id_file.write_text(build["id"], encoding="utf-8")
                return
            if state == "FAILED":
                raise ASCError(f"Build {args.build} processing failed")

        if time.time() >= deadline:
            raise ASCError(f"Timed out waiting for build {args.build}")
        time.sleep(args.poll)


def command_set_beta_notes(args: argparse.Namespace) -> None:
    client = ASCClient()
    bundle_id = args.bundle_id or required_env("ASC_BUNDLE_ID")
    app = find_app(client, bundle_id)
    notes = args.notes_file.read_text(encoding="utf-8").strip()
    if not notes:
        raise ASCError(f"Notes file is empty: {args.notes_file}")

    build_id = args.build_id
    if not build_id:
        if not args.build:
            raise ASCError("Pass --build-id or --build")
        build = find_build_by_number(all_app_builds(client, app["id"]), args.build)
        if not build:
            raise ASCError(f"Build not found: {args.build}")
        build_id = build["id"]

    upsert_beta_build_localization(client, build_id, args.locale, notes[:4000])
    print(f"Updated TestFlight notes for build id={build_id} locale={args.locale}")


def command_xcode_cloud_probe(args: argparse.Namespace) -> None:
    """
    Diagnostic for Xcode Cloud setup. Hits the read-only Xcode Cloud
    endpoints with the ASC API key and prints what we can see.

    Three possible outcomes:
      A. ciProducts returns 1+ entries → Xcode Cloud is enabled and the
         app is onboarded; we can list/create workflows via API.
      B. ciProducts returns 200 with an empty list → Xcode Cloud product
         hasn't been provisioned for this app yet. ONE-TIME manual step:
         App Store Connect → My Apps → OffScript → Xcode Cloud → "Get
         Started". After that, re-run this probe.
      C. ciProducts returns 403 / "FORBIDDEN_ERROR" → API key doesn't
         have Xcode Cloud scope. Add the "Developer" or "App Manager"
         role to the key (Users and Access → Keys → edit key roles).

    On the happy path A, prints the product ID and existing workflows
    so the next step can target them.
    """
    client = ASCClient()
    bundle_id = args.bundle_id or required_env("ASC_BUNDLE_ID")

    print(f"Probing Xcode Cloud for {bundle_id}...")
    try:
        products_body = client.request("GET", "/v1/ciProducts", params={"limit": 200})
    except ASCError as exc:
        print(f"  /v1/ciProducts failed: {exc}")
        print("  Likely cause: API key missing Developer / App Manager role,")
        print("  OR Xcode Cloud terms not accepted on the team account yet.")
        print("  See: https://appstoreconnect.apple.com/access/users")
        raise SystemExit(2)

    products = products_body.get("data", [])
    if not products:
        print("  Xcode Cloud has NO products provisioned on this account.")
        print("  ONE-TIME setup (Apple requires this in the web UI before")
        print("  the API can create workflows):")
        print()
        print("    1. Open App Store Connect → My Apps → OffScript")
        print("    2. Click 'Xcode Cloud' in the left sidebar")
        print("    3. Click 'Get Started' and accept the terms")
        print("    4. (Optional) skip the wizard once it's accepted —")
        print("       this script will create the actual workflow")
        print("    5. Re-run: scripts/app_store_connect.py xcode-cloud probe")
        return

    # Print products + their workflows.
    for product in products:
        a = attrs(product)
        product_id = product.get("id")
        product_app = a.get("name") or a.get("productType") or product_id
        print(f"  PRODUCT {product_id} {product_app!r}")
        try:
            wfs_body = client.request(
                "GET",
                f"/v1/ciProducts/{product_id}/workflows",
                params={"limit": 50},
            )
            for wf in wfs_body.get("data", []):
                wa = attrs(wf)
                print(f"    WORKFLOW {wf.get('id')} {wa.get('name')!r:30} "
                      f"enabled={wa.get('isEnabled')}, lastModified={wa.get('lastModifiedDate')}")
        except ASCError as exc:
            print(f"    workflows query failed: {exc}")


def command_xcode_cloud_inspect(args: argparse.Namespace) -> None:
    """
    Drill into a single Xcode Cloud workflow: dump the start condition,
    actions, and the last N build runs with their status. Tells us
    whether the existing workflow does what we want before we either
    rely on it or create a new one.
    """
    client = ASCClient()
    workflow_id = args.workflow_id

    print(f"Workflow {workflow_id}")
    body = client.request(
        "GET",
        f"/v1/ciWorkflows/{workflow_id}",
        params={"include": "macOsVersion,xcodeVersion,product"},
    )
    wf = body.get("data", {})
    a = attrs(wf)
    print(f"  name: {a.get('name')!r}")
    print(f"  description: {a.get('description')!r}")
    print(f"  enabled: {a.get('isEnabled')}")
    print(f"  lastModified: {a.get('lastModifiedDate')}")
    print(f"  branchStartCondition: {json.dumps(a.get('branchStartCondition'), indent=2)}")
    print(f"  pullRequestStartCondition: {json.dumps(a.get('pullRequestStartCondition'), indent=2)}")
    print(f"  tagStartCondition: {json.dumps(a.get('tagStartCondition'), indent=2)}")
    print(f"  scheduledStartCondition: {json.dumps(a.get('scheduledStartCondition'), indent=2)}")
    actions = a.get("actions") or []
    print(f"  actions: {len(actions)}")
    for action in actions:
        print(f"    - {json.dumps(action, indent=6)}")
        if (
            action.get("actionType") == "ARCHIVE"
            and action.get("buildDistributionAudience") == "INTERNAL_ONLY"
        ):
            print("      WARNING: archive uses INTERNAL_ONLY; external TestFlight needs APP_STORE_ELIGIBLE.")

    print()
    print(f"Recent build runs (limit {args.limit}):")
    try:
        runs_body = client.request(
            "GET",
            f"/v1/ciWorkflows/{workflow_id}/buildRuns",
            params={"limit": args.limit, "sort": "-number"},
        )
        for run in runs_body.get("data", []):
            ra = attrs(run)
            print(f"  RUN #{ra.get('number')} {run.get('id')} "
                  f"status={ra.get('executionProgress')}/{ra.get('completionStatus')}, "
                  f"start={ra.get('startReason')}, src={ra.get('sourceCommit', {}).get('htmlUrl', '?')}")
    except ASCError as exc:
        print(f"  buildRuns query failed: {exc}")


def command_xcode_cloud_reconfigure(args: argparse.Namespace) -> None:
    """
    PATCH an existing Xcode Cloud workflow so it triggers on push to main
    (and optionally release tags vX.Y.Z), and so the Archive action
    prepares archives for TestFlight and App Store distribution.

    Idempotent — safe to re-run. Only mutates fields specified by flags.

    The default behavior:
      - branchStartCondition pattern → 'main' (autoCancel on)
      - tagStartCondition pattern → 'v*' (catches v2.2.0, v2.3.0, etc.)
      - actions[].buildDistributionAudience → APP_STORE_ELIGIBLE for any
        ARCHIVE action that currently differs
    """
    client = ASCClient()
    workflow_id = args.workflow_id

    # Fetch the current state so we can preserve unrelated fields.
    body = client.request("GET", f"/v1/ciWorkflows/{workflow_id}")
    wf = body.get("data", {})
    a = attrs(wf)

    new_attributes: dict[str, Any] = {}

    # Branch start condition
    if not args.skip_branch:
        new_attributes["branchStartCondition"] = {
            "source": {
                "isAllMatch": False,
                "patterns": [{"pattern": args.branch, "isPrefix": False}],
            },
            "filesAndFoldersRule": None,
            "autoCancel": True,
        }

    # Tag start condition (release-driven path)
    if args.tag_pattern:
        new_attributes["tagStartCondition"] = {
            "source": {
                "isAllMatch": False,
                "patterns": [{"pattern": args.tag_pattern, "isPrefix": False}],
            },
            "autoCancel": False,
        }

    # Configure archive deployment preparation. Apple's API enum maps to:
    #   INTERNAL_ONLY      -> TestFlight (Internal Testing Only)
    #   APP_STORE_ELIGIBLE -> TestFlight and App Store
    #
    # Keep the whole action payload intact because PATCH replaces this array.
    if args.testflight:
        actions = a.get("actions") or []
        updated_actions = []
        changed_actions = False
        for action in actions:
            if action.get("actionType") == "ARCHIVE" and action.get("buildDistributionAudience") != args.audience:
                updated = dict(action)
                updated["buildDistributionAudience"] = args.audience
                updated_actions.append(updated)
                changed_actions = True
            else:
                updated_actions.append(action)
        if changed_actions:
            new_attributes["actions"] = updated_actions

    if not new_attributes:
        print("Nothing to update.")
        return

    payload = {
        "data": {
            "type": "ciWorkflows",
            "id": workflow_id,
            "attributes": new_attributes,
        }
    }
    print("PATCH /v1/ciWorkflows/{} payload:".format(workflow_id))
    print(json.dumps(payload, indent=2))

    if not args.apply:
        print("\nDry run. Re-run with --apply to actually PATCH.")
        return

    try:
        response = client.request("PATCH", f"/v1/ciWorkflows/{workflow_id}", json=payload)
    except ASCError as exc:
        if is_xcode_cloud_deployment_config_error(exc):
            print()
            print("PATCH failed because App Store Connect rejected the action replacement:")
            print("  Deployment configured for unknown action.")
            print()
            print("Apple's ciWorkflows PATCH endpoint replaces the actions array, and")
            print("some existing workflows have a hidden deploymentConfig tied to the")
            print("original archive action. Change Deployment Preparation for this")
            print("workflow in App Store Connect or Xcode Cloud from")
            print("  TestFlight (Internal Testing Only)")
            print("to")
            print("  TestFlight and App Store")
            print("then re-run:")
            print(f"  scripts/app_store_connect.py xcode-cloud inspect {workflow_id}")
        raise
    print("\nPATCH succeeded.")
    new_attrs = attrs(response.get("data", {}))
    print(f"  branchStartCondition: {json.dumps(new_attrs.get('branchStartCondition'), indent=2)}")
    print(f"  tagStartCondition: {json.dumps(new_attrs.get('tagStartCondition'), indent=2)}")
    print(f"  actions: {len(new_attrs.get('actions') or [])}")


def command_xcode_cloud_build_run(args: argparse.Namespace) -> None:
    """Drill into a specific build run: top-level status, all build actions,
    and the issues + artifacts each action produced."""
    client = ASCClient()
    run_id = args.build_run_id

    body = client.request("GET", f"/v1/ciBuildRuns/{run_id}")
    run = body.get("data", {})
    a = attrs(run)
    print(f"Build run {run_id}")
    print(f"  number: {a.get('number')}")
    print(f"  executionProgress: {a.get('executionProgress')}")
    print(f"  completionStatus: {a.get('completionStatus')}")
    print(f"  startReason: {a.get('startReason')}")
    print(f"  cancelReason: {a.get('cancelReason')}")
    print(f"  createdDate: {a.get('createdDate')}")
    print(f"  finishedDate: {a.get('finishedDate')}")
    sc = a.get("sourceCommit") or {}
    print(f"  sourceCommit: ref={sc.get('commitSha', '?')[:8]} branch={sc.get('htmlUrl', '?')}")

    try:
        actions_body = client.request("GET", f"/v1/ciBuildRuns/{run_id}/actions", params={"limit": 50})
    except ASCError as exc:
        print(f"  actions query failed: {exc}")
        return

    print()
    actions = actions_body.get("data", [])
    print(f"Build actions ({len(actions)}):")
    for action in actions:
        action_id = action.get("id")
        aa = attrs(action)
        print(f"  ACTION {action_id} {aa.get('name')!r}")
        print(f"    actionType: {aa.get('actionType')}")
        print(f"    executionProgress: {aa.get('executionProgress')}")
        print(f"    completionStatus: {aa.get('completionStatus')}")
        print(f"    isRequiredToPass: {aa.get('isRequiredToPass')}")
        try:
            iss_body = client.request(
                "GET",
                f"/v1/ciBuildActions/{action_id}/issues",
                params={"limit": 50},
            )
            for issue in iss_body.get("data", []):
                ia = attrs(issue)
                print(f"    ISSUE {ia.get('issueType')} category={ia.get('category')}: {ia.get('message')}")
                if ia.get("fileSource"):
                    print(f"      at {ia['fileSource'].get('fileName')}:{ia['fileSource'].get('lineNumber')}")
        except ASCError as exc:
            print(f"    issues query failed: {exc}")


def command_xcode_cloud_start_build(args: argparse.Namespace) -> None:
    """
    Manually kick off a build via POST /v1/ciBuildRuns. Useful for
    one-shot validation that the workflow + signing are healthy without
    pushing a code change.
    """
    client = ASCClient()
    payload = {
        "data": {
            "type": "ciBuildRuns",
            "relationships": {
                "workflow": {
                    "data": {
                        "type": "ciWorkflows",
                        "id": args.workflow_id,
                    }
                }
            }
        }
    }
    body = client.request("POST", "/v1/ciBuildRuns", json=payload)
    run = body.get("data", {})
    a = attrs(run)
    print(f"Started build run {run.get('id')} (number {a.get('number')})")
    print(f"  executionProgress: {a.get('executionProgress')}")
    print(f"  startReason: {a.get('startReason')}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Read App Store Connect status for OffScript.")
    parser.add_argument("--env", type=Path, help="Optional env file to load before defaults.")
    parser.add_argument("--bundle-id", help="Bundle ID to inspect. Defaults to ASC_BUNDLE_ID.")

    subparsers = parser.add_subparsers(dest="command", required=True)

    apps_parser = subparsers.add_parser("app", help="Show the App Store Connect app record.")
    apps_parser.set_defaults(func=command_apps)

    builds_parser = subparsers.add_parser("builds", help="List recent builds.")
    builds_parser.add_argument("--limit", type=int, default=10)
    builds_parser.add_argument("--groups", action="store_true", help="Include beta group assignment for each build.")
    builds_parser.set_defaults(func=command_builds)

    status_parser = subparsers.add_parser("status", help="Show app, beta groups, recent builds, and beta states.")
    status_parser.add_argument("--limit", type=int, default=10)
    status_parser.set_defaults(func=command_status)

    doctor_parser = subparsers.add_parser("doctor", help="Check release pipeline health before uploading.")
    doctor_parser.set_defaults(func=command_doctor)

    sync_parser = subparsers.add_parser("sync-latest", help="Ensure the latest eligible build has beta group access.")
    sync_parser.add_argument("--apply", action="store_true", help="Actually add missing beta group access.")
    sync_parser.set_defaults(func=command_sync_latest)

    exists_parser = subparsers.add_parser("build-exists", help="Fail if a version/build is already uploaded.")
    exists_parser.add_argument("--version")
    exists_parser.add_argument("--build")
    exists_parser.set_defaults(func=command_exists)

    wait_parser = subparsers.add_parser("wait-build", help="Wait for an uploaded build to appear and optionally become VALID.")
    wait_parser.add_argument("--build", required=True, help="CFBundleVersion / App Store Connect build number.")
    wait_parser.add_argument("--timeout", type=int, default=1800)
    wait_parser.add_argument("--poll", type=int, default=30)
    wait_parser.add_argument("--require-valid", action="store_true")
    wait_parser.add_argument("--id-file", type=Path)
    wait_parser.set_defaults(func=command_wait_build)

    xcc_probe_parser = subparsers.add_parser(
        "xcode-cloud",
        help="Xcode Cloud diagnostics + setup commands.",
    )
    xcc_subparsers = xcc_probe_parser.add_subparsers(dest="xcc_command", required=True)
    xcc_probe = xcc_subparsers.add_parser(
        "probe",
        help="Check whether Xcode Cloud is provisioned for this app and list any existing workflows.",
    )
    xcc_probe.set_defaults(func=command_xcode_cloud_probe)

    xcc_inspect = xcc_subparsers.add_parser(
        "inspect",
        help="Dump a workflow's start condition, actions, and recent build runs.",
    )
    xcc_inspect.add_argument("workflow_id", help="Xcode Cloud workflow UUID (from `probe`).")
    xcc_inspect.add_argument("--limit", type=int, default=10, help="Build runs to list (default 10).")
    xcc_inspect.set_defaults(func=command_xcode_cloud_inspect)

    xcc_reconfig = xcc_subparsers.add_parser(
        "reconfigure",
        help="PATCH a workflow to trigger on push to main + tag pattern, with auto-publish to TestFlight.",
    )
    xcc_reconfig.add_argument("workflow_id", help="Xcode Cloud workflow UUID.")
    xcc_reconfig.add_argument("--branch", default="main", help="Branch pattern to start on (default 'main').")
    xcc_reconfig.add_argument("--tag-pattern", default="v*", help="Tag pattern to start on (default 'v*'). Set empty string to skip.")
    xcc_reconfig.add_argument("--skip-branch", action="store_true", help="Don't touch branchStartCondition.")
    xcc_reconfig.add_argument("--testflight", action="store_true", help="Set buildDistributionAudience on ARCHIVE actions.")
    xcc_reconfig.add_argument("--audience", default="APP_STORE_ELIGIBLE", choices=["INTERNAL_ONLY", "APP_STORE_ELIGIBLE"])
    xcc_reconfig.add_argument("--apply", action="store_true", help="Actually PATCH. Without this flag, dry-run.")
    xcc_reconfig.set_defaults(func=command_xcode_cloud_reconfigure)

    xcc_run = xcc_subparsers.add_parser(
        "build-run",
        help="Inspect a specific build run: status, actions, and per-action issues.",
    )
    xcc_run.add_argument("build_run_id", help="Build run UUID (from `inspect`).")
    xcc_run.set_defaults(func=command_xcode_cloud_build_run)

    xcc_start = xcc_subparsers.add_parser(
        "start-build",
        help="Manually trigger a build run for a workflow (no source change needed).",
    )
    xcc_start.add_argument("workflow_id", help="Xcode Cloud workflow UUID.")
    xcc_start.set_defaults(func=command_xcode_cloud_start_build)

    notes_parser = subparsers.add_parser("set-beta-notes", help="Create or update TestFlight What to Test notes.")
    notes_parser.add_argument("--build-id")
    notes_parser.add_argument("--build", help="CFBundleVersion / App Store Connect build number.")
    notes_parser.add_argument("--notes-file", type=Path, required=True)
    notes_parser.add_argument("--locale", default="en-US")
    notes_parser.set_defaults(func=command_set_beta_notes)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.env:
        load_env_file(args.env)
    load_default_env()

    try:
        args.func(args)
    except ASCError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
