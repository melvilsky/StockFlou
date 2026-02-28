"""
Unit tests for FileRecord and ProcessingLog models
"""
import sys
import json
import unittest
from pathlib import Path
from datetime import datetime

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from lib.state.models import FileRecord, ProcessingLog


class TestFileRecord(unittest.TestCase):
    """Tests for FileRecord dataclass"""
    
    def test_default_values(self):
        """Default field values should match expected defaults"""
        record = FileRecord()
        self.assertEqual(record.processing_status, 'pending')
        self.assertEqual(record.upload_status, 'not_uploaded')
        self.assertFalse(record.metadata_generated)
        self.assertEqual(record.retry_count, 0)
        self.assertEqual(record.file_hash, '')
    
    def test_to_dict(self):
        """to_dict should produce a serializable dictionary"""
        now = datetime(2025, 1, 15, 12, 0, 0)
        record = FileRecord(
            id=1,
            file_hash='abc123',
            filename='test.jpg',
            file_size=2048,
            last_modified=now,
            created_at=now,
            updated_at=now,
        )
        d = record.to_dict()
        
        self.assertEqual(d['id'], 1)
        self.assertEqual(d['file_hash'], 'abc123')
        self.assertEqual(d['filename'], 'test.jpg')
        self.assertEqual(d['file_size'], 2048)
        self.assertEqual(d['last_modified'], '2025-01-15T12:00:00')
        # Verify it's JSON-serializable
        json_str = json.dumps(d)
        self.assertIsInstance(json_str, str)
    
    def test_from_dict(self):
        """from_dict should recreate a FileRecord from a dictionary"""
        data = {
            'id': 5,
            'file_hash': 'xyz789',
            'filename': 'photo.png',
            'file_size': 4096,
            'last_modified': '2025-06-01T10:30:00',
            'processing_status': 'completed',
            'upload_status': 'uploaded',
            'metadata_generated': True,
            'metadata_title': 'Test Title',
            'metadata_description': 'A description',
            'metadata_keywords': '["kw1", "kw2"]',
            'uploaded_at': '2025-06-01T11:00:00',
            'upload_target': 'sftp',
            'created_at': '2025-06-01T10:00:00',
            'updated_at': '2025-06-01T11:00:00',
            'error_message': None,
            'retry_count': 2,
        }
        record = FileRecord.from_dict(data)
        
        self.assertEqual(record.id, 5)
        self.assertEqual(record.file_hash, 'xyz789')
        self.assertEqual(record.processing_status, 'completed')
        self.assertEqual(record.upload_status, 'uploaded')
        self.assertEqual(record.retry_count, 2)
        self.assertIsInstance(record.last_modified, datetime)
    
    def test_roundtrip_to_from_dict(self):
        """to_dict -> from_dict should preserve data"""
        now = datetime(2025, 3, 10, 8, 0, 0)
        original = FileRecord(
            id=10,
            file_hash='roundtrip',
            filename='test.jpg',
            file_size=1000,
            last_modified=now,
            processing_status='completed',
            upload_status='uploaded',
            created_at=now,
            updated_at=now,
        )
        restored = FileRecord.from_dict(original.to_dict())
        self.assertEqual(original.file_hash, restored.file_hash)
        self.assertEqual(original.filename, restored.filename)
        self.assertEqual(original.processing_status, restored.processing_status)
    
    def test_get_keywords_list_empty(self):
        """get_keywords_list should return [] when no keywords set"""
        record = FileRecord()
        self.assertEqual(record.get_keywords_list(), [])
    
    def test_get_keywords_list_with_data(self):
        """get_keywords_list should parse JSON string"""
        record = FileRecord(metadata_keywords='["nature", "landscape", "sky"]')
        keywords = record.get_keywords_list()
        self.assertEqual(keywords, ['nature', 'landscape', 'sky'])
    
    def test_get_keywords_list_invalid_json(self):
        """get_keywords_list should return [] on invalid JSON"""
        record = FileRecord(metadata_keywords='not json')
        self.assertEqual(record.get_keywords_list(), [])
    
    def test_set_keywords_list(self):
        """set_keywords_list should store as JSON string"""
        record = FileRecord()
        record.set_keywords_list(['cat', 'dog', 'bird'])
        self.assertIsInstance(record.metadata_keywords, str)
        parsed = json.loads(record.metadata_keywords)
        self.assertEqual(parsed, ['cat', 'dog', 'bird'])
    
    def test_set_and_get_keywords_roundtrip(self):
        """Keywords roundtrip: set -> get should preserve order and content"""
        record = FileRecord()
        keywords = ['alpha', 'beta', 'gamma']
        record.set_keywords_list(keywords)
        result = record.get_keywords_list()
        self.assertEqual(result, keywords)


class TestProcessingLog(unittest.TestCase):
    """Tests for ProcessingLog dataclass"""
    
    def test_default_values(self):
        """Default values should be empty/None"""
        log = ProcessingLog()
        self.assertIsNone(log.id)
        self.assertEqual(log.file_hash, '')
        self.assertEqual(log.step, '')
        self.assertEqual(log.status, '')
        self.assertIsNone(log.error_message)
    
    def test_to_dict(self):
        """to_dict should produce correct dictionary"""
        now = datetime(2025, 2, 1, 9, 0, 0)
        log = ProcessingLog(
            id=1,
            file_hash='abc',
            step='processing',
            status='completed',
            timestamp=now
        )
        d = log.to_dict()
        self.assertEqual(d['step'], 'processing')
        self.assertEqual(d['status'], 'completed')
        self.assertEqual(d['timestamp'], '2025-02-01T09:00:00')
    
    def test_from_dict(self):
        """from_dict should recreate a ProcessingLog"""
        data = {
            'id': 3,
            'file_hash': 'xyz',
            'step': 'upload',
            'status': 'failed',
            'error_message': 'Connection timeout',
            'timestamp': '2025-05-20T14:30:00'
        }
        log = ProcessingLog.from_dict(data)
        self.assertEqual(log.step, 'upload')
        self.assertEqual(log.status, 'failed')
        self.assertEqual(log.error_message, 'Connection timeout')
        self.assertIsInstance(log.timestamp, datetime)


if __name__ == '__main__':
    unittest.main()
