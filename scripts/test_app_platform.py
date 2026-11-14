#!/usr/bin/env python3
"""Run: python3 scripts/test_app_platform.py"""
import importlib.util
import io
import os
import shutil
import tarfile
import tempfile
import unittest

import yaml

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("app_platform", os.path.join(here, "app_platform.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
TEMPLATE = os.path.join(os.path.dirname(here), "apps-platform", "manifest.tpl.yaml")


def make_tar(path, members):
    """members: list of (name, bytes) or prepared TarInfo objects."""
    with tarfile.open(path, "w:gz") as tf:
        for item in members:
            if isinstance(item, tarfile.TarInfo):
                tf.addfile(item)
                continue
            name, data = item
            ti = tarfile.TarInfo(name)
            ti.size = len(data)
            ti.mode = 0o777
            tf.addfile(ti, io.BytesIO(data))


class CheckTest(unittest.TestCase):
    def test_accepts_a_normal_request(self):
        m.check("my-shop", "dev", 31000, "a1b2c3d4-0000")

    def test_refusals(self):
        cases = [
            (("Bad", "dev"), {}, "invalid slug"),
            (("grafana", "dev"), {}, "reserved"),
            (("my-shop", "qa"), {}, "not enabled"),
            (("my-shop", "prod"), {}, "not enabled"),
            (("my-shop", "dev"), {"port": 30999}, "outside"),
            (("my-shop", "dev"), {"port": 31900}, "outside"),
            (("my-shop", "dev"), {"request_id": "x; rm -rf /"}, "request id"),
        ]
        for args, kw, want in cases:
            with self.assertRaises(m.Refused, msg=(args, kw)) as cm:
                m.check(*args, **kw)
            self.assertIn(want, str(cm.exception))


class UnpackTest(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.tar = os.path.join(self.d, "draft.tar.gz")
        self.dest = os.path.join(self.d, "site")

    def tearDown(self):
        shutil.rmtree(self.d)

    def test_extracts_regular_files_with_plain_modes(self):
        make_tar(self.tar, [("index.html", b"<h1>hi</h1>"), ("css/app.css", b"body{}"), ("./js/a.js", b"1")])
        res = m.unpack(self.tar, self.dest)
        self.assertEqual(res["files"], 3)
        with open(os.path.join(self.dest, "css", "app.css"), "rb") as f:
            self.assertEqual(f.read(), b"body{}")
        self.assertTrue(os.path.isfile(os.path.join(self.dest, "js", "a.js")))
        self.assertEqual(os.stat(os.path.join(self.dest, "index.html")).st_mode & 0o777, 0o644)

    def test_refuses_unsafe_names(self):
        for name in ["../evil", "a/../../evil", "/etc/passwd", ".github/workflows/x.yml", ".git/config",
                     ".GitHub/workflows/x.yml", "a\\b", "a/\x01b"]:
            shutil.rmtree(self.dest, ignore_errors=True)
            make_tar(self.tar, [(name, b"x")])
            with self.assertRaises(m.Refused, msg=name):
                m.unpack(self.tar, self.dest)
        self.assertFalse(os.path.exists(os.path.join(self.d, "evil")))

    def test_refuses_links_and_devices(self):
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.CHRTYPE, tarfile.FIFOTYPE):
            shutil.rmtree(self.dest, ignore_errors=True)
            ti = tarfile.TarInfo("link")
            ti.type = kind
            ti.linkname = "/etc/passwd"
            make_tar(self.tar, [ti])
            with self.assertRaises(m.Refused, msg=kind) as cm:
                m.unpack(self.tar, self.dest)
            self.assertIn("regular files", str(cm.exception))

    def test_refuses_too_many_files_and_too_many_bytes(self):
        make_tar(self.tar, [(f"f{i}.txt", b"x") for i in range(m.MAX_FILES + 1)])
        with self.assertRaises(m.Refused) as cm:
            m.unpack(self.tar, self.dest)
        self.assertIn("files", str(cm.exception))
        shutil.rmtree(self.dest)
        old = m.MAX_TOTAL_BYTES
        m.MAX_TOTAL_BYTES = 10
        try:
            make_tar(self.tar, [("a", b"123456"), ("b", b"123456")])
            with self.assertRaises(m.Refused) as cm:
                m.unpack(self.tar, self.dest)
            self.assertIn("larger", str(cm.exception))
        finally:
            m.MAX_TOTAL_BYTES = old

    def test_refuses_an_existing_destination(self):
        make_tar(self.tar, [("index.html", b"x")])
        os.makedirs(self.dest)
        with self.assertRaises(m.Refused):
            m.unpack(self.tar, self.dest)

    def test_empty_archive_gives_an_empty_site(self):
        make_tar(self.tar, [])
        self.assertEqual(m.unpack(self.tar, self.dest)["files"], 0)
        self.assertEqual(os.listdir(self.dest), [])


class RenderTest(unittest.TestCase):
    IMG = "platform.local/app-my-shop:0123abc"

    def test_renders_the_template(self):
        docs = list(yaml.safe_load_all(m.render("my-shop", "dev", 31007, self.IMG, TEMPLATE)))
        dep, svc = docs
        self.assertEqual(dep["metadata"]["namespace"], "app-my-shop")
        pod = dep["spec"]["template"]["spec"]
        self.assertIs(pod["automountServiceAccountToken"], False)
        c = pod["containers"][0]
        self.assertEqual(c["image"], self.IMG)
        self.assertEqual(c["imagePullPolicy"], "Never")
        self.assertIs(c["securityContext"]["allowPrivilegeEscalation"], False)
        self.assertEqual(svc["spec"]["type"], "NodePort")
        self.assertEqual(svc["spec"]["externalTrafficPolicy"], "Local")
        self.assertEqual(svc["spec"]["ports"][0]["nodePort"], 31007)
        self.assertEqual(svc["metadata"]["namespace"], "app-my-shop")

    def test_refuses_foreign_or_malformed_images(self):
        for img in ["platform.local/app-other:0123abc", "ghcr.io/x/app-my-shop:0123abc",
                    "platform.local/app-my-shop:latest", "platform.local/app-my-shop:0123abc\n  privileged: true"]:
            with self.assertRaises(m.Refused, msg=img):
                m.render("my-shop", "dev", 31007, img, TEMPLATE)

    def test_refuses_bad_port_and_env(self):
        with self.assertRaises(m.Refused):
            m.render("my-shop", "dev", 30080, self.IMG, TEMPLATE)
        with self.assertRaises(m.Refused):
            m.render("my-shop", "prod", 31007, self.IMG, TEMPLATE)


if __name__ == "__main__":
    unittest.main()
