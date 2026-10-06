#!/usr/bin/env python3
"""Build and run native Windows ARM64 M0 probes; preserve exact run evidence."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

REPO = Path(__file__).resolve().parent.parent
WORK = Path(os.environ.get("AOE2_WORK_ROOT", Path.home() / "aoe2-poc-work"))
BUILD = WORK / "build/wine-m0"
COMPILER = WORK / "toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin/aarch64-w64-mingw32-clang"
READOBJ = COMPILER.with_name("llvm-readobj")
STAMP = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
RUN = WORK / "runs" / ("m0-" + STAMP)
RUN.mkdir(parents=True)
PREFIX = RUN / "prefix"
ENV = os.environ.copy()
for key in list(ENV):
    if key.startswith("WINE") or key in {"DYLD_LIBRARY_PATH", "DYLD_FRAMEWORK_PATH", "DYLD_INSERT_LIBRARIES", "DYLD_FALLBACK_LIBRARY_PATH"}:
        del ENV[key]
ENV.update(WINEPREFIX=str(PREFIX), WINESERVER=str(BUILD / "server/wineserver"),
           WINEDEBUG="-all", AOE2_M0_DIAGNOSTICS="1")
RESULTS = []

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def command(args, env=None, cwd=None, timeout=30):
    proc = subprocess.Popen([str(a) for a in args], env=env, cwd=cwd,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            start_new_session=True)
    try:
        out, err = proc.communicate(timeout=timeout)
        return proc.returncode, out.decode(errors="replace"), err.decode(errors="replace"), False
    except subprocess.TimeoutExpired:
        # Wine services can retain client pipes after the launcher has exited.
        # Stop only this run's server as well; never kill an unrelated prefix.
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            if proc.poll() is None:
                proc.kill()
        if env and env.get("WINEPREFIX", "").startswith(str(RUN) + os.sep):
            subprocess.run([str(BUILD / "server/wineserver"), "-k"], env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        out, err = proc.communicate(timeout=10)
        return proc.returncode, out.decode(errors="replace"), err.decode(errors="replace"), True

def case(test_id, binary, args, expected_code=0, expected_line=None, timeout=30, env=None, expected_fault=None):
    cwd = RUN / test_id
    cwd.mkdir()
    started = datetime.datetime.now(datetime.timezone.utc)
    cmd = [BUILD / "loader/wine", binary, *args]
    code, out, err, expired = command(cmd, env=env or ENV, cwd=cwd, timeout=timeout)
    (cwd / "stdout.log").write_text(out)
    (cwd / "stderr.log").write_text(err)
    passed = not expired and code == expected_code and (expected_line is None or expected_line in out.splitlines()) and ((expected_fault in err) if expected_fault else "Unhandled" not in err)
    result = dict(test_id=test_id, command=list(map(str, cmd)), cwd=str(cwd),
                  prefix=(env or ENV)["WINEPREFIX"], exit_code=code, timeout=expired,
                  expected_exit=expected_code, expected_line=expected_line, expected_fault=expected_fault,
                  environment_overrides={k:(env or ENV)[k] for k in ["WINEDLLOVERRIDES"] if k in (env or ENV)}, passed=passed,
                  utc=started.isoformat(), seconds=(datetime.datetime.now(datetime.timezone.utc)-started).total_seconds())
    RESULTS.append(result)
    print(("PASS " if passed else "FAIL ") + test_id + f" (exit {code})", flush=True)
    if not passed:
        print(err[-3000:], flush=True)
    return passed

try:
    for exe in [BUILD / "loader/wine", BUILD / "server/wineserver"]:
        if not exe.is_file():
            raise RuntimeError(f"Missing {exe}; run scripts/build-wine.sh first")
        description = subprocess.check_output(["file", str(exe)], text=True)
        if ("Mach-O 64-bit executable arm64" not in description or
            subprocess.check_output(["xcrun", "lipo", "-archs", str(exe)], text=True).strip() != "arm64"):
            raise RuntimeError(f"Expected a thin ARM64 host executable: {description}")
    for stem, src in [("hello", REPO / "tests/hello-a64/a64_hello.c"),
                      ("runtime", REPO / "tests/m0/runtime.c")]:
        exe = RUN / (stem + ".exe")
        subprocess.run([str(COMPILER), "-O1", "-g", "-Wall", "-Wextra", "-Werror", "-fms-extensions", "-Xclang", "-fasync-exceptions", str(src), "-o", str(exe)], check=True)
        inspect = subprocess.check_output([str(READOBJ), "--file-headers", "--coff-imports", str(exe)], text=True)
        (RUN / (stem + "-headers.txt")).write_text(inspect)
        if "IMAGE_FILE_MACHINE_ARM64 (0xAA64)" not in inspect:
            raise RuntimeError(f"{exe} is not plain ARM64 PE")
    if case("A64-HELLO", RUN / "hello.exe", [], 23, "A64-HELLO OK", 120):
        for name in ["memory", "shared", "threads", "callback", "exceptions", "io"]:
            case({"memory":"A64-MEM", "threads":"A64-THREAD", "exceptions":"A64-SEH"}.get(name, "A64-" + name.upper()), RUN / "runtime.exe", [name], expected_line="M0 " + name + " PASS")
        unhandled = ENV.copy()
        # The negative fixture must terminate, rather than launch an interactive debugger.
        unhandled["WINEDLLOVERRIDES"] = "winedbg.exe=d"
        case("A64-SEH-UNHANDLED", RUN / "runtime.exe", ["unhandled"], 5,
             env=unhandled, expected_fault="Unhandled page fault on write access to 0000000000001234")
        for i in range(20):
            if not case(f"A64-REPEAT-{i+1:02d}", RUN / "hello.exe", [], 23, "A64-HELLO OK"):
                break
        fresh = ENV.copy()
        fresh["WINEPREFIX"] = str(RUN / "fresh-prefix")
        case("A64-FRESH", RUN / "hello.exe", [], 23, "A64-HELLO OK", 120, fresh)
        # A Windows API call must cross into native mode; native logs also prove
        # kernel page size and process translation state in the executing host.
        diagnostics = (RUN / "A64-HELLO/stderr.log").read_text()
        callback_log = (RUN / "A64-CALLBACK/stderr.log").read_text()
        native = ("M0-NATIVE pages=4096 custom_x18=0 translated=0" in diagnostics and
                  "M0-UNIX-CLOCK pages=4096 custom_x18=0" in callback_log)
        RESULTS.append(dict(test_id="HOST-NATIVE", passed=native,
                            expected="native Wine boundary reports 4096/false/not translated"))
        print(("PASS " if native else "FAIL ") + "HOST-NATIVE", flush=True)
except Exception as exc:
    RESULTS.append(dict(test_id="HARNESS", passed=False, error=str(exc)))
    print("FAIL HARNESS:", exc, flush=True)
finally:
    for prefix in [PREFIX, RUN / "fresh-prefix"]:
        if prefix.exists():
            cleanup = ENV.copy()
            cleanup["WINEPREFIX"] = str(prefix)
            code, out, err, expired = command([BUILD / "server/wineserver", "-k"], env=cleanup)
            # Wine returns 1 when there is no server lock owner to signal.
            # The independent -w check below must still confirm termination.
            kill_ok = not expired and code in (0, 1) and not err
            wait_code, wait_out, wait_err, wait_expired = command([BUILD / "server/wineserver", "-w"], env=cleanup)
            (RUN / (prefix.name + "-cleanup.log")).write_text(
                f"kill_exit={code} kill_timeout={expired}\n{out}{err}"
                f"wait_exit={wait_code} wait_timeout={wait_expired}\n{wait_out}{wait_err}")
            RESULTS.append(dict(test_id="SERVER-CLEANUP-" + prefix.name,
                                passed=kill_ok and not wait_expired and wait_code == 0,
                                kill_exit=code, wait_exit=wait_code, timeout=expired or wait_expired))
    source = WORK / "sources/wine-m0"
    report = dict(utc=STAMP, host=subprocess.check_output(["sw_vers"], text=True),
                  architecture=subprocess.check_output(["uname", "-m"], text=True).strip(),
                  sdk=subprocess.check_output(["xcrun", "--show-sdk-version"], text=True).strip(),
                  compiler=subprocess.check_output([str(COMPILER), "--version"], text=True),
                  probe_flags=["-O1", "-g", "-Wall", "-Wextra", "-Werror", "-fms-extensions", "-Xclang", "-fasync-exceptions"],
                  source_lock_sha256=digest(REPO / "sources.lock.json"),
                  source_commit=subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip(),
                  source_diff_sha256=hashlib.sha256(subprocess.check_output(["git", "-C", str(source), "diff", "--binary"])).hexdigest(),
                  artifacts={str(p):digest(p) for p in [BUILD / "loader/wine", BUILD / "server/wineserver", BUILD / "dlls/ntdll/ntdll.so", RUN / "hello.exe", RUN / "runtime.exe"] if p.is_file()},
                  environment={k:ENV[k] for k in ["WINEPREFIX", "WINESERVER", "WINEDEBUG", "AOE2_M0_DIAGNOSTICS"]},
                  results=RESULTS)
    (RUN / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print("Evidence:", RUN, flush=True)
if len(RESULTS) != 32 or not all(r["passed"] for r in RESULTS):
    sys.exit(1)
