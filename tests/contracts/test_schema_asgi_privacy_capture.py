from __future__ import annotations

import logging
import sys
import unittest
from typing import Any

from expected_red.test_backend_heartbeat_acceptance import SENSITIVE_CANARY, _request


def _fixture_app(mode: str):  # type: ignore[no-untyped-def]
    async def app(
        scope: dict[str, Any],
        receive: Any,
        send: Any,
    ) -> None:
        if mode == "stdout":
            print(SENSITIVE_CANARY)
        elif mode == "stdout_overcap":
            print("X" * 70000)
        elif mode == "stderr":
            print(SENSITIVE_CANARY, file=sys.stderr)
        elif mode == "logger":
            logging.getLogger("thrivelens.contract.fixture").warning(SENSITIVE_CANARY)
        elif mode in {"logger_handle", "logger_call_handlers"}:
            logger = logging.getLogger("thrivelens.contract.fixture")
            record = logging.LogRecord(
                logger.name,
                logging.WARNING,
                "fixture",
                1,
                SENSITIVE_CANARY,
                (),
                None,
            )
            if mode == "logger_handle":
                logger.handle(record)
            else:
                logger.callHandlers(record)
        await send(
            {
                "type": "http.response.start",
                "status": 204,
                "headers": [],
            }
        )
        await send({"type": "http.response.body", "body": b"", "more_body": False})

    return app


class AsgiPrivacyCaptureTests(unittest.TestCase):
    def test_silent_asgi_request_is_accepted(self) -> None:
        status, headers, body = _request(_fixture_app("silent"), "GET", "/fixture")
        self.assertEqual((status, headers, body), (204, {}, b""))

    def test_stdout_stderr_and_python_logger_are_all_rejected(self) -> None:
        for mode in (
            "stdout",
            "stdout_overcap",
            "stderr",
            "logger",
            "logger_handle",
            "logger_call_handlers",
        ):
            with self.subTest(mode=mode):
                with self.assertRaises(AssertionError):
                    _request(
                        _fixture_app(mode),
                        "GET",
                        f"/fixture/{SENSITIVE_CANARY}",
                        {
                            "authorization": f"Bearer {SENSITIVE_CANARY}",
                            "x-private-value": SENSITIVE_CANARY,
                        },
                        f"private={SENSITIVE_CANARY}".encode("ascii"),
                        SENSITIVE_CANARY.encode("ascii"),
                    )


if __name__ == "__main__":
    unittest.main()
