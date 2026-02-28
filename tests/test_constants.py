"""
Unit tests for constants module
"""
import sys
import unittest
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from lib.constants import (
    PROCESSING_STATUS_PENDING,
    PROCESSING_STATUS_PROCESSING,
    PROCESSING_STATUS_COMPLETED,
    PROCESSING_STATUS_FAILED,
    UPLOAD_STATUS_NOT_UPLOADED,
    UPLOAD_STATUS_UPLOADING,
    UPLOAD_STATUS_UPLOADED,
    UPLOAD_STATUS_FAILED,
    ALLOWED_IMAGE_EXTENSIONS,
    DEFAULT_CONCURRENCY,
    MAX_FILE_SIZE_MB,
    MAX_FILE_SIZE_BYTES,
)


class TestConstants(unittest.TestCase):
    """Tests for project constants"""
    
    def test_processing_statuses_are_strings(self):
        """All processing statuses should be non-empty strings"""
        for status in [
            PROCESSING_STATUS_PENDING,
            PROCESSING_STATUS_PROCESSING,
            PROCESSING_STATUS_COMPLETED,
            PROCESSING_STATUS_FAILED,
        ]:
            self.assertIsInstance(status, str)
            self.assertTrue(len(status) > 0)
    
    def test_upload_statuses_are_strings(self):
        """All upload statuses should be non-empty strings"""
        for status in [
            UPLOAD_STATUS_NOT_UPLOADED,
            UPLOAD_STATUS_UPLOADING,
            UPLOAD_STATUS_UPLOADED,
            UPLOAD_STATUS_FAILED,
        ]:
            self.assertIsInstance(status, str)
            self.assertTrue(len(status) > 0)
    
    def test_processing_statuses_are_unique(self):
        """All processing status values should be distinct"""
        statuses = [
            PROCESSING_STATUS_PENDING,
            PROCESSING_STATUS_PROCESSING,
            PROCESSING_STATUS_COMPLETED,
            PROCESSING_STATUS_FAILED,
        ]
        self.assertEqual(len(statuses), len(set(statuses)))
    
    def test_upload_statuses_are_unique(self):
        """All upload status values should be distinct"""
        statuses = [
            UPLOAD_STATUS_NOT_UPLOADED,
            UPLOAD_STATUS_UPLOADING,
            UPLOAD_STATUS_UPLOADED,
            UPLOAD_STATUS_FAILED,
        ]
        self.assertEqual(len(statuses), len(set(statuses)))
    
    def test_allowed_extensions_contains_jpg(self):
        """Image extensions should include common formats"""
        self.assertIn('.jpg', ALLOWED_IMAGE_EXTENSIONS)
        self.assertIn('.jpeg', ALLOWED_IMAGE_EXTENSIONS)
        self.assertIn('.png', ALLOWED_IMAGE_EXTENSIONS)
    
    def test_max_file_size_bytes_calculation(self):
        """MAX_FILE_SIZE_BYTES should equal MAX_FILE_SIZE_MB * 1024 * 1024"""
        self.assertEqual(MAX_FILE_SIZE_BYTES, MAX_FILE_SIZE_MB * 1024 * 1024)
    
    def test_default_concurrency_positive(self):
        """Default concurrency should be a positive integer"""
        self.assertIsInstance(DEFAULT_CONCURRENCY, int)
        self.assertGreater(DEFAULT_CONCURRENCY, 0)


if __name__ == '__main__':
    unittest.main()
