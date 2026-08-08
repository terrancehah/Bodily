"""
Garmin Connect First Login Script
Run this interactively to authenticate with Garmin Connect for the first time.
Handles MFA prompts and saves tokens + config for the background fetcher.
"""

import json
import os
import sys
from getpass import getpass
from pathlib import Path

from garminconnect import Garmin, GarminConnectConnectionError

# -- Paths (must match garmin_fetcher.py) --
APP_GROUP_CONTAINER = Path.home() / "Library" / "Group Containers" / "group.com.bodily.shared"
TOKEN_STORE = str(Path.home() / ".garminconnect")
CONFIG_FILE = str(Path(TOKEN_STORE) / "config.json")


def mfa_prompt() -> str:
    """Prompt the user for their MFA/2FA code."""
    return input("Enter MFA code from your authenticator app: ")


def main():
    print("=" * 50)
    print("  Garmin Connect - First Time Setup")
    print("=" * 50)
    print()

    # Ensure directories exist
    APP_GROUP_CONTAINER.mkdir(parents=True, exist_ok=True)
    Path(TOKEN_STORE).mkdir(parents=True, exist_ok=True)

    # Collect credentials
    email = input("Enter your Garmin Connect email: ").strip()
    password = getpass("Enter your Garmin Connect password: ")
    print()

    # Attempt login with MFA callback
    print("Authenticating with Garmin Connect...")
    client = Garmin(email, password, prompt_mfa=mfa_prompt)

    try:
        client.login(TOKEN_STORE)
        print(f"\n✓ Successfully logged in as: {client.display_name}")
    except GarminConnectConnectionError as e:
        print(f"\n✗ Login failed: {e}")
        print("  Please check your credentials and try again.")
        sys.exit(1)

    # Save config (credentials + account info shown in the host app)
    # Profile/device fields degrade to "" if their endpoints fail —
    # a partial profile must not block the login flow.
    config = {
        "email": email,
        "password": password,
        "display_name": getattr(client, "display_name", None) or "",
        "full_name": getattr(client, "full_name", None) or "",
        "profile_image_url": "",
        "device_name": "",
    }

    # Social profile also carries the profile image URL
    try:
        profile = client.connectapi("/userprofile-service/socialProfile")
        if isinstance(profile, dict):
            config["profile_image_url"] = (
                profile.get("profileImageUrlLarge")
                or profile.get("profileImageUrlMedium")
                or ""
            )
    except Exception as e:
        print(f"(Skipping profile image: {e})")

    # Last-used device gives the watch model name (e.g. "Forerunner 265")
    try:
        device = client.get_device_last_used()
        if isinstance(device, dict):
            config["device_name"] = (
                device.get("productDisplayName")
                or device.get("deviceName")
                or ""
            )
    except Exception as e:
        print(f"(Skipping device info: {e})")

    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2)

    # Restrict file permissions (contains credentials)
    os.chmod(CONFIG_FILE, 0o600)

    print(f"\n✓ Config saved to: {CONFIG_FILE}")
    print(f"✓ Tokens saved to: {TOKEN_STORE}/")
    print()
    print("Setup complete! The background fetcher will now be able to")
    print("authenticate automatically using saved tokens.")
    print()

    # Do a test fetch to verify everything works
    print("Running a test fetch...")
    from garmin_fetcher import fetch_metrics, write_metrics
    metrics = fetch_metrics(client)
    write_metrics(metrics)
    print(f"\n✓ Test fetch successful! Metrics written to:")
    print(f"  {APP_GROUP_CONTAINER / 'garmin_metrics.json'}")
    print()
    print("You can now install the launchd agent and run the widget.")


if __name__ == "__main__":
    main()
