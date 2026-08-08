"""
Non-interactive Garmin Connect login script.

Reads credentials from stdin, attempts login using the garminconnect library,
and outputs status as JSON to stdout. Used by the Bodily host app's login UI.

Uses the library's prompt_mfa callback for MFA support — the same pattern
shown in the python-garminconnect GitHub example. The library handles token
dumping and profile loading automatically after MFA completion.

Protocol:
  stdin  (line 1): {"email": "...", "password": "..."}
  stdin  (line 2, only if MFA required): {"mfa_code": "..."}
  stdout (line 1): {"status": "success"|"mfa_required"|"error", ...}

All library output (logging, warnings, etc.) is redirected to stderr so it
cannot corrupt the JSON protocol on stdout. JSON is written directly to
file descriptor 1 using os.write() to bypass the redirect.
"""

import json
import os
import sys
from pathlib import Path

# Redirect sys.stdout to stderr BEFORE importing the library, so any
# print/logging output from garminconnect or its dependencies goes to
# stderr instead of corrupting our JSON protocol on stdout.
# We use os.write(1, ...) to write JSON directly to the real stdout pipe.
sys.stdout = sys.stderr

from garminconnect import (
    Garmin,
    GarminConnectAuthenticationError,
    GarminConnectConnectionError,
    GarminConnectTooManyRequestsError,
)

# -- Paths (must match garmin_fetcher.py) --
# Config is stored in ~/.garminconnect/ (same dir as token store) so Python
# subprocesses can read/write it without App Group sandbox permission issues.
APP_GROUP_CONTAINER = Path.home() / "Library" / "Group Containers" / "group.com.bodily.shared"
TOKEN_STORE = str(Path.home() / ".garminconnect")
CONFIG_FILE = str(Path(TOKEN_STORE) / "config.json")


def output_json(data):
    """Write a JSON status line directly to stdout fd 1, bypassing redirect."""
    msg = json.dumps(data) + "\n"
    os.write(1, msg.encode())


def save_config(email, password, display_name="", full_name="",
                profile_image_url="", device_name=""):
    """Save credentials and account info for the background fetcher's token refresh."""
    config = {
        "email": email,
        "password": password,
        "display_name": display_name,
        "full_name": full_name,
        "profile_image_url": profile_image_url,
        "device_name": device_name,
    }
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2)
    # Restrict file permissions (contains credentials)
    os.chmod(CONFIG_FILE, 0o600)


def fetch_extra_account_info(client):
    """
    Fetch the profile image URL and last-used device name.
    Both are optional display data — failures degrade to "" so the
    login flow itself is never blocked by a flaky secondary endpoint.
    """
    profile_image_url = ""
    device_name = ""

    # Social profile carries the profile image URLs
    try:
        profile = client.connectapi("/userprofile-service/socialProfile")
        if isinstance(profile, dict):
            profile_image_url = (
                profile.get("profileImageUrlLarge")
                or profile.get("profileImageUrlMedium")
                or ""
            )
    except Exception as e:
        print(f"Failed to fetch profile image: {e}", file=sys.stderr)

    # Device list reliably carries the watch model name (e.g. "Instinct 2");
    # prefer the primary device, else the first. Last-used endpoint is a
    # fallback — it lacks productDisplayName on some accounts.
    try:
        devices = client.get_devices()
        if isinstance(devices, list) and devices:
            primary = next((d for d in devices if d.get("primary")), devices[0])
            device_name = (
                primary.get("productDisplayName")
                or primary.get("deviceName")
                or ""
            )
    except Exception as e:
        print(f"Failed to fetch device list: {e}", file=sys.stderr)

    if not device_name:
        try:
            device = client.get_device_last_used()
            if isinstance(device, dict):
                device_name = (
                    device.get("productDisplayName")
                    or device.get("deviceName")
                    or ""
                )
        except Exception as e:
            print(f"Failed to fetch device info: {e}", file=sys.stderr)

    return profile_image_url, device_name


def main():
    # -- Read credentials from stdin (one line, newline-delimited) --
    try:
        line = sys.stdin.readline()
        input_data = json.loads(line)
    except Exception as e:
        output_json({"status": "error", "message": f"Invalid input: {e}"})
        sys.exit(1)

    email = input_data.get("email", "").strip()
    password = input_data.get("password", "")

    if not email or not password:
        output_json({"status": "error", "message": "Email and password are required."})
        sys.exit(1)

    # Ensure directories exist
    APP_GROUP_CONTAINER.mkdir(parents=True, exist_ok=True)
    Path(TOKEN_STORE).mkdir(parents=True, exist_ok=True)

    # MFA callback — called by the library when Garmin requires MFA.
    # Outputs mfa_required status to stdout, then waits for the Swift app
    # to send the MFA code via stdin. Returns the code to the library,
    # which completes MFA, dumps tokens, and loads profile automatically.
    def mfa_callback():
        output_json({
            "status": "mfa_required",
            "message": "Enter the MFA code from your authenticator app."
        })
        mfa_line = sys.stdin.readline()
        try:
            mfa_data = json.loads(mfa_line)
            return mfa_data.get("mfa_code", "").strip()
        except Exception:
            return ""

    # Create client with prompt_mfa callback — same pattern as the GitHub example
    client = Garmin(email, password, prompt_mfa=mfa_callback)

    # Attempt login — the library handles token storage and profile loading
    try:
        client.login(TOKEN_STORE)
    except GarminConnectAuthenticationError as e:
        output_json({"status": "error", "message": str(e)})
        sys.exit(1)
    except GarminConnectTooManyRequestsError as e:
        output_json({"status": "error", "message": str(e)})
        sys.exit(1)
    except GarminConnectConnectionError as e:
        output_json({"status": "error", "message": f"Login failed: {e}"})
        sys.exit(1)
    except Exception as e:
        output_json({"status": "error", "message": f"Unexpected error: {e}"})
        sys.exit(1)

    # -- Save config and output success --
    display_name = getattr(client, "display_name", None) or email
    full_name = getattr(client, "full_name", None) or ""
    profile_image_url, device_name = fetch_extra_account_info(client)
    save_config(
        email, password,
        display_name=display_name,
        full_name=full_name,
        profile_image_url=profile_image_url,
        device_name=device_name,
    )
    output_json({
        "status": "success",
        "display_name": display_name,
        "full_name": full_name,
        "profile_image_url": profile_image_url,
        "device_name": device_name,
        "email": email
    })


if __name__ == "__main__":
    main()
