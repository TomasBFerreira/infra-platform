#!/usr/bin/env python3
"""Run: python3 scripts/test_app_dns.py"""
import importlib.util
import os
import shutil
import tempfile
import unittest

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("app_dns", os.path.join(here, "app_dns.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
ROOT = os.path.dirname(here)
VARS = os.path.join(ROOT, "ansible/adguard/roles/adguard/vars")


class T(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.apps = os.path.join(self.d, "apps.yml")
        shutil.copy(os.path.join(VARS, "apps-rewrites.yml"), self.apps)
        self.main = os.path.join(VARS, "main.yml")

    def tearDown(self):
        shutil.rmtree(self.d)

    def run_(self, *a):
        return m.run(*a, self.apps, self.main)

    def test_add_is_idempotent(self):
        r = self.run_("add", "shop", "dev")
        self.assertEqual((r["changed"], r["domain"]), (True, "shop-dev.databaes.net"))
        text = open(self.apps).read()
        self.assertIn("  - domain: shop-dev.databaes.net", text)
        self.assertFalse(self.run_("add", "shop", "dev")["changed"])
        self.assertEqual(open(self.apps).read(), text)

    def test_remove_and_noop(self):
        self.run_("add", "shop", "qa")
        self.assertTrue(self.run_("remove", "shop", "qa")["changed"])
        self.assertIn("adguard_apps_qa_rewrites: []", open(self.apps).read())
        self.assertFalse(self.run_("remove", "shop", "qa")["changed"])

    def test_envs_are_separate_and_sorted(self):
        self.run_("add", "zeta", "dev")
        self.run_("add", "alpha", "dev")
        self.run_("add", "alpha", "qa")
        data = m.load_apps(self.apps)
        self.assertEqual(data["adguard_apps_dev_rewrites"], ["zeta-dev.databaes.net", "alpha-dev.databaes.net"][::-1])
        self.assertEqual(data["adguard_apps_qa_rewrites"], ["alpha-qa.databaes.net"])

    def test_refusals(self):
        for slug in ("wedding", "ops-x", "app-x", "my-dev", "Bad", "a", "x/y", ""):
            with self.assertRaises(m.Refused, msg=slug):
                self.run_("add", slug, "dev")
        with self.assertRaises(m.Refused):
            self.run_("add", "shop", "prod")
        before = open(self.apps).read()
        self.assertEqual(open(self.apps).read(), before)

    def test_refuses_hostnames_owned_by_handmade_lists(self):
        # grafana-dev.databaes.net is hand-maintained; a non-reserved slug that
        # lands on an existing hostname must also be refused.
        with self.assertRaises(m.Refused):
            self.run_("add", "grafana", "dev")

    def test_collision_without_reserved_name(self):
        # tomajflix is reserved, so use a domain from main.yml via a temp copy.
        main = os.path.join(self.d, "main.yml")
        open(main, "w").write("adguard_dev_rewrites:\n  - domain: coolapp-dev.databaes.net\n")
        with self.assertRaises(m.Refused):
            m.run("add", "coolapp", "dev", self.apps, main)

    def test_unknown_keys_rejected(self):
        open(self.apps, "w").write("evil: []\n")
        with self.assertRaises(m.Refused):
            self.run_("add", "shop", "dev")


if __name__ == "__main__":
    unittest.main()
