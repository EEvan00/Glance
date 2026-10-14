#!/usr/bin/env python3
"""Offline configuration and helper packaging tests; no credentials or install actions."""
import os
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


class SigningConfigurationTests(unittest.TestCase):
    def run_config(self, identity_output=None, **changes):
        environment = os.environ.copy()
        for name in ("CODE_SIGN_IDENTITY", "INSTALLER_SIGN_IDENTITY", "NOTARY_PROFILE", "KEYCHAIN_PATH",
                     "WEATHERKIT_ENABLED", "WEATHERKIT_PROVISIONING_PROFILE", "WEATHER_SERVICE_URL"):
            environment.pop(name, None)
        environment.update(changes)
        with tempfile.TemporaryDirectory(prefix="GlanceSigningIdentityTest-") as directory:
            if identity_output is not None:
                # Replace the read-only identity inventory, never import/create a
                # real key. This tests configuration gates, not Apple's trust.
                security = pathlib.Path(directory) / "security"
                security.write_text("#!/bin/sh\ncat <<'IDENTITIES'\n" + identity_output + "\nIDENTITIES\n")
                security.chmod(0o755)
                environment["PATH"] = directory + os.pathsep + environment["PATH"]
            return subprocess.run(["bash", str(ROOT / "scripts/validate-signing-configuration.sh")],
                                  env=environment, text=True, capture_output=True)

    def assert_rejected(self, message, **configuration):
        result = self.run_config(**configuration)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn(message, result.stderr)

    def test_adhoc_default_needs_no_apple_credentials(self):
        result = self.run_config()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_explicit_empty_identity_is_rejected(self):
        self.assert_rejected("must not be empty", CODE_SIGN_IDENTITY="")

    def test_notarization_requires_developer_id(self):
        self.assert_rejected("requires Developer ID Application", NOTARY_PROFILE="unused-test-profile")

    def test_installer_identity_without_application_identity_is_rejected(self):
        self.assert_rejected("requires certificate-backed application signing",
                             INSTALLER_SIGN_IDENTITY="unused-test-identity")

    def test_developer_id_requires_installer_certificate_for_migration_package(self):
        self.assert_rejected("requires INSTALLER_SIGN_IDENTITY", CODE_SIGN_IDENTITY="Developer ID Application: Unavailable Test")

    def test_invalid_explicit_identity_is_rejected_before_build(self):
        self.assert_rejected("not available", CODE_SIGN_IDENTITY="unavailable-test-identity")

    def test_matching_developer_id_identities_pass_configuration_validation(self):
        app = "Developer ID Application: Offline Test (TESTTEAM00)"
        installer = "Developer ID Installer: Offline Test (TESTTEAM00)"
        inventory = f' 1) {"0" * 40} "{app}"\n 2) {"1" * 40} "{installer}"'
        result = self.run_config(identity_output=inventory, CODE_SIGN_IDENTITY=app,
                                 INSTALLER_SIGN_IDENTITY=installer, NOTARY_PROFILE="unused-test-profile")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_developer_id_hash_still_requires_migration_installer_identity(self):
        app = "Developer ID Application: Offline Test (TESTTEAM00)"
        self.assert_rejected("requires INSTALLER_SIGN_IDENTITY", identity_output=f' 1) {"0" * 40} "{app}"',
                             CODE_SIGN_IDENTITY="0" * 40)

    def test_mismatched_application_and_installer_teams_fail_closed(self):
        app = "Developer ID Application: Offline Test (TESTTEAM00)"
        installer = "Developer ID Installer: Offline Test (OTHERTEAM0)"
        inventory = f' 1) {"0" * 40} "{app}"\n 2) {"1" * 40} "{installer}"'
        self.assert_rejected("must belong to the same team", identity_output=inventory,
                             CODE_SIGN_IDENTITY=app, INSTALLER_SIGN_IDENTITY=installer)

    def test_missing_installer_identity_is_rejected(self):
        app = "Developer ID Application: Offline Test (TESTTEAM00)"
        installer = "Developer ID Installer: Offline Test (TESTTEAM00)"
        self.assert_rejected("INSTALLER_SIGN_IDENTITY is not available", identity_output=f' 1) {"0" * 40} "{app}"',
                             CODE_SIGN_IDENTITY=app, INSTALLER_SIGN_IDENTITY=installer)

    def test_development_certificate_does_not_allow_notarization(self):
        app = "Apple Development: Offline Test (TESTTEAM00)"
        self.assert_rejected("require Developer ID Application", identity_output=f' 1) {"0" * 40} "{app}"',
                             CODE_SIGN_IDENTITY=app, NOTARY_PROFILE="unused-test-profile")

    def test_native_weatherkit_is_not_enabled_in_developer_id_distribution(self):
        self.assert_rejected("WeatherKit is unavailable for Developer ID", WEATHERKIT_ENABLED="1")

    def test_public_weather_service_endpoint_is_accepted(self):
        result = self.run_config(WEATHER_SERVICE_URL="https://weather.example.com/v1/weather")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_invalid_weather_endpoints_are_rejected(self):
        for endpoint in ("http://weather.example.com/v1/weather", "https://user@weather.example.com/v1/weather",
                         "https://weather.example.com/v1/weather?key=value", "https://weather.example.com/v1/weather#fragment",
                         "https://weather.example.com/", "https://localhost/v1/weather", "https://127.0.0.1/v1/weather",
                         "https://10.0.0.1/v1/weather", "https://[::1]/v1/weather", "https://host.local/v1/weather",
                         "https://weather.example.com:8443/v1/weather", "https://weather.example.com/v1/weather\n"):
            with self.subTest(endpoint=endpoint):
                self.assert_rejected("WEATHER_SERVICE_URL must be", WEATHER_SERVICE_URL=endpoint)

    def test_profile_input_is_rejected_instead_of_ignored(self):
        self.assert_rejected("WeatherKit is unavailable for Developer ID", WEATHERKIT_PROVISIONING_PROFILE="/no-such-profile")


