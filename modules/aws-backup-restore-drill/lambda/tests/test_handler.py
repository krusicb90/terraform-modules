"""Unit tests for the restore drill validator. No AWS access is needed."""

from __future__ import annotations

import os
import sys
from datetime import UTC, datetime, timedelta
from unittest import mock

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import handler  # noqa: E402

JOB_ID = "11111111-2222-3333-4444-555555555555"
RESOURCE_ARN = "arn:aws:rds:eu-central-1:123456789012:db:awsbackup-restore-test-abc123"
NOW = datetime(2026, 1, 10, 12, 0, tzinfo=UTC)


class FakeContext:
    def __init__(self, seconds: float = 120):
        self._millis = int(seconds * 1000)

    def get_remaining_time_in_millis(self) -> int:
        return self._millis


def event(status: str = "COMPLETED") -> dict:
    return {
        "source": "aws.backup",
        "detail-type": "Restore Job State Change",
        "detail": {
            "restoreJobId": JOB_ID,
            "status": status,
            "resourceType": "RDS",
            "createdResourceArn": RESOURCE_ARN,
            "restoreTestingPlanArn": "arn:aws:backup:eu-central-1:123456789012:restore-testing-plan:drill",
        },
    }


@pytest.fixture
def clients(monkeypatch):
    """Replace every AWS client with a mock and give the instance a healthy default."""
    fakes = {name: mock.MagicMock(name=name) for name in ("backup", "rds", "secretsmanager", "cloudwatch", "sns")}
    fakes["backup"].describe_restore_job.return_value = {
        "CreationDate": NOW - timedelta(minutes=25),
        "CompletionDate": NOW,
        "CreatedResourceArn": RESOURCE_ARN,
    }
    fakes["rds"].describe_db_instances.return_value = {
        "DBInstances": [{"DBInstanceStatus": "available", "Endpoint": {"Address": "db.internal", "Port": 5432}}]
    }
    fakes["secretsmanager"].get_secret_value.return_value = {"SecretString": '{"username": "app", "password": "pw"}'}
    monkeypatch.setattr(handler, "get_client", lambda name: fakes[name])
    monkeypatch.setattr(handler, "check_tcp", lambda host, port, timeout: None)
    for key in ("SQL_CHECKS", "CREDENTIALS_SECRET_ARN", "SNS_TOPIC_ARN", "NOTIFY_ON_SUCCESS"):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setenv("METRIC_NAMESPACE", "RestoreDrill")
    monkeypatch.setenv("PLAN_NAME", "drill")
    return fakes


def metric(clients, name):
    data = clients["cloudwatch"].put_metric_data.call_args.kwargs["MetricData"]
    return next(item["Value"] for item in data if item["MetricName"] == name)


# --- pure helpers -----------------------------------------------------------


def test_identifier_is_taken_from_an_rds_instance_arn():
    assert handler.db_instance_identifier(RESOURCE_ARN) == "awsbackup-restore-test-abc123"


@pytest.mark.parametrize("arn", ["", "arn:aws:s3:::bucket", "arn:aws:rds:eu-central-1:123456789012:cluster:c1"])
def test_other_resources_are_rejected(arn):
    with pytest.raises(handler.ValidationError):
        handler.db_instance_identifier(arn)


def test_min_value_passes_and_fails():
    check = {"name": "orders", "min_value": 100}
    assert "ok" in handler.evaluate_check(check, [(250,)], NOW)
    with pytest.raises(handler.ValidationError, match="below the minimum"):
        handler.evaluate_check(check, [(3,)], NOW)


def test_min_value_needs_a_number():
    with pytest.raises(handler.ValidationError, match="expected a number"):
        handler.evaluate_check({"name": "orders", "min_value": 1}, [("abc",)], NOW)


def test_max_age_accepts_fresh_data_and_rejects_stale_data():
    check = {"name": "newest order", "max_age_hours": 26}
    assert "ok" in handler.evaluate_check(check, [(NOW - timedelta(hours=2),)], NOW)
    with pytest.raises(handler.ValidationError, match="limit is 26h"):
        handler.evaluate_check(check, [(NOW - timedelta(hours=40),)], NOW)


def test_max_age_treats_naive_timestamps_as_utc():
    naive = (NOW - timedelta(hours=1)).replace(tzinfo=None)
    assert "ok" in handler.evaluate_check({"name": "t", "max_age_hours": 2}, [(naive,)], NOW)


def test_a_query_without_rows_fails():
    with pytest.raises(handler.ValidationError, match="no rows"):
        handler.evaluate_check({"name": "orders"}, [], NOW)


def test_restore_duration_is_measured_from_the_job():
    job = {"CreationDate": NOW - timedelta(minutes=25), "CompletionDate": NOW}
    assert handler.restore_duration_seconds(job) == 1500
    assert handler.restore_duration_seconds({}) is None


def test_tls_verifies_only_when_a_ca_bundle_is_packaged(tmp_path):
    import ssl

    assert handler.tls_context(str(tmp_path / "missing.pem")).verify_mode == ssl.CERT_NONE


# --- handler ----------------------------------------------------------------


def test_a_healthy_restore_is_reported_as_successful(clients):
    result = handler.handler(event(), FakeContext())

    assert result["succeeded"] is True
    assert result["checks"] == ["instance: available", "tcp: reachable"]
    clients["backup"].put_restore_validation_result.assert_called_once()
    call = clients["backup"].put_restore_validation_result.call_args.kwargs
    assert call["RestoreJobId"] == JOB_ID
    assert call["ValidationStatus"] == "SUCCESSFUL"
    assert metric(clients, "DrillSuccess") == 1
    assert metric(clients, "RestoreDurationSeconds") == 1500


