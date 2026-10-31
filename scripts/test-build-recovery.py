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
            for name in ["build-menu-bar-app.sh", "version.env", "sources.env", "code-signing.env"]:
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




def cross_arch_does_not_replace_native_app():
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="moa-cross-arch-") as temporary:
        base = Path(temporary)
        source = base / "main.c"
        source.write_text("int main(void) { return 0; }\n")
        binary = base / "fixture-x86_64"
        subprocess.run(
            ["/usr/bin/xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=12.0", str(source), "-o", str(binary)],
            check=True,
        )
        fixture = base / "fixture"
        (fixture / "scripts").mkdir(parents=True)
        for name in ["build-menu-bar-app.sh", "version.env", "sources.env", "code-signing.env"]:
            shutil.copy2(root / "scripts" / name, fixture / "scripts" / name)
        shutil.copytree(root / "macos-menu-bar/Resources", fixture / "macos-menu-bar/Resources")
        shutil.copytree(root / "assets", fixture / "assets")
        native = fixture / "Moa.app"
        native.mkdir()
        marker = native / "previous-build"
        marker.write_bytes(b"known-good native app")
        before = digest(marker)
        compiler = fixture / "swiftc-fixture"
        compiler.write_text("""#!/usr/bin/env python3
import os, shutil, sys
shutil.copy2(os.environ['MOA_FIXTURE_BINARY'], sys.argv[sys.argv.index('-o') + 1])
""")
        compiler.chmod(0o755)
        environment = dict(
            os.environ,
            SWIFTC=str(compiler),
            MOA_FIXTURE_BINARY=str(binary),
            APP_ARCH="x86_64",
            APP_VERSION="1.6.2",
            APP_BUILD="128",
            MACOS_DEPLOYMENT_TARGET="12.0",
            CODE_SIGN_IDENTITY="-",
        )
        result = subprocess.run(
            ["bash", str(fixture / "scripts/build-menu-bar-app.sh")],
            env=environment,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, result.stderr
        assert digest(marker) == before
        side = fixture / "build/macos-x86_64/Moa.app/Contents/MacOS/Moa"
        assert side.exists(), result.stderr
        archs = subprocess.check_output(["/usr/bin/lipo", "-archs", str(side)], text=True).strip()
        assert archs == "x86_64", archs
        assert not list(fixture.glob(".moa-build.*"))
        print("PASS: cross-arch", flush=True)


def local_signing_identity_survives_a_rebuild():
    root = Path(__file__).resolve().parent.parent
    identity = os.environ.get("MOA_CODE_SIGN_IDENTITY", "Moa Local Development Code Signing")
    environment = dict(os.environ, CODE_SIGN_IDENTITY=identity)
    resolve = subprocess.run(
        ["/bin/bash", "-c", 'source "$1"; moa_resolve_signing_identity', "fixture", str(root / "scripts/code-signing.env")],
        env=environment, capture_output=True, text=True, timeout=15,
    )
    if resolve.returncode:
        print("SKIP: local-signing continuity (no unique local identity installed)", flush=True)
        return
    with tempfile.TemporaryDirectory(prefix="moa-signing-continuity-") as temporary:
        base = Path(temporary)
        binaries = []
        requirements = []
        for revision in [1, 2]:
            source = base / f"revision-{revision}.c"
            source.write_text(f"int main(void) {{ return {revision}; }}\n")
            binary = base / f"revision-{revision}"
            subprocess.run(["/usr/bin/xcrun", "clang", str(source), "-o", str(binary)], check=True)
            subprocess.run(
                ["/bin/bash", "-e", "-c", 'source "$1"; moa_resolve_signing_identity; moa_codesign "$2" --identifier com.moarliu.moa',
                 "fixture", str(root / "scripts/code-signing.env"), str(binary)],
                env=environment, check=True, capture_output=True, text=True, timeout=20,
            )
            detail = subprocess.run(["/usr/bin/codesign", "-dr", "-", str(binary)], capture_output=True, text=True, check=True)
            output = detail.stdout + detail.stderr
            requirements.append(next(line[len("designated => "):] for line in output.splitlines() if line.startswith("designated => ")))
            binaries.append(binary)
        assert digest(binaries[0]) != digest(binaries[1]), "Fixture revisions must differ"
        assert requirements[0] == requirements[1], requirements
        assert "cdhash" not in requirements[0], requirements[0]
        subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "-R=" + requirements[0], str(binaries[1])], check=True)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(binaries[1])], check=True, capture_output=True)
        downgrade = subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "-R=" + requirements[0], str(binaries[1])], capture_output=True)
        assert downgrade.returncode != 0, "An ad-hoc replacement must fail the original certificate requirement"
        print("PASS: local-signing continuity and ad-hoc downgrade rejection", flush=True)


if __name__ == "__main__":
    main()
    cross_arch_does_not_replace_native_app()
    local_signing_identity_survives_a_rebuild()

