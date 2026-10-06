import datetime as dt
import unittest
from refresh_lexicon import domain, validate_proposal, stale
class RefreshTests(unittest.TestCase):
 def test_independent_sources(self):
  self.assertEqual(domain('https://news.example.co.jp/a'),'example.co.jp')
  entry=dict(term='めっちゃ',reading='めっちゃ',gloss_ja='程度が強い',register='casual',platforms=['spoken'],age_hint='要確認',example='めっちゃおいしい。',status='established',sources=['https://a.example.com/1','https://b.example.com/2'])
  self.assertIsNone(validate_proposal(entry,set(entry['sources']),dt.date(2026,10,6)))
  entry['sources'][1]='https://dictionary.example.jp/a'
  self.assertIsNone(validate_proposal(entry,set(),dt.date(2026,10,6)))
  proposed=validate_proposal(entry,set(entry['sources']),dt.date(2026,10,6))
  self.assertFalse(proposed['verified']);self.assertIsNone(proposed['last_verified'])
 def test_expiry(self):
  entries=[dict(status='established',last_verified='2024-01-01')]
  self.assertEqual(stale(entries,dt.date(2026,10,6))[0]['status'],'stale')
if __name__=='__main__':unittest.main()
