"""Validate a database restored by an AWS Backup restore testing plan.

EventBridge invokes this function when a restore job that belongs to the
restore testing plan changes state. For a completed restore it checks that the
restored instance is reachable and, optionally, that the data in it looks
right. It then reports the verdict back to AWS Backup, publishes metrics and
sends a notification.

A restore job that did not complete is reported too. A restore that fails is
the most important result a restore drill can produce.
"""

from __future__ import annotations

import json
import logging
import os
import socket
import ssl
import time
from datetime import UTC, date, datetime, timedelta
from typing import Any

import boto3

LOG = logging.getLogger()
LOG.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# AWS Backup rejects long status messages, and nobody reads them past this.
MAX_MESSAGE_LENGTH = 900
# Time kept in reserve so the verdict is always reported before the timeout.
REPORTING_RESERVE_SECONDS = 15
CA_BUNDLE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rds-ca.pem")


class ValidationError(Exception):
    """The restored database did not pass a check."""


def get_client(name: str) -> Any:
    """Return a boto3 client. Kept as a function so tests can replace it."""
    return boto3.client(name)


def load_config(env: dict[str, str] | None = None) -> dict[str, Any]:
    env = os.environ if env is None else env
    return {
        "engine": env.get("ENGINE", "postgres"),
        "db_name": env.get("DB_NAME", ""),
        "credentials_secret_arn": env.get("CREDENTIALS_SECRET_ARN", ""),
        "sql_checks": json.loads(env.get("SQL_CHECKS", "[]")),
        "connect_timeout": int(env.get("CONNECT_TIMEOUT_SECONDS", "10")),
        "ready_timeout": int(env.get("READY_TIMEOUT_SECONDS", "300")),
        "metric_namespace": env.get("METRIC_NAMESPACE", ""),
        "plan_name": env.get("PLAN_NAME", ""),
        "sns_topic_arn": env.get("SNS_TOPIC_ARN", ""),
        "notify_on_success": env.get("NOTIFY_ON_SUCCESS", "false").lower() == "true",
    }


def db_instance_identifier(resource_arn: str) -> str:
    """Extract the DB instance identifier from an RDS instance ARN."""
    parts = (resource_arn or "").split(":")
    if len(parts) < 7 or parts[2] != "rds" or parts[5] != "db":
        raise ValidationError(f"unsupported restored resource: {resource_arn!r}")
    return parts[6]


def wait_for_instance(rds: Any, identifier: str, deadline: float, poll_seconds: float = 15) -> dict[str, Any]:
    """Wait until the restored instance is available and has an endpoint."""
    status = "unknown"
    while True:
        instances = rds.describe_db_instances(DBInstanceIdentifier=identifier)["DBInstances"]
        if not instances:
            raise ValidationError(f"restored instance {identifier} was not found")
        instance = instances[0]
        status = instance.get("DBInstanceStatus", "unknown")
        if status == "available" and instance.get("Endpoint"):
            return instance
        if time.monotonic() + poll_seconds >= deadline:
            raise ValidationError(f"restored instance {identifier} is {status!r}, not 'available', after waiting")
        time.sleep(poll_seconds)


def check_tcp(host: str, port: int, timeout: int) -> None:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return
    except OSError as error:
        raise ValidationError(f"cannot open a TCP connection to {host}:{port}: {error}") from error


def tls_context(ca_bundle_path: str = CA_BUNDLE_PATH) -> ssl.SSLContext:
    """Always encrypt. Verify the server only when a CA bundle was packaged."""
    if os.path.exists(ca_bundle_path):
        return ssl.create_default_context(cafile=ca_bundle_path)
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    return context


def load_credentials(secrets: Any, secret_arn: str) -> tuple[str, str]:
    secret = json.loads(secrets.get_secret_value(SecretId=secret_arn)["SecretString"])
    try:
        return secret["username"], secret["password"]
    except KeyError as error:
        raise ValidationError(f"credentials secret has no {error.args[0]!r} key") from error


