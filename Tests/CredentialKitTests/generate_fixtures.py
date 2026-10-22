#!/usr/bin/env python3
"""Regenerates FixtureData.swift. Everything here is a throwaway, fixture-only credential:
self-signed, random keys created at generation time, password is a public test string.
Run: python3 generate_fixtures.py   (needs `cryptography` and an `openssl` with `cms -stream`)"""
import base64, datetime as dt, os, plistlib, subprocess, tempfile
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12, pkcs7
from cryptography.x509.oid import NameOID

PW = b"fixture-pw"
NOW = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
DAY = dt.timedelta(days=1)

def make(team, cn, nb, na):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([
        x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, f"Fixture Team {team}"),
        x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, team),
        x509.NameAttribute(NameOID.COMMON_NAME, cn),
    ])
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
            .public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(nb).not_valid_after(na)
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
            .add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False, key_encipherment=False,
                data_encipherment=False, key_agreement=False, key_cert_sign=False, crl_sign=False,
                encipher_only=False, decipher_only=False), critical=True)
            .add_extension(x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.CODE_SIGNING]), critical=True)
            .sign(key, hashes.SHA256()))
    return key, cert

TEAM, OTHER = "FIXT123456", "OTHR654321"
keyA, certA = make(TEAM, "Apple Development: Fixture Tester (AAAA111111)", NOW - DAY, NOW + 3650 * DAY)
keyB, certB = make(TEAM, "Apple Development: Fixture Second (BBBB222222)", NOW - DAY, NOW + 3650 * DAY)
keyO, certO = make(OTHER, "Apple Development: Other Team (CCCC333333)", NOW - DAY, NOW + 3650 * DAY)
keyE, certE = make(TEAM, "Apple Development: Fixture Expired (DDDD444444)", NOW - 1000 * DAY, NOW - 100 * DAY)
keyF, certF = make(TEAM, "Apple Development: Fixture Future (EEEE555555)", NOW + 400 * DAY, NOW + 4000 * DAY)

def p12_modern(key, cert):
    return pkcs12.serialize_key_and_certificates(b"fixture", key, cert, None,
        serialization.BestAvailableEncryption(PW))

def p12_legacy(key, cert):
    enc = (serialization.PrivateFormat.PKCS12.encryption_builder()
           .kdf_rounds(2048).key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
           .hmac_hash(hashes.SHA1()).build(PW))
    return pkcs12.serialize_key_and_certificates(b"fixture", key, cert, None, enc)

der = lambda c: c.public_bytes(serialization.Encoding.DER)

def profile_plist(certs, team=TEAM, uuid="11111111-2222-3333-4444-555555555555", devices=("0000FIXTURE-DEVICE-0001", "0000FIXTURE-DEVICE-0002"),
                  all_devices=False, task_allow=True, expires=None, drop=(), name="Fixture Dev Profile",
                  app_id="com.example.fixture", platform="iOS", extra_ents=None):
    d = {
        "AppIDName": "Fixture App", "ApplicationIdentifierPrefix": [team],
        "CreationDate": NOW - DAY, "Platform": [platform],
        "DeveloperCertificates": [der(c) for c in certs],
        "Entitlements": {"application-identifier": f"{team}.{app_id}",
                         "com.apple.developer.team-identifier": team, "get-task-allow": task_allow},
        "ExpirationDate": expires or (NOW + 300 * DAY), "Name": name,
        "TeamIdentifier": [team], "TeamName": f"Fixture Team {team}",
        "TimeToLive": 300, "UUID": uuid, "Version": 1,
    }
    if extra_ents: d["Entitlements"].update(extra_ents)
    if devices: d["ProvisionedDevices"] = list(devices)
    if all_devices: d["ProvisionsAllDevices"] = True
    for k in drop: d.pop(k, None)
    return plistlib.dumps(d, fmt=plistlib.FMT_XML)

