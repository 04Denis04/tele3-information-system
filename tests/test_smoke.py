"""Простой smoke-тест страницы авторизации."""
import unittest

from app import create_app


class LoginPageSmokeTest(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.app.config.update(TESTING=True, SECRET_KEY="test-secret-key")
        self.client = self.app.test_client()

    def test_login_page_is_available(self):
        response = self.client.get("/login")

        self.assertEqual(response.status_code, 200)
        self.assertIn("Войти в систему", response.get_data(as_text=True))


if __name__ == "__main__":
    unittest.main()
