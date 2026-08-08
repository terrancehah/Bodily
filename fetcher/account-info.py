"""
Account info fetcher for the Bodily host app.

Authenticates with saved tokens, fetches the user's social profile
(display name, full name, profile image) and last-used device, merges
those fields into ~/.garminconnect/config.json (preserving credentials),
and outputs one JSON status line to stdout for the Swift app.

This is what "self-heals" accounts that were set up via first_login.py,
which historically saved only email + password without any profile data.

Protocol:
  stdout (line 1): {"status": "success"|"error", ...}

All library output is redirected to stderr so it cannot corrupt the
JSON protocol on stdout. JSON is written directly to file descriptor 1
using os.write() to bypass the redirect — same pattern as login.py.
"""

import json
import os
import sys
from pathlib import Path

# Redirect sys.stdout to stderr BEFORE importing the library — see login.py
sys.stdout = sys.stderr

from garminconnect import Garmin, GarminConnectConnectionError

# -- Paths (must match garmin_fetcher.py / login.py) --
TOKEN_STORE = str(Path.home() / ".garminconnect")
CONFIG_FILE = Path(TOKEN_STORE) / "config.json"


def output_json(data):
    """Write a JSON status line directly to stdout fd 1, bypassing redirect."""
    msg = json.dumps(data) + "\n"
    os.write(1, msg.encode())


def fetch_account_info(client):
    """
    Pull profile and device data from Garmin Connect.

    Returns a dict with display_name, full_name, profile_image_url, and
    device_name. Each field degrades gracefully to "" when its endpoint
    fails — a partial profile is more useful than a hard error.
    """
    info = {
        "display_name": getattr(client, "display_name", None) or "",
        "full_name": getattr(client, "full_name", None) or "",
        "profile_image_url": "",
        "device_name": "",
    }

    # -- Social profile: display name, full name, and profile image --
    # The login already loaded display_name/full_name, but the raw social
    # profile response also carries the profile image URLs.
    try:
        profile = client.connectapi("/userprofile-service/socialProfile")
        if isinstance(profile, dict):
            info["display_name"] = profile.get("displayName") or info["display_name"]
            info["full_name"] = profile.get("fullName") or info["full_name"]
            info["profile_image_url"] = (
                profile.get("profileImageUrlLarge")
                or profile.get("profileImageUrlMedium")
                or ""
            )
    except Exception as e:
        print(f"Failed to fetch social profile: {e}", file=sys.stderr)

    # -- Device: watch model name (e.g. "Instinct 2") --
    # get_devices() lists all registered devices and reliably carries
    # productDisplayName; prefer the primary device, else the first.
    try:
        devices = client.get_devices()
        if isinstance(devices, list) and devices:
            primary = next((d for d in devices if d.get("primary")), devices[0])
            info["device_name"] = (
                primary.get("productDisplayName")
                or primary.get("deviceName")
                or ""
            )
    except Exception as e:
        print(f"Failed to fetch device list: {e}", file=sys.stderr)

    # Fallback: last-used device endpoint (carries no productDisplayName on
    # some accounts, which is why it isn't the primary source)
    if not info["device_name"]:
        try:
            device = client.get_device_last_used()
            if isinstance(device, dict):
                info["device_name"] = (
                    device.get("productDisplayName")
                    or device.get("deviceName")
                    or ""
                )
        except Exception as e:
            print(f"Failed to fetch last-used device: {e}", file=sys.stderr)

    return info


def merge_into_config(info):
    """Merge account fields into config.json, preserving credentials."""
    if not CONFIG_FILE.exists():
        return
    with open(CONFIG_FILE, "r") as f:
        config = json.load(f)
    config.update(info)
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2)
    # Keep restricted permissions (file contains credentials)
    os.chmod(CONFIG_FILE, 0o600)


def main():
    # -- Load credentials saved during login --
    if not CONFIG_FILE.exists():
        output_json({"status": "error", "message": "No config found. Please log in first."})
        sys.exit(1)

    with open(CONFIG_FILE, "r") as f:
        config = json.load(f)

    email = config.get("email", "")
    password = config.get("password", "")
    if not email or not password:
        output_json({"status": "error", "message": "Credentials missing from config."})
        sys.exit(1)

    # -- Authenticate using saved tokens (library auto-refreshes) --
    client = Garmin(email, password)
    try:
        client.login(TOKEN_STORE)
    except GarminConnectConnectionError as e:
        output_json({"status": "error", "message": f"Failed to connect: {e}"})
        sys.exit(1)
    except Exception as e:
        output_json({"status": "error", "message": f"Unexpected error: {e}"})
        sys.exit(1)

    # -- Fetch, persist, and report --
    info = fetch_account_info(client)
    merge_into_config(info)

    output_json({
        "status": "success",
        "display_name": info["display_name"],
        "full_name": info["full_name"],
        "profile_image_url": info["profile_image_url"],
        "device_name": info["device_name"],
        "email": email,
    })


if __name__ == "__main__":
    main()