def test_a_failed_restore_job_is_not_validated_but_is_reported(clients, monkeypatch):
    monkeypatch.setenv("SNS_TOPIC_ARN", "arn:aws:sns:eu-central-1:123456789012:alerts")

    result = handler.handler(event("FAILED"), FakeContext())

    assert result["succeeded"] is False
    clients["backup"].put_restore_validation_result.assert_not_called()
    clients["rds"].describe_db_instances.assert_not_called()
    assert metric(clients, "DrillSuccess") == 0
    assert "FAILED" in clients["sns"].publish.call_args.kwargs["Subject"]


def test_an_instance_that_never_becomes_available_fails_the_drill(clients, monkeypatch):
    clients["rds"].describe_db_instances.return_value = {"DBInstances": [{"DBInstanceStatus": "creating"}]}
    monkeypatch.setattr(handler.time, "sleep", lambda seconds: None)

    result = handler.handler(event(), FakeContext(seconds=20))

    assert result["succeeded"] is False
    assert "'creating'" in result["message"]
    assert clients["backup"].put_restore_validation_result.call_args.kwargs["ValidationStatus"] == "FAILED"


def test_an_unreachable_instance_fails_the_drill(clients, monkeypatch):
    def refuse(host, port, timeout):
        raise handler.ValidationError("cannot open a TCP connection to db.internal:5432: timed out")

    monkeypatch.setattr(handler, "check_tcp", refuse)

    result = handler.handler(event(), FakeContext())

    assert result["succeeded"] is False
    assert "TCP" in result["message"]


def test_sql_checks_run_and_are_evaluated(clients, monkeypatch):
    monkeypatch.setenv("CREDENTIALS_SECRET_ARN", "arn:aws:secretsmanager:eu-central-1:123456789012:secret:db")
    monkeypatch.setenv(
        "SQL_CHECKS",
        '[{"name": "orders", "query": "select count(*) from orders", "min_value": 10},'
        ' {"name": "newest", "query": "select max(created_at) from orders", "max_age_hours": 26}]',
    )
    seen = {}

    def fake_queries(engine, host, port, db_name, user, password, queries, timeout):
        seen.update(engine=engine, user=user, queries=queries)
        return [[(42,)], [(datetime.now(UTC) - timedelta(hours=3),)]]

    monkeypatch.setattr(handler, "run_queries", fake_queries)

    result = handler.handler(event(), FakeContext())

    assert result["succeeded"] is True
    assert len(result["checks"]) == 4
    assert seen["user"] == "app"
    assert seen["queries"] == ["select count(*) from orders", "select max(created_at) from orders"]


def test_a_failing_sql_check_fails_the_drill(clients, monkeypatch):
    monkeypatch.setenv("CREDENTIALS_SECRET_ARN", "arn:aws:secretsmanager:eu-central-1:123456789012:secret:db")
    monkeypatch.setenv("SQL_CHECKS", '[{"name": "orders", "query": "select count(*) from orders", "min_value": 10}]')
    monkeypatch.setattr(handler, "run_queries", lambda *args: [[(0,)]])

    result = handler.handler(event(), FakeContext())

    assert result["succeeded"] is False
    assert "below the minimum" in result["message"]
    assert metric(clients, "DrillSuccess") == 0


def test_sql_checks_without_credentials_fail_with_a_clear_message(clients, monkeypatch):
    monkeypatch.setenv("SQL_CHECKS", '[{"name": "orders", "query": "select 1"}]')

    result = handler.handler(event(), FakeContext())

    assert result["succeeded"] is False
    assert "credentials_secret_arn" in result["message"]


def test_a_missing_driver_fails_with_a_clear_message(clients, monkeypatch):
    monkeypatch.setenv("CREDENTIALS_SECRET_ARN", "arn:aws:secretsmanager:eu-central-1:123456789012:secret:db")
    monkeypatch.setenv("SQL_CHECKS", '[{"name": "orders", "query": "select 1"}]')
    monkeypatch.setitem(sys.modules, "pg8000", None)
    monkeypatch.setitem(sys.modules, "pg8000.native", None)

    result = handler.handler(event(), FakeContext())

    assert result["succeeded"] is False
    assert "lambda_layer_arns" in result["message"]


def test_an_unexpected_error_still_reports_a_failed_drill(clients):
    clients["backup"].describe_restore_job.side_effect = RuntimeError("throttled")

    result = handler.handler(event(), FakeContext())

    assert result["succeeded"] is False
    assert "validator error" in result["message"]
    assert clients["backup"].put_restore_validation_result.call_args.kwargs["ValidationStatus"] == "FAILED"


def test_a_duplicate_event_does_not_crash_when_the_verdict_is_already_set(clients):
    clients["backup"].put_restore_validation_result.side_effect = RuntimeError("validation status already set")

    result = handler.handler(event(), FakeContext())

    assert result["succeeded"] is True


def test_success_does_not_notify_unless_asked(clients, monkeypatch):
    monkeypatch.setenv("SNS_TOPIC_ARN", "arn:aws:sns:eu-central-1:123456789012:alerts")
    handler.handler(event(), FakeContext())
    clients["sns"].publish.assert_not_called()

    monkeypatch.setenv("NOTIFY_ON_SUCCESS", "true")
    handler.handler(event(), FakeContext())
    clients["sns"].publish.assert_called_once()


def test_an_event_without_a_job_id_is_ignored(clients):
    result = handler.handler({"detail": {}}, FakeContext())

    assert result["succeeded"] is False
    clients["backup"].describe_restore_job.assert_not_called()
