#!/usr/bin/env python3
"""App Store Connect helper for Engine Pulse, run from GitHub Actions.

Credentials come from the repository secrets ASC_ISSUER_ID, ASC_KEY_ID and ASC_PRIVATE_KEY
(an App Store Connect API team key). Results are posted as a comment on the GitHub issue
"App Store Connect automation log" so they can be read without opening the Actions page.

Commands:
  status                       app, latest Xcode Cloud runs, latest TestFlight builds, beta groups
  ensure-build <sha>           start the Xcode Cloud "Default" workflow for main if no run exists for <sha>
  start-build                  start the "Default" workflow on main now
  release-beta [group] [text]  add the newest processed build to a beta group (default "Pilot Beta"),
                               set its What to Test text, and submit it for beta review
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt  # PyJWT

BUNDLE_ID = "com.fueledconsulting.EngineMonitoring"
WORKFLOW_NAME = "Default"
API = "https://api.appstoreconnect.apple.com"
LOG = []


def log(line=""):
    print(line)
    LOG.append(line)


def private_key():
    """Rebuilds a clean PEM from however the .p8 was pasted (one line, extra spaces, quotes, with or without the BEGIN/END lines)."""
    import re
    raw = os.environ["ASC_PRIVATE_KEY"].replace("\\n", "\n").strip().strip('"').strip("'")
    body = re.sub(r"-----(BEGIN|END)[A-Z ]*-----", "", raw)
    body = re.sub(r"[^A-Za-z0-9+/=]", "", body)
    if len(body) < 100:
        raise SystemExit("ASC_PRIVATE_KEY looks empty or cut off. Paste the whole contents of the AuthKey_XXXX.p8 file.")
    lines = [body[i:i + 64] for i in range(0, len(body), 64)]
    return "-----BEGIN PRIVATE KEY-----\n" + "\n".join(lines) + "\n-----END PRIVATE KEY-----\n"


def token():
    key = private_key()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"].strip(), "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"].strip(), "typ": "JWT"})


def call(method, path, body=None):
    url = path if path.startswith("http") else API + path
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise SystemExit(f"{method} {path} -> HTTP {e.code}: {detail[:800]}")


def app():
    apps = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not apps:
        raise SystemExit(f"No app with bundle ID {BUNDLE_ID} is visible to this key.")
    return apps[0]


def ci_product(app_id):
    data = call("GET", f"/v1/apps/{app_id}/ciProduct")
    return data["data"]


def workflow(product_id):
    flows = call("GET", f"/v1/ciProducts/{product_id}/workflows")["data"]
    for f in flows:
        if f["attributes"]["name"] == WORKFLOW_NAME:
            return f
    raise SystemExit(f"No Xcode Cloud workflow named {WORKFLOW_NAME}.")


def recent_runs(product_id, limit=8):
    data = call("GET", f"/v1/ciProducts/{product_id}/buildRuns?sort=-number&limit={limit}")["data"]
    out = []
    for r in data:
        a = r["attributes"]
        sha = ((a.get("sourceCommit") or {}).get("commitSha") or "")
        out.append({"number": a.get("number"), "status": a.get("executionProgress"), "result": a.get("completionStatus"),
                    "sha": sha, "started": a.get("startedDate") or a.get("createdDate")})
    return out


def main_ref(wf_id):
    repo = call("GET", f"/v1/ciWorkflows/{wf_id}/repository")["data"]
    refs = call("GET", f"/v1/scmRepositories/{repo['id']}/gitReferences?limit=200")["data"]
    for r in refs:
        if r["attributes"].get("canonicalName") == "refs/heads/main" or r["attributes"].get("name") == "main":
            return r["id"]
    raise SystemExit("Could not find the main branch in the Xcode Cloud repository.")


def start_build(product_id):
    wf = workflow(product_id)
    ref = main_ref(wf["id"])
    run = call("POST", "/v1/ciBuildRuns", {"data": {"type": "ciBuildRuns", "relationships": {
        "workflow": {"data": {"type": "ciWorkflows", "id": wf["id"]}},
        "sourceBranchOrTag": {"data": {"type": "scmGitReferences", "id": ref}}}}})
    log(f"Started Xcode Cloud build #{run['data']['attributes'].get('number')} of {WORKFLOW_NAME} on main.")


def testflight_builds(app_id, limit=6):
    data = call("GET", f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit={limit}&include=preReleaseVersion")
    versions = {i["id"]: i["attributes"]["version"] for i in data.get("included", []) if i["type"] == "preReleaseVersions"}
    out = []
    for b in data["data"]:
        a = b["attributes"]
        pv = ((b.get("relationships") or {}).get("preReleaseVersion") or {}).get("data") or {}
        out.append({"id": b["id"], "version": versions.get(pv.get("id"), "?"), "build": a.get("version"),
                    "state": a.get("processingState"), "uploaded": a.get("uploadedDate"), "expired": a.get("expired")})
    return out


def groups(app_id):
    return call("GET", f"/v1/betaGroups?filter[app]={app_id}&limit=50")["data"]


def cmd_status():
    a = app()
    log(f"App: {a['attributes']['name']} ({a['attributes']['bundleId']}), id {a['id']}")
    p = ci_product(a["id"])
    log("")
    log("Xcode Cloud runs (newest first):")
    for r in recent_runs(p["id"]):
        log(f"- #{r['number']} {r['status']} {r['result'] or ''} commit {r['sha'][:7]} started {r['started']}")
    log("")
    log("TestFlight builds (newest first):")
    for b in testflight_builds(a["id"]):
        log(f"- {b['version']} ({b['build']}) {b['state']}{' expired' if b['expired'] else ''} uploaded {b['uploaded']}")
    log("")
    log("Beta groups:")
    for g in groups(a["id"]):
        at = g["attributes"]
        log(f"- {at['name']} ({'internal' if at.get('isInternalGroup') else 'external'})"
            f"{', public link on' if at.get('publicLinkEnabled') else ''}")


def cmd_ensure_build(sha):
    a = app()
    p = ci_product(a["id"])
    # Give Xcode Cloud time to start on its own first.
    for _ in range(10):
        if any(r["sha"].startswith(sha[:7]) for r in recent_runs(p["id"], 15)):
            log(f"Xcode Cloud already has a run for {sha[:7]}. Nothing to do.")
            return
        time.sleep(30)
    log(f"No Xcode Cloud run for {sha[:7]} after 5 minutes.")
    start_build(p["id"])


def cmd_release_beta(group_name="Pilot Beta", what_to_test=""):
    a = app()
    g = next((g for g in groups(a["id"]) if g["attributes"]["name"] == group_name), None)
    if not g:
        raise SystemExit(f"No beta group named {group_name}.")
    b = next((b for b in testflight_builds(a["id"], 10) if b["state"] == "VALID" and not b["expired"]), None)
    if not b:
        raise SystemExit("No processed, unexpired build found.")
    call("POST", f"/v1/betaGroups/{g['id']}/relationships/builds", {"data": [{"type": "builds", "id": b["id"]}]})
    log(f"Added {b['version']} ({b['build']}) to {group_name}.")
    if what_to_test:
        locs = call("GET", f"/v1/builds/{b['id']}/betaBuildLocalizations")["data"]
        if locs:
            call("PATCH", f"/v1/betaBuildLocalizations/{locs[0]['id']}", {"data": {
                "type": "betaBuildLocalizations", "id": locs[0]["id"], "attributes": {"whatsNew": what_to_test}}})
        else:
            call("POST", "/v1/betaBuildLocalizations", {"data": {"type": "betaBuildLocalizations",
                "attributes": {"locale": "en-US", "whatsNew": what_to_test},
                "relationships": {"build": {"data": {"type": "builds", "id": b["id"]}}}}})
        log("Set What to Test.")
    if not g["attributes"].get("isInternalGroup"):
        try:
            call("POST", "/v1/betaAppReviewSubmissions", {"data": {"type": "betaAppReviewSubmissions",
                "relationships": {"build": {"data": {"type": "builds", "id": b["id"]}}}}})
            log("Submitted for beta app review.")
        except SystemExit as e:
            log(f"Beta review submission: {e}")


def post_log(title):
    """Comments the log on the tracking issue (created if needed)."""
    gh = os.environ.get("GITHUB_TOKEN")
    repo = os.environ.get("GITHUB_REPOSITORY")
    if not gh or not repo:
        return
    def ghcall(method, path, body=None):
        req = urllib.request.Request("https://api.github.com" + path, method=method,
                                     data=json.dumps(body).encode() if body is not None else None)
        req.add_header("Authorization", "Bearer " + gh)
        req.add_header("Accept", "application/vnd.github+json")
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read() or b"{}")
    issues = ghcall("GET", f"/repos/{repo}/issues?state=open&labels=asc-log&per_page=5")
    if issues:
        number = issues[0]["number"]
    else:
        number = ghcall("POST", f"/repos/{repo}/issues", {"title": "App Store Connect automation log",
            "body": "Results of the App Store Connect automation (tools/asc.py).", "labels": ["asc-log"]})["number"]
    ghcall("POST", f"/repos/{repo}/issues/{number}/comments",
           {"body": f"**{title}**\n\n```\n" + "\n".join(LOG)[-60000:] + "\n```"})


def annotate(kind, title, text):
    """Shows text as a GitHub annotation (readable from the check run without the Actions page)."""
    esc = text.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    print(f"::{kind} title={title}::{esc[:60000]}")


def safe_post(title):
    try:
        post_log(title)
    except Exception as e:  # posting the log must never hide the real result
        annotate("warning", "log-issue", f"Could not post to the log issue: {e}")


def main():
    try:
        run()
    except SystemExit:
        raise
    except Exception as e:
        import traceback
        log("ERROR: " + "".join(traceback.format_exception_only(type(e), e)).strip())
        annotate("error", "asc", "\n".join(LOG))
        safe_post("failed")
        raise SystemExit(1)


def run():
    args = sys.argv[1:] or ["status"]
    cmd = args[0]
    title = " ".join(args)
    try:
        if cmd == "status":
            cmd_status()
        elif cmd == "ensure-build":
            cmd_ensure_build(args[1])
        elif cmd == "start-build":
            start_build(ci_product(app()["id"])["id"])
        elif cmd == "release-beta":
            cmd_release_beta(args[1] if len(args) > 1 and args[1] else "Pilot Beta", args[2] if len(args) > 2 else "")
        else:
            raise SystemExit(f"Unknown command {cmd}")
    except SystemExit as e:
        if e.code not in (None, 0):
            log(f"ERROR: {e.code}")
            annotate("error", "asc", "\n".join(LOG))
            safe_post(title + " (failed)")
            raise
    except KeyError as e:
        log(f"ERROR: missing secret {e}. Add it under Settings > Secrets and variables > Actions.")
        annotate("error", "asc", "\n".join(LOG))
        safe_post(title + " (failed)")
        raise SystemExit(1)
    annotate("notice", "asc", "\n".join(LOG))
    safe_post(title)


if __name__ == "__main__":
    main()
