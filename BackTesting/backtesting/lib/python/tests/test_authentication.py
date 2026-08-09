import unittest
from unittest.mock import ANY, patch

from fastapi import HTTPException

import main as api


class FirebaseAuthenticationTests(unittest.TestCase):
    def test_missing_authorization_header_is_rejected(self):
        with self.assertRaises(HTTPException) as context:
            api.require_firebase_user(None)

        self.assertEqual(context.exception.status_code, 401)
        self.assertEqual(context.exception.detail, "Authentication required.")

    def test_invalid_authorization_header_is_rejected(self):
        with self.assertRaises(HTTPException) as context:
            api.require_firebase_user("Basic credentials")

        self.assertEqual(context.exception.status_code, 401)
        self.assertEqual(context.exception.detail, "Invalid authorization header.")

    def test_valid_bearer_token_returns_decoded_claims(self):
        expected_claims = {"uid": "test-user", "email": "user@example.com"}

        with (
            patch.object(api, "_firebase_app", return_value=object()),
            patch.object(
                api.firebase_auth,
                "verify_id_token",
                return_value=expected_claims,
            ) as verify,
        ):
            claims = api.require_firebase_user("Bearer valid-token")

        self.assertEqual(claims, expected_claims)
        verify.assert_called_once_with("valid-token", app=ANY)

    def test_invalid_bearer_token_is_rejected(self):
        with (
            patch.object(api, "_firebase_app", return_value=object()),
            patch.object(
                api.firebase_auth,
                "verify_id_token",
                side_effect=ValueError("invalid token"),
            ),
            self.assertRaises(HTTPException) as context,
        ):
            api.require_firebase_user("Bearer invalid-token")

        self.assertEqual(context.exception.status_code, 401)
        self.assertEqual(
            context.exception.detail,
            "Invalid or expired authentication token.",
        )

    def test_compute_routes_require_firebase_authentication(self):
        protected_paths = {
            "/optimize",
            "/portfolio-stats",
            "/rolling-backtest",
            "/backtest",
            "/simulate",
            "/correlation",
        }

        routes = {route.path: route for route in api.app.routes}
        for path in protected_paths:
            dependency_calls = {
                dependency.call for dependency in routes[path].dependant.dependencies
            }
            self.assertIn(api.require_firebase_user, dependency_calls, path)


if __name__ == "__main__":
    unittest.main()
