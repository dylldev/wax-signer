"""Run: python3 -m unittest -v Server/wax-ota/test_install_script.py (nothing is installed; the script runs in --dry-run)."""
import os, re, subprocess, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "install.sh")

def run(*args):
    return subprocess.run(["bash", SCRIPT, *args], capture_output=True, text=True)

class InstallScript(unittest.TestCase):
    def test_script_parses(self):
        self.assertEqual(subprocess.run(["bash", "-n", SCRIPT]).returncode, 0)

    def test_dry_run_prints_every_step_and_changes_nothing(self):
        r = run("--dry-run", "wax.example.test"); out = r.stdout
        self.assertEqual(r.returncode, 0, r.stderr)
        for step in ("apt-get install -y caddy", "systemctl enable --now wax-ota", "systemctl enable --now fail2ban",
                     "write /etc/wax-ota.env (mode 600)", "write /etc/caddy/Caddyfile"):
            self.assertIn(step, out)

    def test_only_ssh_http_and_https_are_opened(self):
        allowed = re.findall(r"^\+ ufw allow (\S+)", run("--dry-run", "wax.example.test").stdout, re.M)
        self.assertEqual(allowed, ["22/tcp", "80/tcp", "443/tcp"])

    def test_caddy_gpg_key_fingerprint_is_pinned(self):
        with open(SCRIPT) as f:
            self.assertIn("155B 6D79 CA56 EA34", f.read())

    def test_the_printed_line_has_the_setup_format_and_no_real_token(self):
        out = run("--dry-run", "wax.example.test").stdout
        self.assertRegex(out, r"(?m)^WAXINSTALL1 https://wax\.example\.test <random 40-character token>$")

    def test_caddyfile_has_exactly_the_two_routes_and_a_404_fallback(self):
        out = run("--dry-run", "wax.example.test").stdout
        site = out[out.index("wax.example.test {"):out.index("+ write /etc/caddy/Caddyfile")]
        self.assertEqual(re.findall(r"^\thandle( \S+)? \{", site, re.M), [" /ota-up/*", " /ota/*", ""])
        self.assertIn("respond 404", site)
        self.assertNotIn("{{DOMAIN}}", out)
        self.assertNotIn("browse", site)           # directories are not listed
        self.assertNotIn("log", site)              # paths contain the secret id

    def test_the_upload_service_is_only_reachable_through_the_proxy(self):
        out = run("--dry-run", "wax.example.test").stdout
        self.assertIn("reverse_proxy 127.0.0.1:8091", out)
        self.assertNotRegex(out, r"ufw allow 8091")

    def test_bad_domains_are_refused(self):
        for bad in ("", "localhost", "a b.example", "x.example;rm -rf /", "-a.example", "http://x.example"):
            r = run("--dry-run", bad) if bad else run("--dry-run")
            self.assertNotEqual(r.returncode, 0, bad)

    def test_without_dry_run_it_refuses_to_run_as_a_normal_user(self):
        if os.geteuid() == 0: self.skipTest("running as root")
        r = run("wax.example.test")
        self.assertNotEqual(r.returncode, 0); self.assertIn("sudo", r.stderr)

if __name__ == "__main__":
    unittest.main()
