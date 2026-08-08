"""
Garmin Connect Metrics Fetcher
Fetches recovery metrics from Garmin Connect and writes them to a JSON file
that the macOS WidgetKit extension reads from.
Designed to run on a 15-minute schedule via launchd.
"""

import json
import math
import os
import sys
import logging
from datetime import date, datetime, timedelta
from pathlib import Path

from garminconnect import Garmin, GarminConnectConnectionError

# -- Configuration --
# App Group container path where the widget reads data from.
# This must match the App Group ID configured in Xcode.
APP_GROUP_CONTAINER = Path.home() / "Library" / "Group Containers" / "group.com.bodily.shared"
OUTPUT_FILE = APP_GROUP_CONTAINER / "garmin_metrics.json"

# Token storage location for persistent authentication
TOKEN_STORE = str(Path.home() / ".garminconnect")

# Logging setup
LOG_FILE = APP_GROUP_CONTAINER / "fetcher.log"
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
logger = logging.getLogger(__name__)


def ensure_directories():
    """Create necessary directories if they don't exist."""
    APP_GROUP_CONTAINER.mkdir(parents=True, exist_ok=True)
    Path(TOKEN_STORE).mkdir(parents=True, exist_ok=True)


def connect_to_garmin() -> Garmin:
    """
    Authenticate with Garmin Connect using saved tokens.
    Tokens are expected to already exist from a prior interactive login
    via first_login.py. The library auto-refreshes expired tokens.
    """
    # Load credentials from config file (set during login)
    # Config is stored in ~/.garminconnect/ alongside token store
    config_path = Path(TOKEN_STORE) / "config.json"
    if not config_path.exists():
        logger.error("Config file not found. Run first_login.py to set up credentials.")
        sys.exit(1)

    with open(config_path, "r") as f:
        config = json.load(f)

    email = config.get("email")
    password = config.get("password")

    if not email or not password:
        logger.error("Email or password missing from config. Run first_login.py again.")
        sys.exit(1)

    # Initialize client and login using saved token store
    client = Garmin(email, password)
    try:
        client.login(TOKEN_STORE)
        logger.info("Successfully authenticated with Garmin Connect.")
    except GarminConnectConnectionError as e:
        logger.error(f"Failed to connect to Garmin: {e}")
        sys.exit(1)

    return client


