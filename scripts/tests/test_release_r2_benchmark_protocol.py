import copy
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPOSITORY_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

from r2_benchmark_support import (  # noqa: E402
    capture_preflight,
    evaluate_preflight,
    memory_gate,
)


class R2ReleaseBenchmarkProtocolTests(unittest.TestCase):
    def test_memory_gate_requires_relative_and_absolute_breaches(self):
        relative_only = memory_gate(10_000_000, 11_600_000, 15, 2_097_152)
        both = memory_gate(10_000_000, 12_097_153, 15, 2_097_152)
        self.assertTrue(relative_only["relativeLimitBreached"])
        self.assertFalse(relative_only["absoluteLimitBreached"])
        self.assertEqual(relative_only["verdict"], "pass")
        self.assertTrue(both["relativeLimitBreached"])
        self.assertTrue(both["absoluteLimitBreached"])
        self.assertEqual(both["verdict"], "fail")

    def test_preflight_requires_every_sample_to_meet_frozen_limits(self):
        policy = {
            "maximumOneMinuteLoad": 14.0,
            "minimumCPUIdlePercent": 40.0,
            "maximumDiskMegabytesPerSecond": 1.0,
        }
        passing = [
            {
                "oneMinuteLoad": 7.0,
                "cpuIdlePercent": 60.0,
                "diskMegabytesPerSecond": 0.0,
            },
            {
                "oneMinuteLoad": 14.0,
                "cpuIdlePercent": 40.0,
                "diskMegabytesPerSecond": 1.0,
            },
        ]
        self.assertEqual(evaluate_preflight(passing, policy)["verdict"], "pass")
        for key, value in (
            ("oneMinuteLoad", 14.01),
            ("cpuIdlePercent", 39.99),
            ("diskMegabytesPerSecond", 1.01),
        ):
            failing = copy.deepcopy(passing)
            failing[1][key] = value
            self.assertEqual(evaluate_preflight(failing, policy)["verdict"], "fail")

    def test_preflight_observes_the_full_frozen_duration(self):
        policy = {
            "durationSeconds": 30,
            "sampleIntervalSeconds": 5,
            "maximumOneMinuteLoad": 14.0,
            "minimumCPUIdlePercent": 40.0,
            "maximumDiskMegabytesPerSecond": 1.0,
        }
        clock = {"value": 0.0}

        def monotonic():
            return clock["value"]

        def sleep(seconds):
            clock["value"] += seconds

        with patch(
            "r2_benchmark_support.time.monotonic", side_effect=monotonic
        ), patch(
            "r2_benchmark_support.time.sleep", side_effect=sleep
        ), patch(
            "r2_benchmark_support.os.getloadavg", return_value=(5.0, 4.0, 3.0)
        ), patch(
            "r2_benchmark_support.current_cpu_idle_percent", return_value=80.0
        ), patch(
            "r2_benchmark_support.current_disk_megabytes_per_second", return_value=0.0
        ):
            observed = capture_preflight(policy)

        self.assertEqual(observed["elapsedSeconds"], 30.0)
        self.assertEqual(len(observed["samples"]), 6)
        self.assertEqual(observed["verdict"], "pass")


if __name__ == "__main__":
    unittest.main()
