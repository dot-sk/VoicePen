"""Copy the built app and make a bounded bundle-only hosted test run."""
import argparse
import plistlib
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--xctestrun", type=Path, required=True)
parser.add_argument("--app", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=False)
app = args.output.resolve() / "VoicePen.app"
subprocess.run(["/usr/bin/ditto", str(args.app), str(app)], check=True)
with args.xctestrun.open("rb") as source:
    run = plistlib.load(source)
frameworks = str(app / "Contents/Frameworks")
libraries = str(app / "Contents/MacOS")
for configuration in run["TestConfigurations"]:
    for target in configuration["TestTargets"]:
        bundle = str(app / "Contents/PlugIns/VoicePenIntegrationTests.xctest")
        target["TestHostPath"] = str(app)
        target["TestBundlePath"] = bundle
        target["DependentProductPaths"] = [str(app), bundle]
        target["TestTimeoutsEnabled"] = True
        target["DefaultTestExecutionTimeAllowance"] = 120
        target["MaximumTestExecutionTimeAllowance"] = 180
        for key in ["EnvironmentVariables", "TestingEnvironmentVariables"]:
            environment = target.setdefault(key, {})
            environment["DYLD_FRAMEWORK_PATH"] = frameworks + ":__SHAREDFRAMEWORKS__:__PLATFORMS__/MacOSX.platform/Developer/Library/Frameworks"
            environment["DYLD_LIBRARY_PATH"] = libraries + ":__PLATFORMS__/MacOSX.platform/Developer/usr/lib"
            environment["__XPC_DYLD_FRAMEWORK_PATH"] = frameworks
            environment["__XPC_DYLD_LIBRARY_PATH"] = libraries
            environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] = str(app.parent)
            environment["VOICEPEN_GIGAAM_REQUIRE_APP_BUNDLE"] = "1"
            environment["PATH"] = "/usr/bin:/bin"
            for override in ["GGML_METAL_PATH_RESOURCES", "GGML_METAL_PATH_SOURCE"]:
                environment.pop(override, None)
with (args.output / "relocated.xctestrun").open("wb") as output:
    plistlib.dump(run, output)
print(args.output / "relocated.xctestrun")
