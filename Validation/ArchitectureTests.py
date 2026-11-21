#!/usr/bin/env python3
"""Test the architecture gate independently of actual signature checks.
Real release signatures are verified against every page by verify_package.py.
"""
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import verify_package

class Arm64eOnlyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'binary'
    def check_blob(self, blob, success):
        self.path.write_bytes(blob)
        with patch.object(verify_package, 'verify_signature', return_value=['checked']) as signature:
            if success:
                result = verify_package.verify_macho(self.path)
                self.assertEqual([r['arch'] for r in result], ['arm64e'])
                signature.assert_called_once_with(blob)
            else:
                with self.assertRaises(AssertionError):
                    verify_package.verify_macho(self.path)
                signature.assert_not_called()
    def thin(self, cpu=0x0100000c, subtype=0x80000002):
        return struct.pack('<8I', 0xfeedfacf, cpu, subtype, 6, 0, 0, 0, 0)
    def test_modern_arm64e_accepted(self):
        self.check_blob(self.thin(), True)
    def test_arm64_rejected(self):
        self.check_blob(self.thin(subtype=0), False)
    def test_legacy_arm64e_rejected(self):
        self.check_blob(self.thin(subtype=2), False)
    def test_other_cpu_rejected(self):
        self.check_blob(self.thin(cpu=0x01000007), False)
    def test_fat32_and_fat64_rejected(self):
        for magic in (0xcafebabe, 0xcafebabf):
            with self.subTest(magic=magic):
                self.check_blob(struct.pack('>8I', magic, 2, 0, 0, 0, 0, 0, 0), False)
    def test_truncated_rejected(self):
        for size in (0, 4, 16, 31):
            with self.subTest(size=size):
                self.check_blob(b'\0' * size, False)

if __name__ == '__main__':
    unittest.main(verbosity=2)
