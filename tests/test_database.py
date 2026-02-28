"""
Unit tests for DatabaseManager
"""
import os
import sys
import sqlite3
import tempfile
import unittest
from pathlib import Path
from datetime import datetime

# Add project root to path
ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from lib.state.database import DatabaseManager
from lib.state.models import FileRecord, ProcessingLog


class TestDatabaseManager(unittest.TestCase):
    """Tests for DatabaseManager"""
    
    def setUp(self):
        """Create a temporary database for each test"""
        self.tmp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.tmp_dir, 'test_state.db')
        self.db = DatabaseManager(self.db_path)
    
    def tearDown(self):
        """Clean up temporary database"""
        self.db.close()
        if os.path.exists(self.db_path):
            os.remove(self.db_path)
        os.rmdir(self.tmp_dir)
    
    def _make_record(self, file_hash='abc123', filename='test.jpg') -> FileRecord:
        return FileRecord(
            file_hash=file_hash,
            filename=filename,
            file_size=1024,
            last_modified=datetime.now(),
            created_at=datetime.now(),
            updated_at=datetime.now(),
        )
    
    # --- Init ---
    
    def test_init_creates_tables(self):
        """Database init should create files and processing_logs tables"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = {row[0] for row in cursor.fetchall()}
        conn.close()
        self.assertIn('files', tables)
        self.assertIn('processing_logs', tables)
    
    def test_wal_mode_enabled(self):
        """WAL journal mode should be enabled for concurrent access"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.execute("PRAGMA journal_mode")
        mode = cursor.fetchone()[0]
        conn.close()
        self.assertEqual(mode, 'wal')
    
    # --- add_file ---
    
    def test_add_file_returns_id(self):
        """add_file should return an integer row ID"""
        record = self._make_record()
        file_id = self.db.add_file(record)
        self.assertIsInstance(file_id, int)
        self.assertGreater(file_id, 0)
    
    def test_add_file_increments_id(self):
        """Successive inserts should get increasing IDs"""
        id1 = self.db.add_file(self._make_record('hash1', 'a.jpg'))
        id2 = self.db.add_file(self._make_record('hash2', 'b.jpg'))
        self.assertEqual(id2, id1 + 1)
    
    # --- get_file_by_hash ---
    
    def test_get_file_by_hash_found(self):
        """Should return the correct FileRecord when hash exists"""
        self.db.add_file(self._make_record('myhash', 'photo.jpg'))
        result = self.db.get_file_by_hash('myhash')
        self.assertIsNotNone(result)
        self.assertEqual(result.filename, 'photo.jpg')
        self.assertEqual(result.file_hash, 'myhash')
    
    def test_get_file_by_hash_not_found(self):
        """Should return None when hash does not exist"""
        result = self.db.get_file_by_hash('nonexistent')
        self.assertIsNone(result)
    
    # --- update_file ---
    
    def test_update_file(self):
        """update_file should persist changes"""
        self.db.add_file(self._make_record('h1', 'old.jpg'))
        record = self.db.get_file_by_hash('h1')
        record.processing_status = 'completed'
        record.filename = 'new.jpg'
        self.db.update_file(record)
        
        updated = self.db.get_file_by_hash('h1')
        self.assertEqual(updated.processing_status, 'completed')
        self.assertEqual(updated.filename, 'new.jpg')
    
    # --- get_files_by_status ---
    
    def test_get_files_by_processing_status(self):
        """Should filter by processing_status"""
        r1 = self._make_record('h1', 'a.jpg')
        r1.processing_status = 'completed'
        r2 = self._make_record('h2', 'b.jpg')
        r2.processing_status = 'pending'
        self.db.add_file(r1)
        self.db.add_file(r2)
        
        completed = self.db.get_files_by_status(processing_status='completed')
        self.assertEqual(len(completed), 1)
        self.assertEqual(completed[0].filename, 'a.jpg')
    
    def test_get_files_by_upload_status(self):
        """Should filter by upload_status"""
        r1 = self._make_record('h1', 'a.jpg')
        r1.upload_status = 'uploaded'
        r2 = self._make_record('h2', 'b.jpg')
        r2.upload_status = 'not_uploaded'
        self.db.add_file(r1)
        self.db.add_file(r2)
        
        uploaded = self.db.get_files_by_status(upload_status='uploaded')
        self.assertEqual(len(uploaded), 1)
        self.assertEqual(uploaded[0].filename, 'a.jpg')
    
    # --- count methods ---
    
    def test_count_files(self):
        """count_files should return total number of records"""
        self.assertEqual(self.db.count_files(), 0)
        self.db.add_file(self._make_record('h1'))
        self.db.add_file(self._make_record('h2'))
        self.assertEqual(self.db.count_files(), 2)
    
    def test_count_files_by_upload_status(self):
        """Should count files with a specific upload_status"""
        r1 = self._make_record('h1')
        r1.upload_status = 'uploaded'
        r2 = self._make_record('h2')
        r2.upload_status = 'not_uploaded'
        self.db.add_file(r1)
        self.db.add_file(r2)
        
        self.assertEqual(self.db.count_files_by_upload_status('uploaded'), 1)
        self.assertEqual(self.db.count_files_by_upload_status('not_uploaded'), 1)
        self.assertEqual(self.db.count_files_by_upload_status('failed'), 0)
    
    # --- processing logs ---
    
    def test_add_and_get_processing_log(self):
        """Should add and retrieve processing logs"""
        self.db.add_file(self._make_record('h1'))
        log = ProcessingLog(
            file_hash='h1',
            step='processing',
            status='completed',
            timestamp=datetime.now()
        )
        log_id = self.db.add_processing_log(log)
        self.assertIsInstance(log_id, int)
        
        logs = self.db.get_processing_logs('h1')
        self.assertEqual(len(logs), 1)
        self.assertEqual(logs[0].step, 'processing')
        self.assertEqual(logs[0].status, 'completed')
    
    # --- get_all_files ---
    
    def test_get_all_files(self):
        """get_all_files should return all records"""
        self.db.add_file(self._make_record('h1', 'a.jpg'))
        self.db.add_file(self._make_record('h2', 'b.jpg'))
        
        all_files = self.db.get_all_files()
        self.assertEqual(len(all_files), 2)
    
    # --- thread safety ---
    
    def test_close_and_reopen(self):
        """close() should gracefully close connection"""
        self.db.add_file(self._make_record('h1'))
        self.db.close()
        
        # Reopen
        self.db = DatabaseManager(self.db_path)
        result = self.db.get_file_by_hash('h1')
        self.assertIsNotNone(result)


if __name__ == '__main__':
    unittest.main()
