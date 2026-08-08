"""
Debug script to inspect raw API responses from Garmin Connect.
Tries both today and yesterday to determine data availability.
"""

import json
import os
from datetime import date, timedelta
from pathlib import Path
from garminconnect import Garmin

TOKEN_STORE = str(Path.home() / ".garminconnect")
CONFIG_PATH = Path(TOKEN_STORE) / "config.json"

# Load credentials and login
with open(CONFIG_PATH, "r") as f:
    config = json.load(f)

client = Garmin(config["email"], config["password"])
client.login(TOKEN_STORE)
print(f"Logged in as: {client.display_name}\n")

today = date.today().isoformat()
yesterday = (date.today() - timedelta(days=1)).isoformat()

print(f"=== Trying YESTERDAY ({yesterday}) ===\n")

# Training Readiness
print("--- Training Readiness ---")
try:
    data = client.get_training_readiness(yesterday)
    print(json.dumps(data, indent=2, default=str)[:500])
except Exception as e:
    print(f"ERROR: {e}")
print()

# Body Battery
print("--- Body Battery ---")
try:
    data = client.get_body_battery(yesterday)
    print(json.dumps(data, indent=2, default=str)[:500])
except Exception as e:
    print(f"ERROR: {e}")
print()

# Stress
print("--- All Day Stress ---")
try:
    data = client.get_all_day_stress(yesterday)
    # Print just the keys and summary fields, not the full arrays
    if isinstance(data, dict):
        summary = {k: v for k, v in data.items() if not isinstance(v, list)}
        print(json.dumps(summary, indent=2, default=str)[:500])
    else:
        print(json.dumps(data, indent=2, default=str)[:500])
except Exception as e:
    print(f"ERROR: {e}")
print()

# VO2 Max
print("--- Max Metrics (VO2 Max) ---")
try:
    data = client.get_max_metrics(yesterday)
    print(json.dumps(data, indent=2, default=str)[:500])
except Exception as e:
    print(f"ERROR: {e}")
print()

# HRV
print("--- HRV Data ---")
try:
    data = client.get_hrv_data(yesterday)
    print(json.dumps(data, indent=2, default=str)[:500])
except Exception as e:
    print(f"ERROR: {e}")
print()

# Sleep
print("--- Sleep Data ---")
try:
    data = client.get_sleep_data(yesterday)
    if isinstance(data, dict):
        # Print just the top-level keys and score fields
        summary = {k: v for k, v in data.items() if not isinstance(v, list) and not isinstance(v, dict)}
        if "sleepScores" in data:
            summary["sleepScores"] = data["sleepScores"]
        print(json.dumps(summary, indent=2, default=str)[:500])
    else:
        print(json.dumps(data, indent=2, default=str)[:500])
except Exception as e:
    print(f"ERROR: {e}")
print()

print(f"\n=== Trying TODAY ({today}) ===\n")

# Quick check for today
print("--- Training Readiness (today) ---")
try:
    data = client.get_training_readiness(today)
    print(json.dumps(data, indent=2, default=str)[:300])
except Exception as e:
    print(f"ERROR: {e}")

print("\n--- Body Battery (today) ---")
try:
    data = client.get_body_battery(today)
    print(json.dumps(data, indent=2, default=str)[:300])
except Exception as e:
    print(f"ERROR: {e}")
