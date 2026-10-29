#!/usr/bin/env python3
"""Exercise build/promotion failures in isolated app fixtures, never Moa.app."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="moa-build-recovery-") as temporary:
        base = Path(temporary)
        source = base / "main.c"
        source.write_text("int main(void) { return 0; }\n")
        binary = base / "fixture-binary"
        subprocess.run(["/usr/bin/xcrun", "clang", "-mmacosx-version-min=12.0", str(source), "-o", str(binary)], check=True)
        for failure in ["compile", "sign", "promote", "restore", "none"]:
            fixture = base / failure
            (fixture / "scripts").mkdir(parents=True)
            for name in ["build-menu-bar-app.sh", "version.env", "sources.env"]:
                shutil.copy2(root / "scripts" / name, fixture / "scripts" / name)
            shutil.copytree(root / "macos-menu-bar/Resources", fixture / "macos-menu-bar/Resources")
            shutil.copytree(root / "assets", fixture / "assets")
            old = fixture / "Moa.app"
            old.mkdir()
            marker = old / "previous-build"
            marker.write_bytes(b"known-good previous app")
            before = digest(marker)
            compiler = fixture / "swiftc-fixture"
            compiler.write_text("""#!/usr/bin/env python3
import os, shutil, sys
if os.environ['MOA_FIXTURE_FAILURE'] == 'compile':
    open(os.environ['MOA_FIXTURE_STAGE_FILE'], 'w').write('compile')
    sys.exit(72)
shutil.copy2(os.environ['MOA_FIXTURE_BINARY'], sys.argv[sys.argv.index('-o') + 1])
""")
            compiler.chmod(0o755)
            (fixture / "bin").mkdir()
            move = fixture / "bin" / "mv"
            move.write_text("""#!/usr/bin/env python3
import os, sys
source = sys.argv[1]
failure = os.environ['MOA_FIXTURE_FAILURE']
if '.moa-build.' in source and (source.endswith('/Moa.app') and failure in ['promote', 'restore'] or source.endswith('/previous.app') and failure == 'restore'):
    open(os.environ['MOA_FIXTURE_STAGE_FILE'], 'w').write(failure)
    sys.exit(73)
os.execv('/bin/mv', ['/bin/mv'] + sys.argv[1:])
""")
            move.chmod(0o755)
            environment = dict(os.environ, SWIFTC=str(compiler), MOA_FIXTURE_FAILURE=failure,
                               MOA_FIXTURE_BINARY=str(binary), APP_VERSION="1.5.0", APP_BUILD="124",
                               MOA_FIXTURE_STAGE_FILE=str(fixture / "failure-stage"),
                               MACOS_DEPLOYMENT_TARGET="12.0", CODE_SIGN_IDENTITY="Moa Missing Fixture Identity" if failure == "sign" else "-",
                               PATH=str(fixture / "bin") + ":" + os.environ["PATH"])
            result = subprocess.run(["bash", str(fixture / "scripts/build-menu-bar-app.sh")],
                                    env=environment, capture_output=True, text=True, timeout=30)
            workspaces = list(fixture.glob(".moa-build.*"))
            if failure == "sign":
                assert "Missing code signing identity:" in result.stderr, result.stderr
            elif failure != "none":
                assert (fixture / "failure-stage").read_text() == failure, result.stderr
            if failure == "none":
                assert result.returncode == 0, result.stderr
                assert (old / "Contents/MacOS/Moa").exists()
                assert (old / "Contents/Resources/CodexStatusLine.js").read_bytes() == (root / "macos-menu-bar/Resources/CodexStatusLine.js").read_bytes()
                assert not workspaces
            elif failure == "restore":
                assert result.returncode != 0
                backups = list(fixture.glob(".moa-build.*/previous.app/previous-build"))
                assert len(backups) == 1 and digest(backups[0]) == before
            else:
                assert result.returncode != 0
                assert marker.exists() and digest(marker) == before, (failure, result.stderr)
                assert not workspaces
            print(f"PASS: {failure}", flush=True)


if __name__ == "__main__":
    main()
