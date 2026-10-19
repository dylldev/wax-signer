#!/usr/bin/env python3
"""Execute the real Foundation-only R1 parsers on a non-Apple Swift toolchain.

This is deliberately NOT a substitute for `swift test` on macOS: Security, CryptoKit,
Compression, signing, and verifier integration are absent. Only the existing error
ENUM is extracted from its Security-dependent file; no parser or crypto mocks run.
Each XCTest case runs in a subprocess so a fatal trap cannot end the other cases.
Requires Swift >= 5.9 and Python 3; no downloaded dependencies.
"""
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="wax-parser-tests-") as temp:
    root = Path(temp)
    src = root / "Sources/SigningKit"
    tests = root / "Tests/SigningKitTests"
    src.mkdir(parents=True)
    tests.mkdir(parents=True)
    for name in ["CheckedBytes", "MachO", "FatMachO", "SignatureLayout", "DebArchive"]:
        shutil.copyfile(repo / f"Sources/SigningKit/{name}.swift", src / f"{name}.swift")
    error_source = (repo / "Sources/SigningKit/CodeSigningIdentity.swift").read_text()
    error_enum = error_source[error_source.index("public enum SigningError"):error_source.index("/// What the signer needs")]
    (src / "SigningError.swift").write_text("import Foundation\n" + error_enum)
    for name in ["ParserSafetyTests", "MachOMalformedTests"]:
        shutil.copyfile(repo / f"Tests/SigningKitTests/{name}.swift", tests / f"{name}.swift")
    shutil.copytree(repo / "Tests/SigningKitTests/Fixtures", tests / "Fixtures")
    (tests / "Fixtures.swift").write_text('''import Foundation
enum Fixtures {
    static var appDirectory: URL { Bundle.module.resourceURL!.appendingPathComponent("Fixtures/TestApp.app") }
}
''')
    (root / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "WaxParserSafety", targets: [
    .target(name: "SigningKit"),
    .testTarget(name: "SigningKitTests", dependencies: ["SigningKit"], resources: [.copy("Fixtures")])
])
''')
    subprocess.run(["swift", "build", "--build-tests"], cwd=root, check=True)
    listed = subprocess.check_output(["swift", "test", "list", "--skip-build"], cwd=root, text=True)
    cases = [s.strip() for s in listed.splitlines() if re.fullmatch(r"SigningKitTests\.\w+/test\w+", s.strip())]
    if not cases:
        raise RuntimeError("No XCTest cases discovered")
    failed = []
    for case in cases:
        print(f"Running isolated: {case}", flush=True)
        result = subprocess.run(["swift", "test", "--skip-build", "--filter", case], cwd=root)
        if result.returncode:
            failed.append(case)
    print(f"Portable parser cases: {len(cases) - len(failed)} passed, {len(failed)} failed; Apple integration NOT run.")
    if failed:
        print("Failures:\n" + "\n".join(failed))
        sys.exit(1)
