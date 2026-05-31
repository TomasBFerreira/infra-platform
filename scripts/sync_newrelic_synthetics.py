#!/usr/bin/env python3

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple


def load_config(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def region_base_url(region: str) -> str:
    normalized = (region or "US").strip().upper()
    if normalized == "EU":
        return "https://synthetics.eu.newrelic.com/synthetics/api/v3"
    return "https://synthetics.newrelic.com/synthetics/api/v3"


def rest_region_base_url(region: str) -> str:
    normalized = (region or "US").strip().upper()
    if normalized == "EU":
        return "https://api.eu.newrelic.com/v2"
    return "https://api.newrelic.com/v2"


class NewRelicClient:
    def __init__(self, api_key: str, region: str) -> None:
        self.base_url = os.getenv("NEWRELIC_API_BASE_URL", region_base_url(region)).rstrip("/")
        self.rest_base_url = os.getenv(
            "NEWRELIC_REST_API_BASE_URL", rest_region_base_url(region)
        ).rstrip("/")
        self.api_key = api_key

    def _request(
        self,
        base_url: str,
        method: str,
        path: str,
        payload: Optional[Dict[str, Any]] = None,
        expected: Iterable[int] = (200,),
    ) -> Dict[str, Any]:
        data = None
        headers = {
            "Api-Key": self.api_key,
            "Content-Type": "application/json",
            "Accept": "application/json",
        }
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            f"{base_url}{path}",
            data=data,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                body = response.read().decode("utf-8")
                if response.status not in set(expected):
                    raise RuntimeError(
                        f"Unexpected status {response.status} for {method} {path}: {body}"
                    )
                if not body:
                    return {}
                return json.loads(body)
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(
                f"New Relic API error for {method} {path}: {exc.code} {body}"
            ) from exc

    def list_monitors(self) -> List[Dict[str, Any]]:
        offset = 0
        limit = 100
        monitors: List[Dict[str, Any]] = []
        while True:
            query = urllib.parse.urlencode({"limit": limit, "offset": offset})
            page = self._request(self.base_url, "GET", f"/monitors?{query}")
            batch = page.get("monitors", [])
            monitors.extend(batch)
            if len(batch) < limit:
                break
            offset += limit
        return monitors

    def create_monitor(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        return self._request(self.base_url, "POST", "/monitors", payload, expected=(200, 201))

    def update_monitor(self, monitor_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        return self._request(
            self.base_url,
            "PATCH",
            f"/monitors/{monitor_id}",
            payload,
            expected=(200, 202),
        )

    def delete_monitor(self, monitor_id: str) -> None:
        self._request(self.base_url, "DELETE", f"/monitors/{monitor_id}", expected=(200, 202, 204))

    def list_policies(self) -> List[Dict[str, Any]]:
        response = self._request(self.rest_base_url, "GET", "/alerts_policies.json")
        return response.get("policies", [])

    def create_policy(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        return self._request(
            self.rest_base_url,
            "POST",
            "/alerts_policies.json",
            {"policy": payload},
            expected=(200, 201),
        )

    def update_policy(self, policy_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        return self._request(
            self.rest_base_url,
            "PUT",
            f"/alerts_policies/{policy_id}.json",
            {"policy": payload},
            expected=(200, 201),
        )

    def list_location_failure_conditions(self, policy_id: str) -> List[Dict[str, Any]]:
        response = self._request(
            self.rest_base_url,
            "GET",
            f"/alerts_location_failure_conditions/policies/{policy_id}.json",
        )
        return response.get("location_failure_conditions", [])

    def create_location_failure_condition(
        self, policy_id: str, payload: Dict[str, Any]
    ) -> Dict[str, Any]:
        return self._request(
            self.rest_base_url,
            "POST",
            f"/alerts_location_failure_conditions/policies/{policy_id}.json",
            {"location_failure_condition": payload},
            expected=(200, 201),
        )

    def update_location_failure_condition(
        self, condition_id: str, payload: Dict[str, Any]
    ) -> Dict[str, Any]:
        return self._request(
            self.rest_base_url,
            "PUT",
            f"/alerts_location_failure_conditions/{condition_id}.json",
            {"location_failure_condition": payload},
            expected=(200, 201),
        )

    def delete_location_failure_condition(self, condition_id: str) -> None:
        self._request(
            self.rest_base_url,
            "DELETE",
            f"/alerts_conditions/{condition_id}.json",
            expected=(200, 202, 204),
        )


def build_desired_monitors(config: Dict[str, Any]) -> List[Dict[str, Any]]:
    defaults = config.get("defaults", {})
    prefix = defaults.get("namePrefix", "")
    default_frequency = defaults.get("frequencyMinutes", 5)
    default_locations = defaults.get("locations", [])
    default_status = defaults.get("status", "ENABLED")
    desired: List[Dict[str, Any]] = []
    for entry in config.get("monitors", []):
        if not entry.get("enabled", False):
            continue
        if entry.get("mode") not in {"simple", "probe-endpoint"}:
            continue
        desired.append(
            {
                "name": f"{prefix}{entry['name']}",
                "uri": entry["url"],
                "type": "SIMPLE",
                "frequency": entry.get("frequencyMinutes", default_frequency),
                "locations": entry.get("locations", default_locations),
                "status": entry.get("status", default_status),
                "slaThreshold": entry.get("slaThreshold", 7.0),
                "_slug": entry["slug"],
                "_alert_enabled": entry.get("alert", True),
            }
        )
    return desired


def build_desired_conditions(
    config: Dict[str, Any], monitors_by_name: Dict[str, Dict[str, Any]]
) -> Dict[str, Dict[str, Any]]:
    alerts_config = config.get("alerts", {})
    policy_config = alerts_config.get("policy", {})
    if not policy_config.get("enabled", False):
        return {}

    runbook_url = alerts_config.get("conditionDefaults", {}).get("runbookUrl")
    critical_threshold = (
        alerts_config.get("conditionDefaults", {}).get("criticalThresholdLocations", 1)
    )
    violation_time_limit_seconds = (
        alerts_config.get("conditionDefaults", {}).get("violationTimeLimitSeconds", 3600)
    )
    desired_conditions: Dict[str, Dict[str, Any]] = {}
    for monitor in build_desired_monitors(config):
        if not monitor.get("_alert_enabled", True):
            continue
        current_monitor = monitors_by_name.get(monitor["name"])
        if current_monitor is None:
            continue
        condition_name = f"{monitor['name']} down"
        payload = {
            "name": condition_name,
            "entities": [str(current_monitor["id"])],
            "enabled": True,
            "terms": [{"priority": "critical", "threshold": int(critical_threshold)}],
            "violation_time_limit_seconds": int(violation_time_limit_seconds),
        }
        if runbook_url:
            payload["runbook_url"] = runbook_url
        desired_conditions[condition_name] = payload
    return desired_conditions


def managed_prefixes(config: Dict[str, Any]) -> List[str]:
    defaults = config.get("defaults", {})
    prefixes = [defaults.get("namePrefix", "")]
    prefixes.extend(defaults.get("legacyNamePrefixes", []))
    return [prefix for prefix in prefixes if prefix]


def find_existing_monitor(
    desired_monitor: Dict[str, Any],
    existing_monitors: Sequence[Dict[str, Any]],
    existing_by_name: Dict[str, Dict[str, Any]],
    prefixes: Sequence[str],
) -> Optional[Dict[str, Any]]:
    exact = existing_by_name.get(desired_monitor["name"])
    if exact is not None:
        return exact

    uri_matches = [
        monitor
        for monitor in existing_monitors
        if monitor.get("uri") == desired_monitor["uri"]
        and (not prefixes or any(str(monitor.get("name", "")).startswith(prefix) for prefix in prefixes))
    ]
    if len(uri_matches) == 1:
        return uri_matches[0]
    return None


def condition_entity_key(condition: Dict[str, Any]) -> Tuple[str, ...]:
    return tuple(sorted(str(entity) for entity in condition.get("entities", [])))


def find_existing_condition(
    condition_name: str,
    payload: Dict[str, Any],
    existing_conditions_by_name: Dict[str, Dict[str, Any]],
    existing_conditions: Sequence[Dict[str, Any]],
    prefixes: Sequence[str],
) -> Optional[Dict[str, Any]]:
    exact = existing_conditions_by_name.get(condition_name)
    if exact is not None:
        return exact

    entity_key = condition_entity_key(payload)
    entity_matches = [
        condition
        for condition in existing_conditions
        if condition_entity_key(condition) == entity_key
        and (not prefixes or any(str(condition.get("name", "")).startswith(prefix) for prefix in prefixes))
    ]
    if len(entity_matches) == 1:
        return entity_matches[0]
    return None


def normalize_monitor(monitor: Dict[str, Any]) -> Dict[str, Any]:
    comparable = {
        "name": monitor.get("name"),
        "uri": monitor.get("uri"),
        "type": monitor.get("type"),
        "frequency": monitor.get("frequency"),
        "status": monitor.get("status"),
        "slaThreshold": float(monitor.get("slaThreshold", 0)),
        "locations": sorted(monitor.get("locations", [])),
    }
    return comparable


def normalize_condition(condition: Dict[str, Any]) -> Dict[str, Any]:
    terms = []
    for term in condition.get("terms", []):
        terms.append(
            {
                "priority": term.get("priority"),
                "threshold": int(term.get("threshold", 0)),
            }
        )
    terms.sort(key=lambda item: (item["priority"] or "", item["threshold"]))
    comparable = {
        "name": condition.get("name"),
        "entities": sorted(str(entity) for entity in condition.get("entities", [])),
        "enabled": bool(condition.get("enabled", True)),
        "runbook_url": condition.get("runbook_url"),
        "terms": terms,
        "violation_time_limit_seconds": int(condition.get("violation_time_limit_seconds", 0)),
    }
    return comparable


def validate_config(config: Dict[str, Any]) -> List[str]:
    errors: List[str] = []
    defaults = config.get("defaults", {})
    if not defaults.get("namePrefix"):
        errors.append("defaults.namePrefix is required")
    if not defaults.get("locations"):
        errors.append("defaults.locations must contain at least one New Relic public location")

    alerts_config = config.get("alerts", {})
    policy_config = alerts_config.get("policy", {})
    if policy_config.get("enabled", False):
        if not policy_config.get("name"):
            errors.append("alerts.policy.name is required when alerts.policy.enabled is true")
        incident_preference = policy_config.get("incidentPreference")
        if incident_preference not in {"PER_POLICY", "PER_CONDITION", "PER_CONDITION_AND_TARGET"}:
            errors.append(
                "alerts.policy.incidentPreference must be one of "
                "PER_POLICY, PER_CONDITION, PER_CONDITION_AND_TARGET"
            )

    seen_slugs = set()
    seen_names = set()
    for entry in config.get("monitors", []):
        slug = entry.get("slug")
        name = entry.get("name")
        url = entry.get("url")
        mode = entry.get("mode")
        if not slug:
            errors.append("Every monitor requires a slug")
        elif slug in seen_slugs:
            errors.append(f"Duplicate slug: {slug}")
        else:
            seen_slugs.add(slug)

        if not name:
            errors.append(f"Monitor {slug or '<unknown>'} requires a name")
        elif name in seen_names:
            errors.append(f"Duplicate name: {name}")
        else:
            seen_names.add(name)

        if not url:
            errors.append(f"Monitor {slug or name or '<unknown>'} requires a url")
        if mode not in {"simple", "probe-endpoint"}:
            errors.append(
                f"Monitor {slug or name or '<unknown>'} has unsupported mode {mode!r}"
            )
    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync New Relic synthetics monitors from repo-managed desired state."
    )
    parser.add_argument(
        "--config",
        default="monitoring/newrelic/monitors.json",
        help="Path to the monitor inventory JSON file.",
    )
    parser.add_argument(
        "--validate",
        action="store_true",
        help="Validate configuration and print the sync plan without calling New Relic.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show creates/updates/deletes without applying them.",
    )
    parser.add_argument(
        "--allow-delete",
        action="store_true",
        help="Delete repo-managed monitors missing from the desired-state file.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    config = load_config(args.config)
    errors = validate_config(config)
    desired = build_desired_monitors(config)
    deferred = [
        entry
        for entry in config.get("monitors", [])
        if entry.get("mode") == "probe-endpoint" and not entry.get("enabled", False)
    ]

    if errors:
        for error in errors:
            print(f"CONFIG ERROR: {error}", file=sys.stderr)
        return 1

    print(f"Validated {len(config.get('monitors', []))} monitor entries.")
    print(f"Active simple monitors: {len(desired)}")
    if deferred:
        print(f"Deferred probe-endpoint monitors: {len(deferred)}")
        for entry in deferred:
            print(f"  - {entry['slug']}: {entry.get('notes', 'needs probe endpoint')}")

    if args.validate and not args.dry_run:
        return 0

    api_key = os.getenv("NEWRELIC_API_KEY")
    region = os.getenv("NEWRELIC_REGION", "US")
    if not api_key:
        print("NEWRELIC_API_KEY is required unless only --validate is used.", file=sys.stderr)
        return 1

    client = NewRelicClient(api_key=api_key, region=region)
    existing_monitors = client.list_monitors()
    existing_by_name = {monitor.get("name"): monitor for monitor in existing_monitors}
    desired_names = {monitor["name"] for monitor in desired}
    prefixes = managed_prefixes(config)

    for monitor in desired:
        current = find_existing_monitor(monitor, existing_monitors, existing_by_name, prefixes)
        payload = {
            key: value
            for key, value in monitor.items()
            if not key.startswith("_")
        }
        if current is None:
            print(f"CREATE {monitor['name']} -> {monitor['uri']}")
            if not args.dry_run:
                client.create_monitor(payload)
            continue

        if normalize_monitor(current) != normalize_monitor(payload):
            print(f"UPDATE {monitor['name']}")
            if not args.dry_run:
                client.update_monitor(str(current["id"]), payload)
        else:
            print(f"OK     {monitor['name']}")

    if args.allow_delete:
        for current in existing_monitors:
            current_name = current.get("name", "")
            if not any(current_name.startswith(known_prefix) for known_prefix in prefixes):
                continue
            if current_name in desired_names:
                continue
            print(f"DELETE {current_name}")
            if not args.dry_run:
                client.delete_monitor(str(current["id"]))

    alerts_config = config.get("alerts", {})
    policy_config = alerts_config.get("policy", {})
    if policy_config.get("enabled", False):
        policies = client.list_policies()
        existing_policy = next(
            (policy for policy in policies if policy.get("name") == policy_config["name"]),
            None,
        )
        legacy_policy_names = policy_config.get("legacyNames", [])
        if existing_policy is None:
            existing_policy = next(
                (
                    policy
                    for policy in policies
                    if policy.get("name") in legacy_policy_names
                ),
                None,
            )
        if existing_policy is None:
            policy_payload = {
                "name": policy_config["name"],
                "incident_preference": policy_config["incidentPreference"],
            }
            print(f"CREATE POLICY {policy_config['name']}")
            if args.dry_run:
                policy_id = "dry-run-policy"
            else:
                created_policy = client.create_policy(policy_payload)
                policy_id = str(created_policy["policy"]["id"])
        else:
            policy_id = str(existing_policy["id"])
            current_policy_payload = {
                "name": existing_policy.get("name"),
                "incident_preference": existing_policy.get("incident_preference"),
            }
            desired_policy_payload = {
                "name": policy_config["name"],
                "incident_preference": policy_config["incidentPreference"],
            }
            if current_policy_payload != desired_policy_payload:
                print(f"UPDATE POLICY {policy_config['name']}")
                if not args.dry_run:
                    client.update_policy(policy_id, desired_policy_payload)
            else:
                print(f"OK     POLICY {policy_config['name']}")

        refreshed_monitors = client.list_monitors()
        monitors_by_name = {monitor.get("name"): monitor for monitor in refreshed_monitors}
        desired_conditions = build_desired_conditions(config, monitors_by_name)

        if args.dry_run and policy_id == "dry-run-policy":
            existing_conditions: List[Dict[str, Any]] = []
        else:
            existing_conditions = client.list_location_failure_conditions(policy_id)
        existing_conditions_by_name = {
            condition.get("name"): condition for condition in existing_conditions
        }

        for condition_name, payload in desired_conditions.items():
            current = find_existing_condition(
                condition_name,
                payload,
                existing_conditions_by_name,
                existing_conditions,
                prefixes,
            )
            if current is None:
                print(f"CREATE CONDITION {condition_name}")
                if not args.dry_run:
                    client.create_location_failure_condition(policy_id, payload)
                continue

            if normalize_condition(current) != normalize_condition(payload):
                print(f"UPDATE CONDITION {condition_name}")
                if not args.dry_run:
                    client.update_location_failure_condition(str(current["id"]), payload)
            else:
                print(f"OK     CONDITION {condition_name}")

        if args.allow_delete:
            desired_condition_names = set(desired_conditions)
            for current in existing_conditions:
                current_name = current.get("name")
                if current_name in desired_condition_names:
                    continue
                if not any(str(current_name).startswith(known_prefix) for known_prefix in prefixes):
                    continue
                print(f"DELETE CONDITION {current_name}")
                if not args.dry_run:
                    client.delete_location_failure_condition(str(current["id"]))

    return 0


if __name__ == "__main__":
    sys.exit(main())