def fetch_metrics(client: Garmin) -> dict:
    """
    Fetch all recovery metrics from Garmin Connect.

    Each metric is stored as an object with "value" and "date" fields.
    This allows the widget to show "last updated" labels for stale data.

    Metric categories:
      - Real-time (Body Battery, Stress): Only today's data shown; blank if unavailable.
      - Daily/sleep-derived (Training Readiness, HRV, Sleep Score): Falls back to
        yesterday with the source date recorded for "last updated" display.
      - Persistent (VO2 Max): Searches back up to 30 days; always shows most recent.
    """
    today = date.today().isoformat()
    yesterday = (date.today() - timedelta(days=1)).isoformat()

    metrics = {
        "timestamp": datetime.now().isoformat(),
        "date": today,
        # Each metric: {"value": number|null, "date": "YYYY-MM-DD"|null}
        "trainingReadiness": {"value": None, "date": None, "level": None},
        "bodyBattery": {"value": None, "date": None},
        "stressLevel": {"value": None, "date": None},
        "vo2Max": {"value": None, "date": None},
        "hrvStatus": {"value": None, "date": None},
        "sleepScore": {"value": None, "date": None},
        "fitnessAge": {"value": None, "date": None},
        "trainingStatus": {"value": None, "date": None, "level": None},
        # "goal" drives goal-relative gauges; "detail" adds a secondary display string
        "stepsToday": {"value": None, "date": None, "goal": None},
        "restingHR": {"value": None, "date": None},
        "intensityMinutes": {"value": None, "date": None, "goal": None},
        "trainingLoad": {"value": None, "date": None, "level": None, "goal": None},
        "error": None,
    }

    # -- Training Readiness (daily/sleep-derived) --
    # Calculated once after waking. Falls back to yesterday with date recorded.
    try:
        for query_date in [today, yesterday]:
            tr_data = client.get_training_readiness(query_date)
            if isinstance(tr_data, list) and len(tr_data) > 0:
                entry = tr_data[0]
                score = entry.get("score")
                if score is not None:
                    metrics["trainingReadiness"] = {
                        "value": score,
                        "date": query_date,
                        "level": entry.get("level"),  # e.g. "LOW", "MODERATE", "HIGH"
                    }
                    break
        logger.info(f"Training Readiness: {metrics['trainingReadiness']}")
    except Exception as e:
        logger.warning(f"Failed to fetch Training Readiness: {e}")

    # -- Body Battery (real-time) --
    # Updates continuously. Falls back to yesterday's final reading when today
    # has no data yet (watch not synced), with the date recorded for the UI.
    try:
        for query_date in [today, yesterday]:
            bb_data = client.get_body_battery(query_date)
            if isinstance(bb_data, list) and len(bb_data) > 0:
                entry = bb_data[0]
                values_array = entry.get("bodyBatteryValuesArray", [])
                # Find the last non-null value in the day's array
                current_level = None
                for pair in reversed(values_array):
                    if len(pair) >= 2 and pair[1] is not None:
                        current_level = pair[1]
                        break
                if current_level is not None:
                    metrics["bodyBattery"] = {"value": current_level, "date": query_date}
                    break
        logger.info(f"Body Battery: {metrics['bodyBattery']}")
    except Exception as e:
        logger.warning(f"Failed to fetch Body Battery: {e}")

    # -- Stress Level (real-time) --
    # Running daily average. Falls back to yesterday's average when today has
    # no stress data yet, with the date recorded for the UI.
    try:
        for query_date in [today, yesterday]:
            stress_data = client.get_all_day_stress(query_date)
            if isinstance(stress_data, dict):
                avg = stress_data.get("avgStressLevel")
                if avg is not None and avg > 0:
                    metrics["stressLevel"] = {"value": avg, "date": query_date}
                    break
        logger.info(f"Stress Level: {metrics['stressLevel']}")
    except Exception as e:
        logger.warning(f"Failed to fetch Stress: {e}")

    # -- VO2 Max (persistent/activity-dependent) --
    # Only updates after GPS activities. Search back up to 30 days.
    try:
        for days_back in range(0, 30):
            query_date = (date.today() - timedelta(days=days_back)).isoformat()
            vo2_data = client.get_max_metrics(query_date)
            if isinstance(vo2_data, list) and len(vo2_data) > 0:
                generic = vo2_data[0].get("generic", {})
                vo2_val = generic.get("vo2MaxValue") if generic else None
                if vo2_val is not None:
                    metrics["vo2Max"] = {"value": vo2_val, "date": query_date}
                    break
            elif isinstance(vo2_data, dict):
                generic = vo2_data.get("generic", {})
                vo2_val = generic.get("vo2MaxValue") if generic else None
                if vo2_val is not None:
                    metrics["vo2Max"] = {"value": vo2_val, "date": query_date}
                    break
        logger.info(f"VO2 Max: {metrics['vo2Max']}")
    except Exception as e:
        logger.warning(f"Failed to fetch VO2 Max: {e}")

    # -- HRV Status (daily/sleep-derived) --
    # Computed from overnight sleep. Falls back to yesterday with date.
    try:
        for query_date in [today, yesterday]:
            hrv_data = client.get_hrv_data(query_date)
            if isinstance(hrv_data, dict) and "hrvSummary" in hrv_data:
                summary = hrv_data["hrvSummary"]
                avg = summary.get("lastNightAvg") or summary.get("weeklyAvg")
                # Also capture the HRV status text (BALANCED, UNBALANCED, LOW, POOR)
                hrv_status_text = summary.get("status")
                if avg is not None:
                    metrics["hrvStatus"] = {"value": avg, "date": query_date, "level": hrv_status_text}
                    break
        logger.info(f"HRV Status: {metrics['hrvStatus']}")
    except Exception as e:
        logger.warning(f"Failed to fetch HRV: {e}")

    # -- Sleep Score (daily/sleep-derived) --
    # Available after sleep is processed. Falls back to yesterday with date.
    try:
        for query_date in [today, yesterday]:
            sleep_data = client.get_sleep_data(query_date)
            if isinstance(sleep_data, dict):
                score = None
                # Primary: sleepScores.overall.value (overall is a dict with 'value' key)
                overall = sleep_data.get("sleepScores", {}).get("overall")
                if isinstance(overall, dict):
                    score = overall.get("value")
                elif isinstance(overall, (int, float)):
                    score = overall
                # Fallback: check nested dailySleepDTO structure
                if score is None:
                    dto = sleep_data.get("dailySleepDTO", {})
                    if isinstance(dto, dict):
                        overall_dto = dto.get("sleepScores", {}).get("overall")
                        if isinstance(overall_dto, dict):
                            score = overall_dto.get("value")
                        elif isinstance(overall_dto, (int, float)):
                            score = overall_dto
                # Fallback: direct field names
                if score is None:
                    score = sleep_data.get("overallScore") or sleep_data.get("sleepScore")
                # Sleep duration accompanies the score on the same card, so it
                # travels as a "detail" string rather than a separate metric
                duration_text = None
                dto = sleep_data.get("dailySleepDTO") or {}
                sleep_seconds = (
                    dto.get("sleepTimeSeconds")
                    or sleep_data.get("sleepTimeSeconds")
                )
                if sleep_seconds:
                    hours = int(sleep_seconds) // 3600
                    minutes = (int(sleep_seconds) % 3600) // 60
                    duration_text = f"{hours}h {minutes:02d}m"

                if score is not None:
                    metrics["sleepScore"] = {
                        "value": score,
                        "date": query_date,
                        "detail": duration_text,
                    }
                    break
        logger.info(f"Sleep Score: {metrics['sleepScore']}")
    except Exception as e:
        logger.warning(f"Failed to fetch Sleep Score: {e}")

    # -- Fitness Age (slow-moving) --
    # Garmin's estimate of biological fitness age. Falls back to yesterday.
    try:
        for query_date in [today, yesterday]:
            age_data = client.get_fitnessage_data(query_date)
            if isinstance(age_data, dict):
                fitness_age = age_data.get("fitnessAge")
                if fitness_age is not None:
                    # Garmin Connect displays fitness age floored to the nearest
                    # 0.5 (e.g. API 22.99 -> app 22.5) — mirror that display
                    fitness_age = math.floor(fitness_age * 2) / 2
                    metrics["fitnessAge"] = {"value": fitness_age, "date": query_date}
                    break
        logger.info(f"Fitness Age: {metrics['fitnessAge']}")
    except Exception as e:
        logger.warning(f"Failed to fetch Fitness Age: {e}")

    # -- Training Status (text metric) --
    # Qualitative state (PRODUCTIVE, PEAKING, RECOVERY, ...) stored in the
    # "level" field rather than "value" since it isn't numeric.
    # ts_data is shared with the Training Load block below (same endpoint),
    # so it lives outside the try to avoid a duplicate request.
    ts_data = None
    try:
        ts_data = client.get_training_status(today)
        if isinstance(ts_data, dict):
            # Keys can be present with None values — `or {}` guards each level
            latest = (
                (ts_data.get("mostRecentTrainingStatus") or {})
                .get("latestTrainingStatusData") or {}
            )
            # Data is keyed by device ID — take the first entry
            if isinstance(latest, dict) and latest:
                entry = next(iter(latest.values()))
                # Prefer the phrase ("PRODUCTIVE_2"); trainingStatus is a
                # numeric code (7), not the display string
                status_phrase = entry.get("trainingStatusFeedbackPhrase")
                status_code = entry.get("trainingStatus")
                status = None
                if status_phrase:
                    # Normalize "PRODUCTIVE_2" -> "PRODUCTIVE"
                    status = str(status_phrase).split("_")[0]
                elif isinstance(status_code, int):
                    # Garmin's numeric training status codes
                    status_map = {
                        1: "DETRAINING", 2: "RECOVERY", 3: "UNPRODUCTIVE",
                        4: "MAINTAINING", 5: "PRODUCTIVE", 6: "PEAKING",
                        7: "PRODUCTIVE",
                    }
                    status = status_map.get(status_code)
                if status:
                    metrics["trainingStatus"] = {
                        "value": None, "date": today, "level": status,
                    }
        logger.info(f"Training Status: {metrics['trainingStatus']}")
    except Exception as e:
        logger.warning(f"Failed to fetch Training Status: {e}")

    # -- Training Load (7-day acute load) --
    # Garmin's acute load with its "optimal range" tunnel. The load value goes
    # in "value", the ACWR status (OPTIMAL/LOW/HIGH) in "level", and the top of
    # the optimal range in "goal" so the gauge shows position within the tunnel.
    try:
        if isinstance(ts_data, dict):
            latest = (
                (ts_data.get("mostRecentTrainingStatus") or {})
                .get("latestTrainingStatusData") or {}
            )
            if isinstance(latest, dict) and latest:
                entry = next(iter(latest.values()))
                acute = entry.get("acuteTrainingLoadDTO") or {}
                load = acute.get("dailyTrainingLoadAcute")
                if load is not None:
                    status = acute.get("acwrStatus")
                    metrics["trainingLoad"] = {
                        "value": load,
                        "date": entry.get("calendarDate") or today,
                        # e.g. "OPTIMAL", "LOW", "HIGH"
                        "level": str(status).split("_")[0] if status else None,
                        "goal": acute.get("maxTrainingLoadChronic"),
                    }
        logger.info(f"Training Load: {metrics['trainingLoad']}")
    except Exception as e:
        logger.warning(f"Failed to fetch Training Load: {e}")

    # -- Steps Today (real-time) --
    # Total steps so far today from the user summary endpoint, paired with the
    # user's own daily step goal so the gauge reflects their target (not a
    # hardcoded 10k). Falls back to yesterday when today has no steps yet.
    try:
        for query_date in [today, yesterday]:
            summary = client.get_user_summary(query_date)
            if isinstance(summary, dict):
                total_steps = summary.get("totalSteps")
                if total_steps is not None and total_steps > 0:
                    metrics["stepsToday"] = {
                        "value": total_steps,
                        "date": query_date,
                        "goal": summary.get("dailyStepGoal"),
                    }
                    break
        logger.info(f"Steps Today: {metrics['stepsToday']}")
    except Exception as e:
        logger.warning(f"Failed to fetch Steps: {e}")

    # -- Intensity Minutes (weekly) --
    # Garmin goals intensity minutes weekly (WHO's 150/week), and counts each
    # vigorous minute double. Query the last 7 days and take the most recent
    # week bucket the API returns.
    try:
        week_start = (date.today() - timedelta(days=6)).isoformat()
        im_data = client.get_weekly_intensity_minutes(week_start, today)
        if isinstance(im_data, list) and im_data:
            current = im_data[-1]
            moderate = current.get("moderateValue") or 0
            vigorous = current.get("vigorousValue") or 0
            # Garmin's formula: vigorous minutes count twice toward the goal
            total = moderate + (vigorous * 2)
            if total > 0:
                metrics["intensityMinutes"] = {
                    "value": total,
                    "date": current.get("calendarDate") or today,
                    "goal": current.get("weeklyGoal"),
                }
        logger.info(f"Intensity Minutes: {metrics['intensityMinutes']}")
    except Exception as e:
        logger.warning(f"Failed to fetch Intensity Minutes: {e}")

    # -- Resting Heart Rate (daily) --
    # Falls back to yesterday when today's HR data hasn't synced yet.
    try:
        for query_date in [today, yesterday]:
            hr_data = client.get_heart_rates(query_date)
            if isinstance(hr_data, dict):
                resting = hr_data.get("restingHeartRate")
                if resting is not None and resting > 0:
                    metrics["restingHR"] = {"value": resting, "date": query_date}
                    break
        logger.info(f"Resting HR: {metrics['restingHR']}")
    except Exception as e:
        logger.warning(f"Failed to fetch Resting HR: {e}")

    return metrics


def write_metrics(metrics: dict):
    """Write the metrics dictionary to the shared JSON file."""
    with open(OUTPUT_FILE, "w") as f:
        json.dump(metrics, f, indent=2)
    logger.info(f"Metrics written to {OUTPUT_FILE}")


def main():
    """Main entry point: authenticate, fetch, and write metrics."""
    logger.info("--- Garmin Fetcher started ---")
    ensure_directories()

    client = connect_to_garmin()
    metrics = fetch_metrics(client)
    write_metrics(metrics)

    logger.info("--- Garmin Fetcher completed ---")


if __name__ == "__main__":
    main()