def run_queries(
    engine: str, host: str, port: int, db_name: str, user: str, password: str, queries: list[str], timeout: int
) -> list[list[tuple]]:
    """Run each query in a read-only session and return the rows per query."""
    context = tls_context()
    if engine == "postgres":
        try:
            import pg8000.native
        except ImportError as error:
            raise ValidationError("sql_checks need the pg8000 driver. Add it with lambda_layer_arns.") from error
        connection = pg8000.native.Connection(
            user,
            host=host,
            port=port,
            database=db_name,
            password=password,
            ssl_context=context,
            timeout=timeout,
        )
        try:
            connection.run("SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY")
            return [[tuple(row) for row in connection.run(query)] for query in queries]
        finally:
            connection.close()

    if engine == "mysql":
        try:
            import pymysql
        except ImportError as error:
            raise ValidationError("sql_checks need the PyMySQL driver. Add it with lambda_layer_arns.") from error
        connection = pymysql.connect(
            host=host,
            port=port,
            user=user,
            password=password,
            database=db_name,
            ssl=context,
            connect_timeout=timeout,
            read_timeout=timeout,
        )
        try:
            results = []
            with connection.cursor() as cursor:
                cursor.execute("SET SESSION TRANSACTION READ ONLY")
                for query in queries:
                    cursor.execute(query)
                    results.append([tuple(row) for row in cursor.fetchall()])
            return results
        finally:
            connection.close()

    raise ValidationError(f"unsupported engine: {engine!r}")


def evaluate_check(check: dict[str, Any], rows: list[tuple], now: datetime) -> str:
    """Compare the first column of the first row with the check's expectation."""
    name = check.get("name", "unnamed")
    if not rows or not rows[0]:
        raise ValidationError(f"{name}: query returned no rows")
    value = rows[0][0]

    min_value = check.get("min_value")
    if min_value is not None:
        try:
            number = float(value)
        except (TypeError, ValueError) as error:
            raise ValidationError(f"{name}: expected a number, got {value!r}") from error
        if number < float(min_value):
            raise ValidationError(f"{name}: {number:g} is below the minimum {float(min_value):g}")

    max_age_hours = check.get("max_age_hours")
    if max_age_hours is not None:
        if isinstance(value, datetime):
            moment = value
        elif isinstance(value, date):
            moment = datetime(value.year, value.month, value.day)
        else:
            raise ValidationError(f"{name}: expected a timestamp, got {value!r}")
        if moment.tzinfo is None:
            moment = moment.replace(tzinfo=UTC)
        age = now - moment
        if age > timedelta(hours=float(max_age_hours)):
            hours = age.total_seconds() / 3600
            raise ValidationError(f"{name}: newest value is {hours:.1f}h old, limit is {float(max_age_hours):g}h")

    return f"{name}: ok ({value})"


def validate_restored_database(config: dict[str, Any], resource_arn: str, deadline: float) -> list[str]:
    """Run every check against the restored instance. Raise on the first failure."""
    passed = []
    identifier = db_instance_identifier(resource_arn)
    ready_deadline = min(deadline, time.monotonic() + config["ready_timeout"])
    instance = wait_for_instance(get_client("rds"), identifier, ready_deadline)
    passed.append("instance: available")

    host = instance["Endpoint"]["Address"]
    port = int(instance["Endpoint"]["Port"])
    check_tcp(host, port, config["connect_timeout"])
    passed.append("tcp: reachable")

    checks = config["sql_checks"]
    if not checks:
        return passed
    if not config["credentials_secret_arn"]:
        raise ValidationError("sql_checks are set but credentials_secret_arn is not")

    user, password = load_credentials(get_client("secretsmanager"), config["credentials_secret_arn"])
    results = run_queries(
        config["engine"],
        host,
        port,
        config["db_name"],
        user,
        password,
        [check["query"] for check in checks],
        config["connect_timeout"],
    )
    now = datetime.now(UTC)
    for check, rows in zip(checks, results, strict=True):
        passed.append(evaluate_check(check, rows, now))
    return passed