def cms_ber(content, key, cert):
    """openssl cms -stream: BER indefinite-length, like Apple-issued profiles."""
    with tempfile.TemporaryDirectory() as t:
        open(f"{t}/c", "wb").write(content)
        open(f"{t}/k", "wb").write(key.private_bytes(serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        open(f"{t}/s", "wb").write(cert.public_bytes(serialization.Encoding.PEM))
        subprocess.run(["openssl", "cms", "-sign", "-binary", "-stream", "-nodetach", "-outform", "DER",
                        "-in", f"{t}/c", "-signer", f"{t}/s", "-inkey", f"{t}/k", "-out", f"{t}/o"], check=True)
        return open(f"{t}/o", "rb").read()

def cms_der(content, key, cert):
    return pkcs7.PKCS7SignatureBuilder().set_data(content).add_signer(cert, key, hashes.SHA256()).sign(
        serialization.Encoding.DER, [pkcs7.PKCS7Options.Binary])

out = {
    "p12ValidModern": p12_modern(keyA, certA),
    "p12ValidLegacy": p12_legacy(keyA, certA),
    "p12SecondIdentity": p12_legacy(keyB, certB),
    "p12OtherTeam": p12_legacy(keyO, certO),
    "p12Expired": p12_legacy(keyE, certE),
    "p12NotYetValid": p12_legacy(keyF, certF),
    "p12CertOnly": pkcs12.serialize_key_and_certificates(b"fixture", None, certA, None, serialization.BestAvailableEncryption(PW)),
    "p12Malformed": os.urandom(300),
    "p12Truncated": p12_legacy(keyA, certA)[:400],
    "certADER": der(certA),
    "certBDER": der(certB),
    "profileValidBER": cms_ber(profile_plist([certA]), keyA, certA),
    "profileValidDER": cms_der(profile_plist([certA], uuid="22222222-2222-3333-4444-555555555555"), keyA, certA),
    "profileAdHoc": cms_ber(profile_plist([certA], uuid="33333333-2222-3333-4444-555555555555", task_allow=False), keyA, certA),
    "profileEnterprise": cms_ber(profile_plist([certA], uuid="44444444-2222-3333-4444-555555555555", devices=(), all_devices=True, task_allow=False), keyA, certA),
    "profileAppStore": cms_ber(profile_plist([certA], uuid="55555555-2222-3333-4444-555555555555", devices=(), task_allow=False), keyA, certA),
    "profileExpired": cms_ber(profile_plist([certA], uuid="66666666-2222-3333-4444-555555555555", expires=NOW - 10 * DAY), keyA, certA),
    "profileListsOtherCert": cms_ber(profile_plist([certB], uuid="77777777-2222-3333-4444-555555555555"), keyA, certA),
    "profileTeamMismatch": cms_ber(profile_plist([certA], team=OTHER, uuid="88888888-2222-3333-4444-555555555555"), keyA, certA),
    "profileMissingUUID": cms_ber(profile_plist([certA], drop=("UUID",)), keyA, certA),
    "profileWildcardAll": cms_ber(profile_plist([certA], uuid="99999999-2222-3333-4444-555555555555", app_id="*", name="Fixture Wildcard"), keyA, certA),
    "profileWildcardPrefix": cms_ber(profile_plist([certA], uuid="AAAAAAAA-2222-3333-4444-555555555555", app_id="com.example.*", name="Fixture Prefix"), keyA, certA),
    "profileExactTestApp": cms_ber(profile_plist([certA], uuid="BBBBBBBB-2222-3333-4444-555555555555", app_id="dev.localsigner.testapp", name="Fixture Exact"), keyA, certA),
    "profileExactTestExt": cms_ber(profile_plist([certA], uuid="CCCCCCCC-2222-3333-4444-555555555555", app_id="dev.localsigner.testapp.TestExt", name="Fixture Exact Ext"), keyA, certA),
    "profileRich": cms_ber(profile_plist([certA], uuid="DDDDDDDD-2222-3333-4444-555555555555", app_id="*", name="Fixture Rich",
        extra_ents={"com.apple.security.application-groups": ["group.com.example.shared", "group.com.example.team.*"],
                    "com.apple.developer.associated-domains": ["*"],
                    "keychain-access-groups": [TEAM + ".*"]}), keyA, certA),
    "profileTvOS": cms_ber(profile_plist([certA], uuid="EEEEEEEE-2222-3333-4444-555555555555", app_id="*", name="Fixture tvOS", platform="tvOS"), keyA, certA),
    "profileNotCMS": os.urandom(300),
    "profileCMSNotPlist": cms_ber(b"this is not a property list", keyA, certA),
    "profileUnsignedPlist": profile_plist([certA]),
}

lines = ["// Generated by generate_fixtures.py. Throwaway, fixture-only credentials. Do not use for anything real.",
         "import Foundation", "", "enum FixtureData {", '    static let password = "fixture-pw"',
         f'    static let teamID = "{TEAM}"', f'    static let otherTeamID = "{OTHER}"']
for k, v in out.items():
    lines.append(f'    static let {k} = Data(base64Encoded: "{base64.b64encode(v).decode()}")!')
lines.append("}")
for d in (os.path.dirname(os.path.abspath(__file__)), os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "SigningKitTests")):
    open(os.path.join(d, "FixtureData.swift"), "w").write("\n".join(lines) + "\n")
print({k: len(v) for k, v in out.items()})
