#!/usr/bin/env python3
"""Build static DocC references for every target with public declarations."""

import argparse
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Sources" / "SwiftDebtKit" / "SwiftDebtKit.docc"
PUBLIC_MODULES = {
    "SwiftDebtKit": Path("."),
    "SwiftDebtCore": Path("api/swiftdebtcore"),
    "SwiftDebtInteractive": Path("api/swiftdebtinteractive"),
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--hosting-base-path", default="SwiftDebt")
    arguments = parser.parse_args()
    output = arguments.output.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error(f"output directory must be empty: {output}")
    output.mkdir(parents=True, exist_ok=True)

    for module, relative_path in PUBLIC_MODULES.items():
        target = output / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        hosting_path = "/".join(
            part for part in (arguments.hosting_base_path.strip("/"),
                             *relative_path.parts) if part and part != "."
        )
        command = [
            "swift", "package", "--allow-writing-to-directory", str(output),
            "generate-documentation", "--target", module, "--output-path", str(target),
            "--transform-for-static-hosting", "--hosting-base-path", hosting_path,
            "--disable-indexing", "--symbol-graph-minimum-access-level", "public",
            "--warnings-as-errors",
        ]
        subprocess.run(command, cwd=ROOT, check=True)
        if not (target / "index.html").is_file():
            raise RuntimeError(f"DocC did not create {target / 'index.html'}")
        if module == "SwiftDebtKit":
            for section in ("Tutorials", "Articles"):
                for source in (CATALOG / section).glob("*.md"):
                    article = target / "data" / "documentation" / "swiftdebtkit" / (
                        source.stem.lower() + ".json"
                    )
                    if not article.is_file():
                        raise RuntimeError(f"DocC omitted catalog article: {source}")

    print(f"DocC documentation built at {output}")


if __name__ == "__main__":
    main()
