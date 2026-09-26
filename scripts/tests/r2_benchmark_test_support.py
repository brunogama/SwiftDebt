import json


CACHE_DATA_CLASSES = [
    "data-clump-syntax-facts",
    "fact-budget-dependencies",
    "parse-diagnostics",
    "repeated-switch-syntax-facts",
    "source-content-digests",
]


def fake_cli_source(scenario, configuration, cache_compatibility):
    source_snapshot_digest = {"algorithm": "sha256", "value": "0" * 64}
    detections = scenario["expectedDetectionCounts"]
    rules = [
        {
            "ruleIdentity": identity,
            "completionState": "complete",
            "semanticRevision": 2,
            "detections": [{} for _ in range(count)],
            "issues": [],
            "capabilities": [
                {"provider": {"name": "SwiftSyntax", "version": "602.0.0"}}
            ],
        }
        for identity, count in detections.items()
    ]
    sidecar = {
        "summary": {
            "sourceFileCount": scenario["sourceFileCount"],
            "detectionCount": sum(detections.values()),
            "completeRuleCount": len(rules),
            "incompleteRuleCount": 0,
        },
        "rules": rules,
        "snapshot": {
            "contentDigest": source_snapshot_digest,
            "configuration": configuration,
        },
    }
    expectation = scenario["expectedCacheActivity"]
    cache_activity = {
        "reportKind": "swiftdebt-repository-syntax-cache",
        "schemaVersion": 1,
        "sourceSnapshotDigest": source_snapshot_digest,
        "mode": expectation["mode"],
        "disposition": expectation["disposition"],
        "compatibility": cache_compatibility,
        "storage": {
            "location": None,
            "dataClasses": [],
            "byteCount": 0,
            "contentDigest": None,
            "writePerformed": expectation["writePerformed"],
        },
        "selectedSourceCount": expectation["selectedSourceCount"],
        "reusedSourceCount": expectation["reusedSourceCount"],
        "recomputedSourceCount": expectation["recomputedSourceCount"],
        "removedSourceCount": expectation["removedSourceCount"],
        "invalidations": [
            {"reason": reason, "sourceCount": count}
            for reason, count in expectation["invalidations"].items()
        ],
        "networkRequestCount": expectation["networkRequestCount"],
    }
    if expectation["mode"] == "disabled":
        cache_activity["storage"].pop("location")
        cache_activity["storage"].pop("contentDigest")
    return f"""#!/usr/bin/env python3
import json
import sys
from pathlib import Path
arguments = sys.argv[1:]
def value(option):
    return Path(arguments[arguments.index(option) + 1])
report = value("--output")
profile = value("--profile-output")
sidecar = value("--repository-evidence")
cache_report = value("--repository-cache-report")
for path in (report, profile, sidecar, cache_report):
    path.parent.mkdir(parents=True, exist_ok=True)
report.write_text('{{"schemaVersion":2}}\\n')
profile.write_text(json.dumps({{"phases":[{{"phase":"discovery","elapsedNanoseconds":100}}]}}))
sidecar.write_text(json.dumps({json.dumps(sidecar)}))
cache_report.write_text({json.dumps(json.dumps(cache_activity))})
"""


def stateful_fake_cli_source(scenario, configuration, cache_compatibility):
    source_snapshot_digest = {"algorithm": "sha256", "value": "0" * 64}
    static_source = fake_cli_source(scenario, configuration, cache_compatibility)
    prefix = static_source.split("cache_report.write_text", 1)[0]
    return prefix + f'''source_root = Path(arguments[1])
source_hashes = {{
    path.name: __import__("hashlib").sha256(path.read_bytes()).hexdigest()
    for path in sorted(source_root.glob("*.swift"))
}}
cache_path = value("--repository-cache") if "--repository-cache" in arguments else None
if cache_path is None:
    mode = "disabled"
    disposition = "disabled"
    reused = 0
    recomputed = len(source_hashes)
    invalidations = [{{"reason": "cache-disabled", "sourceCount": recomputed}}]
    write_performed = False
else:
    previous = json.loads(cache_path.read_text()) if cache_path.is_file() else None
    if previous is None:
        mode = "reuse"
        disposition = "cold-rebuild"
        reused = 0
        recomputed = len(source_hashes)
        invalidations = [{{"reason": "cache-missing", "sourceCount": recomputed}}]
        write_performed = True
    else:
        changed = sum(
            previous["sourceHashes"].get(name) != digest
            for name, digest in source_hashes.items()
        )
        reused = len(source_hashes) - changed
        recomputed = changed
        if changed:
            mode = "reuse"
            disposition = "partial-rebuild"
            invalidations = [
                {{"reason": "source-content-changed", "sourceCount": changed}}
            ]
            write_performed = True
        else:
            mode = "reuse"
            disposition = "warm-reuse"
            invalidations = []
            write_performed = False
    if write_performed:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(json.dumps({{"sourceHashes": source_hashes}}, sort_keys=True))
cache_data = cache_path.read_bytes() if cache_path else b""
activity = {{
    "reportKind": "swiftdebt-repository-syntax-cache",
    "schemaVersion": 1,
    "sourceSnapshotDigest": {json.dumps(source_snapshot_digest)},
    "mode": mode,
    "disposition": disposition,
    "compatibility": {json.dumps(cache_compatibility)},
    "storage": {{
        "location": str(cache_path) if cache_path else None,
        "dataClasses": {json.dumps(CACHE_DATA_CLASSES)} if cache_path else [],
        "byteCount": len(cache_data),
        "contentDigest": {{
            "algorithm": "sha256",
            "value": __import__("hashlib").sha256(cache_data).hexdigest(),
        }} if cache_path else None,
        "writePerformed": write_performed,
    }},
    "selectedSourceCount": len(source_hashes),
    "reusedSourceCount": reused,
    "recomputedSourceCount": recomputed,
    "removedSourceCount": 0,
    "invalidations": invalidations,
    "networkRequestCount": 0,
}}
cache_report.write_text(json.dumps(activity, sort_keys=True))
'''
