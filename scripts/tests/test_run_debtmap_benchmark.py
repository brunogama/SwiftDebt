import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "run_debtmap_benchmark", ROOT / "scripts" / "run_debtmap_benchmark.py"
)
assert SPEC is not None and SPEC.loader is not None
BENCHMARK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BENCHMARK)


class DebtmapBenchmarkPairingTests(unittest.TestCase):
    def test_paired_samples_are_adjacent_and_alternate_order(self) -> None:
        calls: list[str] = []

        def timed(command: list[str]) -> tuple[float, int]:
            role = command[0]
            calls.append(role)
            return (1.0 if role == "reference" else 2.0, 100 if role == "reference" else 200)

        with mock.patch.object(BENCHMARK, "timed_command", side_effect=timed):
            reference, candidate = BENCHMARK.collect_samples(
                ["reference", "analyze"],
                warmups=1,
                runs=4,
                paired_command=["candidate", "analyze"],
            )

        self.assertEqual(
            calls,
            [
                "reference",
                "candidate",
                "candidate",
                "reference",
                "reference",
                "candidate",
                "candidate",
                "reference",
                "reference",
                "candidate",
            ],
        )
        self.assertEqual([sample["pairIndex"] for sample in reference], [0, 1, 2, 3])
        self.assertEqual([sample["orderInPair"] for sample in reference], [2, 1, 2, 1])
        self.assertEqual([sample["pairIndex"] for sample in candidate], [0, 1, 2, 3])
        self.assertEqual([sample["orderInPair"] for sample in candidate], [1, 2, 1, 2])
        self.assertEqual([sample["peakMemoryBytes"] for sample in reference], [100] * 4)
        self.assertEqual([sample["peakMemoryBytes"] for sample in candidate], [200] * 4)

    def test_unpaired_sampling_keeps_existing_sequence(self) -> None:
        calls: list[str] = []

        def timed(command: list[str]) -> tuple[float, int]:
            calls.append(command[0])
            return 1.0, 100

        with mock.patch.object(BENCHMARK, "timed_command", side_effect=timed):
            samples, paired = BENCHMARK.collect_samples(["command"], warmups=2, runs=3)

        self.assertEqual(calls, ["command"] * 5)
        self.assertIsNone(paired)
        self.assertEqual(len(samples), 3)
        self.assertNotIn("pairIndex", samples[0])

    def test_paired_cli_outputs_share_metadata_and_retain_raw_samples(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            input_path = root / "input.swift"
            reference_path = root / "reference.json"
            candidate_path = root / "candidate.json"
            input_path.write_text("struct Input {}\n", encoding="utf-8")

            def timed(command: list[str]) -> tuple[float, int]:
                return (1.0, 100) if command[0] == "reference" else (1.1, 110)

            arguments = [
                "run_debtmap_benchmark.py",
                "--output",
                str(reference_path),
                "--paired-output",
                str(candidate_path),
                "--paired-executable",
                "candidate",
                "--input",
                str(input_path),
                "--analyzer",
                "SwiftDebt",
                "--workload-family",
                "SwiftDebt",
                "--command-fingerprint",
                "frozen",
                "--analysis-mode",
                "baseline",
                "--optional-context",
                "none",
                "--warmups",
                "0",
                "--runs",
                "2",
                "--",
                "reference",
                "analyze",
            ]
            with (
                mock.patch.object(sys, "argv", arguments),
                mock.patch.object(BENCHMARK, "timed_command", side_effect=timed),
                mock.patch.object(BENCHMARK, "command_output", return_value="Swift test"),
                mock.patch.object(BENCHMARK, "cpu_model", return_value="Test CPU"),
                mock.patch.object(BENCHMARK, "system_memory_bytes", return_value=1024),
            ):
                self.assertEqual(BENCHMARK.main(), 0)

            reference = json.loads(reference_path.read_text(encoding="utf-8"))
            candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
            self.assertEqual(reference["workload"], candidate["workload"])
            self.assertEqual(reference["metadata"], candidate["metadata"])
            self.assertEqual(reference["metadata"]["measurementDesign"], "paired-interleaved-v1")
            self.assertEqual(reference["wallClockSecondsMedian"], 1.0)
            self.assertEqual(candidate["wallClockSecondsMedian"], 1.1)
            self.assertEqual(
                [(sample["pairIndex"], sample["orderInPair"]) for sample in reference["samples"]],
                [(0, 1), (1, 2)],
            )
            self.assertEqual(
                [(sample["pairIndex"], sample["orderInPair"]) for sample in candidate["samples"]],
                [(0, 2), (1, 1)],
            )

    def test_paired_cli_rejects_canonical_same_output_before_measurement(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            nested = root / "nested"
            nested.mkdir()
            input_path = root / "input.swift"
            output_path = root / "result.json"
            output_alias = nested / ".." / "result.json"
            input_path.write_text("struct Input {}\n", encoding="utf-8")
            arguments = [
                "run_debtmap_benchmark.py",
                "--output",
                str(output_path),
                "--paired-output",
                str(output_alias),
                "--paired-executable",
                "candidate",
                "--input",
                str(input_path),
                "--analyzer",
                "SwiftDebt",
                "--workload-family",
                "SwiftDebt",
                "--command-fingerprint",
                "frozen",
                "--analysis-mode",
                "baseline",
                "--optional-context",
                "none",
                "--",
                "reference",
            ]
            error_output = io.StringIO()
            with (
                mock.patch.object(sys, "argv", arguments),
                mock.patch.object(BENCHMARK, "timed_command") as timed_command,
                mock.patch.object(sys, "stderr", error_output),
            ):
                with self.assertRaises(SystemExit) as raised:
                    BENCHMARK.main()

            self.assertEqual(raised.exception.code, 2)
            self.assertIn(
                "--output and --paired-output must resolve to different paths",
                error_output.getvalue(),
            )
            timed_command.assert_not_called()
            self.assertFalse(output_path.exists())


if __name__ == "__main__":
    unittest.main()