class HelperPackagingTests(unittest.TestCase):
    def package(self, strategy):
        with tempfile.TemporaryDirectory(prefix="GlanceHelperPackageTest-") as directory:
            app = pathlib.Path(directory) / "Glance.app"
            resources = app / "Contents/Resources"
            resources.mkdir(parents=True)
            shutil.copyfile("/usr/bin/true", resources / "GlanceMagSafeHelper")
            with (app / "Contents/Info.plist").open("wb") as handle:
                plistlib.dump({"CFBundleVersion": "1"}, handle)
            environment = os.environ.copy()
            environment.pop("INSTALLER_SIGN_IDENTITY", None)
            environment.pop("NOTARY_PROFILE", None)
            result = subprocess.run(["bash", str(ROOT / "scripts/build-helper-packages.sh"), str(app), strategy],
                                    env=environment, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return (resources / "GlanceHelperInstall.pkg").exists(), (resources / "GlanceHelperUninstall.pkg").exists()

    def test_adhoc_has_install_and_uninstall_packages(self):
        self.assertEqual(self.package("legacyPackage"), (True, True))

    def test_bundled_service_has_only_migration_uninstaller(self):
        self.assertEqual(self.package("bundledService"), (False, True))

    def test_incomplete_notarization_stops_before_package_generation(self):
        environment = os.environ.copy()
        environment.pop("INSTALLER_SIGN_IDENTITY", None)
        environment["NOTARY_PROFILE"] = "unused-test-profile"
        result = subprocess.run(["bash", str(ROOT / "scripts/build-helper-packages.sh"), "/no-such-app", "bundledService"],
                                env=environment, text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("requires INSTALLER_SIGN_IDENTITY", result.stderr)

    def test_unknown_packaging_strategy_is_rejected(self):
        result = subprocess.run(["bash", str(ROOT / "scripts/build-helper-packages.sh"), "/no-such-app", "unknown"],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