def restore_duration_seconds(job: dict[str, Any]) -> float | None:
    started, finished = job.get("CreationDate"), job.get("CompletionDate")
    if isinstance(started, datetime) and isinstance(finished, datetime):
        return max((finished - started).total_seconds(), 0.0)
    return None


def report_validation(backup: Any, job_id: str, succeeded: bool, message: str) -> None:
    """Report the verdict to AWS Backup. A verdict can be set only once."""
    try:
        backup.put_restore_validation_result(
            RestoreJobId=job_id,
            ValidationStatus="SUCCESSFUL" if succeeded else "FAILED",
            ValidationStatusMessage=message[:MAX_MESSAGE_LENGTH],
        )
    except Exception:  # a duplicate event must not hide the result
        LOG.exception("could not report the validation result for restore job %s", job_id)


def publish_metrics(config: dict[str, Any], succeeded: bool, duration: float | None) -> None:
    if not config["metric_namespace"]:
        return
    dimensions = [{"Name": "PlanName", "Value": config["plan_name"]}]
    metrics = [
        {"MetricName": "DrillSuccess", "Dimensions": dimensions, "Value": 1 if succeeded else 0, "Unit": "Count"}
    ]
    if duration is not None:
        metrics.append(
            {"MetricName": "RestoreDurationSeconds", "Dimensions": dimensions, "Value": duration, "Unit": "Seconds"}
        )
    try:
        get_client("cloudwatch").put_metric_data(Namespace=config["metric_namespace"], MetricData=metrics)
    except Exception:  # metrics must not change the verdict
        LOG.exception("could not publish metrics")


def notify(config: dict[str, Any], result: dict[str, Any]) -> None:
    if not config["sns_topic_arn"]:
        return
    if result["succeeded"] and not config["notify_on_success"]:
        return
    outcome = "passed" if result["succeeded"] else "FAILED"
    try:
        get_client("sns").publish(
            TopicArn=config["sns_topic_arn"],
            Subject=f"Restore drill {outcome}: {config['plan_name']}"[:100],
            Message=json.dumps(result, indent=2, default=str),
        )
    except Exception:  # a notification must not change the verdict
        LOG.exception("could not send the notification")


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    config = load_config()
    detail = event.get("detail") or {}
    job_id = detail.get("restoreJobId")
    status = detail.get("status")
    if not job_id:
        LOG.error("event has no restoreJobId, ignoring: %s", json.dumps(event, default=str))
        return {"succeeded": False, "message": "event has no restoreJobId"}

    result: dict[str, Any] = {
        "restoreJobId": job_id,
        "restoreStatus": status,
        "resourceArn": detail.get("createdResourceArn"),
        "planName": config["plan_name"],
        "succeeded": False,
        "restoreDurationSeconds": None,
        "checks": [],
        "message": "",
    }
    backup = get_client("backup")

    if status != "COMPLETED":
        result["message"] = f"restore job ended with status {status}"
        LOG.error(result["message"])
    else:
        remaining = context.get_remaining_time_in_millis() / 1000 if context else 60
        deadline = time.monotonic() + max(remaining - REPORTING_RESERVE_SECONDS, 1)
        try:
            job = backup.describe_restore_job(RestoreJobId=job_id)
            result["restoreDurationSeconds"] = restore_duration_seconds(job)
            resource_arn = result["resourceArn"] or job.get("CreatedResourceArn", "")
            result["resourceArn"] = resource_arn
            result["checks"] = validate_restored_database(config, resource_arn, deadline)
            result["succeeded"] = True
            result["message"] = "; ".join(result["checks"])
        except ValidationError as error:
            result["message"] = str(error)
            LOG.error("validation failed: %s", error)
        except Exception as error:  # every failure must be reported as a failed drill
            result["message"] = f"validator error: {type(error).__name__}: {error}"
            LOG.exception("validator error")
        report_validation(backup, job_id, result["succeeded"], result["message"])

    publish_metrics(config, result["succeeded"], result["restoreDurationSeconds"])
    notify(config, result)
    LOG.info("result: %s", json.dumps(result, default=str))
    return result
