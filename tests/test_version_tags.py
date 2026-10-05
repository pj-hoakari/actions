"""Exercise the action entrypoints against real Git tags and metadata inputs."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def outputs(path):
    lines = path.read_text().splitlines()
    result = {}
    while lines:
        line = lines.pop(0)
        if "<<" in line:
            name, delimiter = line.split("<<", 1)
            value = []
            while lines[0] != delimiter:
                value.append(lines.pop(0))
            lines.pop(0)
            result[name] = "\n".join(value).rstrip("\n")
        else:
            name, value = line.split("=", 1)
            result[name] = value
    return result


class ActionTests(unittest.TestCase):
    def invoke(self, script, cwd, **inputs):
        output = Path(cwd) / "action-output"
        output.write_text("")
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(("INPUT_", "GITHUB_"))}
        env.update(inputs, GITHUB_OUTPUT=str(output))
        result = subprocess.run(["bash", str(ROOT / script)], cwd=cwd,
                                env=env, capture_output=True, text=True)
        return result, outputs(output)


class PrepareTagsTests(ActionTests):
    def prepare(self, **inputs):
        with tempfile.TemporaryDirectory() as directory:
            return self.invoke("publish-image/prepare-tags.sh", directory,
                               INPUT_VERSION="1.2.3", **inputs)

    def test_version_only_preserves_legacy_rules(self):
        result, values = self.prepare()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("auto", values["latest"])
        self.assertEqual("type=semver,pattern={{version}},value=1.2.3\n"
                         "type=sha\ntype=raw,value=latest,enable=true", values["tags"])

    def test_resolved_tags_do_not_enable_implicit_latest(self):
        for suffix in ("", "-jvm"):
            with self.subTest(suffix=suffix):
                result, values = self.prepare(INPUT_TAGS="1.2.3,sha-abcdef0,latest",
                                              INPUT_TAG_SUFFIX=suffix)
                self.assertEqual(0, result.returncode, result.stderr)
                self.assertEqual("false", values["latest"])
                self.assertEqual("type=raw,value=1.2.3\ntype=raw,value=sha-abcdef0\n"
                                 "type=raw,value=latest", values["tags"])

    def test_resolved_prerelease_does_not_add_latest(self):
        result, values = self.prepare(INPUT_TAGS="1.2.3-rc.1,sha-abcdef0", INPUT_TAG_SUFFIX="-jvm")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("false", values["latest"])
        self.assertNotIn("value=latest", values["tags"])

    def test_legacy_prerelease_disables_latest(self):
        with tempfile.TemporaryDirectory() as directory:
            result, values = self.invoke("publish-image/prepare-tags.sh", directory,
                                         INPUT_VERSION="1.2.3-rc.1", INPUT_TAG_SUFFIX="-jvm")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("value=latest,enable=false", values["tags"])

    def test_invalid_metadata_inputs_fail_before_publishing(self):
        cases = [dict(INPUT_TAGS=value) for value in
                 (",latest", "latest,", "1.2.3,,latest", "1.2.3\nlatest", "value,enable=true", "bad tag")]
        cases += [dict(INPUT_TAG_SUFFIX=",onlatest=false"),
                  dict(INPUT_TAGS="a" * 125, INPUT_TAG_SUFFIX="-jvm")]
        for inputs in cases:
            with self.subTest(inputs=inputs):
                result, values = self.prepare(**inputs)
                self.assertNotEqual(0, result.returncode)
                self.assertEqual({}, values)


class ResolveVersionTests(ActionTests):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.work = Path(self.directory.name)
        self.git("init", "--quiet")
        self.git("config", "user.email", "ci@example.invalid")
        self.git("config", "user.name", "CI Test")
        self.git("remote", "add", "origin", str(self.work))
        self.git("commit", "--allow-empty", "--quiet", "-m", "first")
        self.sha = self.git("rev-parse", "HEAD").strip()

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.work, text=True)

    def resolve(self, tag, **inputs):
        return self.invoke("resolve-version/resolve-version.sh", self.work,
                           GITHUB_REF_TYPE="tag", GITHUB_REF_NAME=tag,
                           GITHUB_SHA=self.sha, **inputs)

    def test_tag_is_the_source_of_version_and_image_tags(self):
        self.git("tag", "v1.2.3")
        result, values = self.resolve("v1.2.3")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual({"version": "1.2.3", "tags": f"1.2.3,sha-{self.sha[:7]},latest"}, values)

    def test_annotated_tag_points_to_commit(self):
        self.git("tag", "-a", "v1.2.3", "-m", "release")
        result, _ = self.resolve("v1.2.3")
        self.assertEqual(0, result.returncode, result.stderr)

    def test_prerelease_has_no_latest(self):
        self.git("tag", "v1.2.3-rc.1")
        result, values = self.resolve("v1.2.3-rc.1")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(f"1.2.3-rc.1,sha-{self.sha[:7]}", values["tags"])

    def test_invalid_tag_and_build_metadata_are_rejected(self):
        for tag in ("main", "v1.2", "v1.2.3+build"):
            with self.subTest(tag=tag):
                result, values = self.resolve(tag)
                self.assertNotEqual(0, result.returncode)
                self.assertEqual({}, values)

    def test_missing_remote_tag_is_rejected(self):
        result, _ = self.resolve("v1.2.3")
        self.assertNotEqual(0, result.returncode)

    def test_tag_commit_mismatch_is_rejected(self):
        self.git("tag", "v1.2.3")
        self.git("commit", "--allow-empty", "--quiet", "-m", "second")
        self.sha = self.git("rev-parse", "HEAD").strip()
        result, _ = self.resolve("v1.2.3")
        self.assertNotEqual(0, result.returncode)

    def test_older_version_is_rejected_with_numeric_ordering(self):
        self.git("tag", "v1.2.9")
        self.git("tag", "v1.2.10")
        result, _ = self.resolve("v1.2.9")
        self.assertNotEqual(0, result.returncode)
        result, _ = self.resolve("v1.2.10")
        self.assertEqual(0, result.returncode, result.stderr)


if __name__ == "__main__":
    unittest.main()
