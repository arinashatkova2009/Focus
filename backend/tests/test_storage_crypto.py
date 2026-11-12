import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from contextlib import closing
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import security
import storage_crypto
import store


@unittest.skipUnless(os.name == 'nt', 'Windows DPAPI')
class StorageCryptoTests(unittest.TestCase):
    def test_metadata_cannot_trigger_ciphertext_decoding(self):
        with sqlite3.connect(':memory:') as db:
            db.row_factory=store.protected_row
            literal='focus-dpapi-v1:not-a-ciphertext'
            row=db.execute('SELECT ? AS name, ? AS data',(literal,storage_crypto.seal('private'))).fetchone()
            self.assertEqual(row['name'],literal)
            self.assertEqual(row['data'],'private')

    def test_private_audit_key_and_legacy_chain_migration(self):
        import hashlib
        import hmac
        with tempfile.TemporaryDirectory() as folder, patch.object(store,'DB_PATH',str(Path(folder)/'audit.db')):
            store.init()
            ts=store.now()
            content=json.dumps([ts,None,'legacy','','ok','','GENESIS'],ensure_ascii=False,separators=(',',':'))
            digest=hmac.new(b'demo-only-change-me',content.encode(),hashlib.sha256).hexdigest()
            with closing(store.connect()) as db, db:
                db.execute('INSERT INTO audit(at,actor_id,action,object_ref,result,detail,previous_hash,hash) VALUES (?,?,?,?,?,?,?,?)',(ts,None,'legacy','','ok','','GENESIS',digest))
                store.audit(db,None,'new-entry')
                self.assertTrue(store.audit_verify(db))
            with closing(sqlite3.connect(store.DB_PATH)) as raw:
                key=raw.execute("SELECT value FROM settings WHERE key='audit_key_v1'").fetchone()[0]
                self.assertTrue(key.startswith(storage_crypto.PREFIX))
            with closing(store.connect()) as db:
                self.assertTrue(store.audit_verify(db))

    def test_authenticated_roundtrip_and_tampering(self):
        original = 'Личный документ: секретное содержимое 934857'
        first = storage_crypto.seal(original)
        self.assertNotIn(original, first)
        self.assertEqual(storage_crypto.unseal(first), original)
        self.assertNotEqual(first, storage_crypto.seal(original))
        damaged = first[:-8] + 'AAAAAAAA'
        with self.assertRaises(storage_crypto.StorageProtectionError):
            storage_crypto.unseal(damaged)

    def test_roundtrip_after_process_restart(self):
        token = storage_crypto.seal('retained after restart')
        code = 'from storage_crypto import unseal;import sys;print(unseal(sys.argv[1]))'
        result = subprocess.run([sys.executable, '-X', 'utf8', '-c', code, token],
                                cwd=Path(store.__file__).parent, capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout.strip(), 'retained after restart')

    def test_legacy_migration_is_idempotent_and_readable(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(store, 'DB_PATH', str(Path(folder) / 'test.db')):
            store.seed()
            plain = json.dumps({'text': 'PRIVATE-MIGRATION-SENTINEL'})
            with closing(sqlite3.connect(store.DB_PATH)) as raw, raw:
                raw.execute('UPDATE objects SET data=? WHERE id=1', (plain,))
            store.init()
            with closing(sqlite3.connect(store.DB_PATH)) as raw:
                first = raw.execute('SELECT data FROM objects WHERE id=1').fetchone()[0]
            self.assertTrue(first.startswith(storage_crypto.PREFIX))
            self.assertNotIn('PRIVATE-MIGRATION-SENTINEL', Path(store.DB_PATH).read_bytes().decode('latin1'))
            store.init()
            with closing(sqlite3.connect(store.DB_PATH)) as raw:
                self.assertEqual(first, raw.execute('SELECT data FROM objects WHERE id=1').fetchone()[0])
            with closing(store.connect()) as db:
                self.assertEqual(json.loads(db.execute('SELECT data FROM objects WHERE id=1').fetchone()['data']), json.loads(plain))


class PrivacyBoundaryTests(unittest.TestCase):
    def test_credentials_are_masked_without_breaking_normal_dates(self):
        safe = security.model_safe_text('password=supersecret123 email@example.com deadline 2026-12-01')
        self.assertNotIn('supersecret123', safe)
        self.assertNotIn('email@example.com', safe)
        self.assertIn('2026-12-01', safe)

    def test_provider_is_not_called_if_privacy_boundary_rejects_text(self):
        import providers
        with patch('providers.model_safe_text', side_effect=ValueError('blocked')), patch('providers.post') as send:
            with self.assertRaises(providers.ProviderError):
                providers.generate('ollama', 'test')
            send.assert_not_called()
