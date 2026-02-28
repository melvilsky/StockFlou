"""
Unit tests for StateManager
"""
import os
import sys
import tempfile
import unittest
from pathlib import Path
from datetime import datetime

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from lib.state.state_manager import StateManager
from lib.state.models import FileRecord


class TestStateManager(unittest.TestCase):
    """Tests for StateManager"""
    
    def setUp(self):
        """Create StateManager with temporary database"""
        self.tmp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.tmp_dir, 'test_state.db')
        self.sm = StateManager(self.db_path)
        
        # Create a temporary image file for hashing tests
        self.test_file = Path(self.tmp_dir) / 'test_image.jpg'
        self.test_file.write_bytes(b'\xff\xd8\xff' + b'\x00' * 100)  # minimal JPEG-like
    
    def tearDown(self):
        """Clean up"""
        self.sm.db.close()
        for f in Path(self.tmp_dir).glob('*'):
            f.unlink()
        os.rmdir(self.tmp_dir)
    
    # --- File signature ---
    
    def test_get_file_signature(self):
        """get_file_signature should return hash, filename, size"""
        sig = self.sm.get_file_signature(self.test_file)
        self.assertIn('file_hash', sig)
        self.assertIn('filename', sig)
        self.assertIn('file_size', sig)
        self.assertEqual(sig['filename'], 'test_image.jpg')
        self.assertEqual(sig['file_size'], 103)  # 3 + 100 bytes
        self.assertEqual(len(sig['file_hash']), 64)  # SHA-256 hex
    
    def test_get_file_signature_deterministic(self):
        """Same file should always produce same hash"""
        sig1 = self.sm.get_file_signature(self.test_file)
        sig2 = self.sm.get_file_signature(self.test_file)
        self.assertEqual(sig1['file_hash'], sig2['file_hash'])
    
    # --- add_or_get_file ---
    
    def test_add_or_get_file_new(self):
        """Should add a new file and return its hash"""
        file_hash = self.sm.add_or_get_file(self.test_file)
        self.assertEqual(len(file_hash), 64)
    
    def test_add_or_get_file_existing(self):
        """Calling twice with same file should return same hash without duplicating"""
        hash1 = self.sm.add_or_get_file(self.test_file)
        hash2 = self.sm.add_or_get_file(self.test_file)
        self.assertEqual(hash1, hash2)
        self.assertEqual(self.sm.db.count_files(), 1)
    
    # --- Processing status ---
    
    def test_update_processing_status(self):
        """Should update processing status on a file"""
        file_hash = self.sm.add_or_get_file(self.test_file)
        self.sm.update_processing_status(file_hash, 'processing')
        
        record = self.sm.get_file_info(file_hash)
        self.assertEqual(record.processing_status, 'processing')
    
    def test_update_processing_status_failed_increments_retry(self):
        """Setting status to 'failed' should increment retry_count"""
        file_hash = self.sm.add_or_get_file(self.test_file)
        self.sm.update_processing_status(file_hash, 'failed', 'some error')
        
        record = self.sm.get_file_info(file_hash)
        self.assertEqual(record.retry_count, 1)
        self.assertEqual(record.error_message, 'some error')
    
    # --- Upload status ---
    
    def test_mark_as_uploaded(self):
        """mark_as_uploaded should set upload_status and uploaded_at"""
        file_hash = self.sm.add_or_get_file(self.test_file)
        self.sm.mark_as_uploaded(file_hash, 'sftp')
        
        record = self.sm.get_file_info(file_hash)
        self.assertEqual(record.upload_status, 'uploaded')
        self.assertEqual(record.upload_target, 'sftp')
        self.assertIsNotNone(record.uploaded_at)
    
    def test_mark_upload_failed(self):
        """mark_upload_failed should set status to failed"""
        file_hash = self.sm.add_or_get_file(self.test_file)
        self.sm.mark_upload_failed(file_hash, 'Timeout')
        
        record = self.sm.get_file_info(file_hash)
        self.assertEqual(record.upload_status, 'failed')
        self.assertEqual(record.error_message, 'Timeout')
    
    def test_is_file_already_uploaded_false(self):
        """New file should not be marked as uploaded"""
        self.sm.add_or_get_file(self.test_file)
        self.assertFalse(self.sm.is_file_already_uploaded(self.test_file))
    
    def test_is_file_already_uploaded_true(self):
        """After marking as uploaded, should return True"""
        file_hash = self.sm.add_or_get_file(self.test_file)
        self.sm.mark_as_uploaded(file_hash)
        self.assertTrue(self.sm.is_file_already_uploaded(self.test_file))
    
    # --- Metadata ---
    
    def test_update_metadata(self):
        """update_metadata should set title, description, keywords"""
        file_hash = self.sm.add_or_get_file(self.test_file)
        self.sm.update_metadata(file_hash, 'Title', 'Description', ['kw1', 'kw2'])
        
        record = self.sm.get_file_info(file_hash)
        self.assertTrue(record.metadata_generated)
        self.assertEqual(record.metadata_title, 'Title')
        self.assertEqual(record.metadata_description, 'Description')
        self.assertEqual(record.get_keywords_list(), ['kw1', 'kw2'])
    
    # --- Statistics ---
    
    def test_get_upload_statistics(self):
        """Should return correct statistics"""
        file_hash = self.sm.add_or_get_file(self.test_file)
        stats = self.sm.get_upload_statistics()
        
        self.assertEqual(stats['total_files'], 1)
        self.assertEqual(stats['pending_files'], 1)
        self.assertEqual(stats['uploaded_files'], 0)
    
    # --- retry_failed_uploads ---
    
    def test_retry_failed_uploads_returns_failed(self):
        """Should return files with upload_status = failed"""
        file_hash = self.sm.add_or_get_file(self.test_file)
        self.sm.mark_upload_failed(file_hash, 'Error')
        
        failed = self.sm.retry_failed_uploads()
        self.assertEqual(len(failed), 1)
        self.assertEqual(failed[0].file_hash, file_hash)
    
    # --- cleanup_old_logs ---
    
    def test_cleanup_old_logs(self):
        """cleanup_old_logs should run without errors"""
        file_hash = self.sm.add_or_get_file(self.test_file)
        self.sm.update_processing_status(file_hash, 'completed')
        # Should not raise
        self.sm.cleanup_old_logs(days=0)


if __name__ == '__main__':
    unittest.main()
