import json
import runpy
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "patch-rea-ghidra.py"
NAMESPACE = runpy.run_path(str(SCRIPT))
PatchError = NAMESPACE["PatchError"]
patch_package = NAMESPACE["patch_package"]
patch_policy = NAMESPACE["patch_policy"]

POLICY = """export const SUPPORTED_GHIDRA_VERSION = "12.1.4";
export const ghidraReleaseCompatibility = (raw) => {
    const version = parseGhidraRelease(raw);
    if (version === undefined) return { status: "unresolved", raw };
    if (raw === SUPPORTED_GHIDRA_VERSION)
        return { status: "verified", version, raw };
    const verified = verifiedGhidraRelease();
    return version.major === verified.major && version.minor === verified.minor
        ? { status: "compatible", version, raw }
        : { status: "unsupported", version, raw };
};
/** Release line accepted by this bridge, such as `12.1.x`. */
export const ghidraReleaseLine = () => {
    const verified = verifiedGhidraRelease();
    return `${String(verified.major)}.${String(verified.minor)}.x`;
};
"""


class ReaPolicyPatchTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.temporary.cleanup()

    def make_package(self, version="6.3.0", policy=POLICY):
        root = Path(self.temporary.name)
        policy_path = root / "dist" / "ghidra" / "GhidraInstallationPolicy.js"
        policy_path.parent.mkdir(parents=True)
        (root / "package.json").write_text(
            json.dumps({"name": "rea-agents", "version": version}), encoding="utf-8"
        )
        policy_path.write_text(policy, encoding="utf-8")
        return root

    def test_adds_compatible_release_and_is_idempotent(self):
        first = patch_policy(POLICY, "12.2")
        self.assertIn('export const SUPPORTED_GHIDRA_VERSION = "12.1.4";', first)
        self.assertIn('const BUNDLE_GHIDRA_VERSION = "12.2";', first)
        self.assertIn("sameVerifiedLine || raw === BUNDLE_GHIDRA_VERSION", first)
        self.assertIn(".x or ${BUNDLE_GHIDRA_VERSION}`", first)
        self.assertEqual(first, patch_policy(first, "12.2"))

    def test_rejects_another_ghidra_version_without_writing(self):
        root = self.make_package()
        policy_path = root / "dist" / "ghidra" / "GhidraInstallationPolicy.js"
        with self.assertRaises(PatchError):
            patch_package(root, "12.2.1")
        self.assertEqual(POLICY, policy_path.read_text(encoding="utf-8"))

    def test_rejects_another_rea_version(self):
        root = self.make_package(version="6.7.0")
        with self.assertRaises(PatchError):
            patch_package(root, "12.2")

    def test_rejects_unexpected_policy_source_without_writing(self):
        changed = POLICY.replace(
            "version.minor === verified.minor", "version.minor !== verified.minor"
        )
        root = self.make_package(policy=changed)
        policy_path = root / "dist" / "ghidra" / "GhidraInstallationPolicy.js"
        with self.assertRaises(PatchError):
            patch_package(root, "12.2")
        self.assertEqual(changed, policy_path.read_text(encoding="utf-8"))

    def test_rejects_changes_outside_patch_anchors(self):
        installed_path = (
            Path(__file__).resolve().parents[1]
            / ".rea" / "node_modules" / "rea-agents" / "dist" / "ghidra"
            / "GhidraInstallationPolicy.js"
        )
        if not installed_path.is_file():
            self.skipTest("rea-agents is not installed")
        installed = installed_path.read_text(encoding="utf-8")
        changed = installed.replace("major >= requirement.minimumMajor", "true")
        self.assertNotEqual(installed, changed)
        root = self.make_package(policy=changed)
        policy_path = root / "dist" / "ghidra" / "GhidraInstallationPolicy.js"
        with self.assertRaises(PatchError):
            patch_package(root, "12.2")
        self.assertEqual(changed, policy_path.read_text(encoding="utf-8"))

    def test_rejects_a_partial_patch(self):
        root = self.make_package()
        policy_path = root / "dist" / "ghidra" / "GhidraInstallationPolicy.js"
        partial = patch_policy(POLICY, "12.2").replace(
            "    const sameVerifiedLine = version.major === verified.major && version.minor === verified.minor;\n",
            "",
        )
        policy_path.write_text(partial, encoding="utf-8")
        with self.assertRaises(PatchError):
            patch_package(root, "12.2")
        self.assertEqual(partial, policy_path.read_text(encoding="utf-8"))

    def test_real_installed_policy_when_available(self):
        policy_path = (
            Path(__file__).resolve().parents[1]
            / ".rea" / "node_modules" / "rea-agents" / "dist" / "ghidra"
            / "GhidraInstallationPolicy.js"
        )
        if not policy_path.is_file():
            self.skipTest("rea-agents is not installed")
        original = policy_path.read_text(encoding="utf-8")
        patched = patch_policy(original, "12.2")
        self.assertIn('export const SUPPORTED_GHIDRA_VERSION = "12.1.4";', patched)
        self.assertIn("sameVerifiedLine || raw === BUNDLE_GHIDRA_VERSION", patched)
        self.assertIn(".x or ${BUNDLE_GHIDRA_VERSION}`", patched)
        self.assertEqual(patched, patch_policy(patched, "12.2"))


if __name__ == "__main__":
    unittest.main()
