import os
import tempfile
import unittest

from affine_sync import cli


class Lock(unittest.TestCase):
    def setUp(self):
        self._home = tempfile.mkdtemp()
        os.environ["AFFINE_SYNC_HOME"] = self._home

    def tearDown(self):
        os.environ.pop("AFFINE_SYNC_HOME", None)

    def test_lock_is_exclusive(self):
        a = cli._acquire_lock()
        self.assertIsNotNone(a)                 # first acquire wins
        b = cli._acquire_lock()
        self.assertIsNone(b)                     # held -> second is refused
        a.close()                                # release
        c = cli._acquire_lock()
        self.assertIsNotNone(c)                  # freed -> acquires again
        c.close()


if __name__ == "__main__":
    unittest.main()
