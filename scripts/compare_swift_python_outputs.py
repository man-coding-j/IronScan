from __future__ import annotations

import subprocess


def main() -> None:
    subprocess.run(["uv", "run", "pytest", "PythonReference/tests"], check=True)
    print("Python parity fixtures are internally consistent; run iOS golden tests for Swift comparison.")


if __name__ == "__main__":
    main()
