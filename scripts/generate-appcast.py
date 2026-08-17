#!/usr/bin/env python3
"""
Generates the Sparkle appcast.xml for a Bodily release.

Computes an Ed25519 signature over the DMG file and writes a new
<item> entry into appcast.xml with the download URL, version, and
signature. The public key is injected on the first run.

Usage:
  python3 scripts/generate-appcast.py \
      --version 1.0.0 \
      --build 4 \
      --dmg build/Bodily-1.0.0.dmg \
      --download-url "https://github.com/terrancehah/Bodily/releases/download/v1.0.0/Bodily-1.0.0.dmg" \
      --private-key sparkle_private.pem \
      --appcast appcast.xml \
      --release-notes "Initial release"

If --private-key is not provided, the item is added without a signature
(Sparkle will refuse to install unsigned updates — generate keys first).
"""

import argparse
import base64
import hashlib
import os
import sys
from datetime import datetime, timezone
from xml.etree import ElementTree as ET


def sign_dmg(dmg_path: str, private_key_pem: str) -> str:
    """Sign the DMG file with Ed25519 and return the base64-encoded signature."""
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ed25519

    with open(private_key_pem, "rb") as f:
        private_key = serialization.load_pem_private_key(f.read(), password=None)

    with open(dmg_path, "rb") as f:
        dmg_data = f.read()

    signature = private_key.sign(dmg_data)
    return base64.b64encode(signature).decode("ascii")


def extract_public_key(private_key_pem: str) -> str:
    """Extract the base64-encoded Ed25519 public key from a private key file."""
    from cryptography.hazmat.primitives import serialization

    with open(private_key_pem, "rb") as f:
        private_key = serialization.load_pem_private_key(f.read(), password=None)

    public_key = private_key.public_key()
    raw = public_key.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    return base64.b64encode(raw).decode("ascii")


def read_appcast(appcast_path: str) -> ET.ElementTree:
    """Parse the existing appcast.xml, creating a minimal one if absent."""
    ET.register_namespace("sparkle", "http://www.andymatuschak.org/xml-namespaces/sparkle")
    ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")

    if os.path.exists(appcast_path):
        return ET.parse(appcast_path)

    # Create a minimal appcast
    root = ET.Element("rss", version="2.0")
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "Bodily"
    ET.SubElement(channel, "description").text = "Most recent changes with links to updates."
    ET.SubElement(channel, "language").text = "en"
    return ET.ElementTree(root)


def ensure_public_key(channel: ET.Element, public_key: str):
    """Add the Ed25519 public key to the channel if not already present."""
    sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    existing = channel.find(f"{{{sparkle_ns}}}edSignaturePublicKey")
    if existing is None and public_key:
        pk_elem = ET.SubElement(channel, f"{{{sparkle_ns}}}edSignaturePublicKey")
        pk_elem.text = public_key


def add_release_item(channel: ET.Element, version: str, build: str,
                     download_url: str, dmg_path: str,
                     signature: str, release_notes: str, min_system: str = "14.0"):
    """Append a new <item> entry for this release to the channel."""
    sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"

    # Remove any existing item with the same version
    for item in channel.findall("item"):
        sv = item.find(f"{{{sparkle_ns}}}shortVersionString")
        if sv is not None and sv.text == version:
            channel.remove(item)

    # Compute DMG file size
    dmg_size = os.path.getsize(dmg_path)

    # RFC 2822 pubDate
    pub_date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")

    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"Version {version}"
    ET.SubElement(item, "description").text = release_notes
    ET.SubElement(item, "pubDate").text = pub_date

    ver_elem = ET.SubElement(item, f"{{{sparkle_ns}}}version")
    ver_elem.text = build

    sv_elem = ET.SubElement(item, f"{{{sparkle_ns}}}shortVersionString")
    sv_elem.text = version

    min_elem = ET.SubElement(item, f"{{{sparkle_ns}}}minimumSystemVersion")
    min_elem.text = min_system

    enclosure = ET.SubElement(item, "enclosure")
    enclosure.set("url", download_url)
    enclosure.set(f"{{{sparkle_ns}}}version", build)
    enclosure.set(f"{{{sparkle_ns}}}shortVersionString", version)
    enclosure.set("length", str(dmg_size))
    enclosure.set("type", "application/octet-stream")

    if signature:
        enclosure.set(f"{{{sparkle_ns}}}edSignature", signature)


def main():
    parser = argparse.ArgumentParser(description="Generate Sparkle appcast entry")
    parser.add_argument("--version", required=True, help="Marketing version (e.g. 1.0.0)")
    parser.add_argument("--build", required=True, help="Build number (e.g. 4)")
    parser.add_argument("--dmg", required=True, help="Path to the DMG file")
    parser.add_argument("--download-url", required=True,
                        help="Public download URL for the DMG")
    parser.add_argument("--private-key", default="",
                        help="Path to Ed25519 private key PEM file (optional)")
    parser.add_argument("--appcast", default="appcast.xml",
                        help="Path to appcast.xml")
    parser.add_argument("--release-notes", default="",
                        help="Release notes (HTML or plain text)")
    parser.add_argument("--min-system", default="14.0",
                        help="Minimum macOS version")
    args = parser.parse_args()

    # Validate inputs
    if not os.path.exists(args.dmg):
        print(f"ERROR: DMG file not found: {args.dmg}", file=sys.stderr)
        sys.exit(1)

    # Sign the DMG if a private key is provided
    signature = ""
    public_key = ""
    if args.private_key and os.path.exists(args.private_key):
        try:
            signature = sign_dmg(args.dmg, args.private_key)
            public_key = extract_public_key(args.private_key)
            print(f"Signed DMG with Ed25519 (public key: {public_key[:16]}...)")
        except ImportError:
            print("WARNING: cryptography library not available — skipping EdDSA signature",
                  file=sys.stderr)
            print("  Install with: pip install cryptography", file=sys.stderr)
    else:
        print("WARNING: No private key provided — update will not be signed",
              file=sys.stderr)
        print("  Sparkle will refuse to install unsigned updates.", file=sys.stderr)
        print("  Generate keys with:", file=sys.stderr)
        print("    openssl genpkey -algorithm ed25519 -out sparkle_private.pem", file=sys.stderr)
        print("    openssl pkey -in sparkle_private.pem -pubout -out sparkle_public.pem", file=sys.stderr)

    # Read or create appcast
    tree = read_appcast(args.appcast)
    root = tree.getroot()
    channel = root.find("channel")
    if channel is None:
        channel = ET.SubElement(root, "channel")

    # Inject public key on first signed release
    ensure_public_key(channel, public_key)

    # Add the new release item
    add_release_item(channel, args.version, args.build,
                     args.download_url, args.dmg,
                     signature, args.release_notes, args.min_system)

    # Write the appcast
    tree.write(args.appcast, encoding="utf-8", xml_declaration=True)
    print(f"Appcast written to {args.appcast}")


if __name__ == "__main__":
    main()
