"""离线验证认证重试、语言优先级，以及 Terminal 后备的一致性。"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]
HELPER = SOURCE / 'YouTube 字幕总结/Resources/SubtitleExtractor.sh'

FAKE = '''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
cookies = '--cookies-from-browser' in args or '--cookies' in args
metadata = '--dump-single-json' in args
with open(os.environ['TEST_CALLS'], 'a') as log:
    log.write(json.dumps({'metadata': metadata, 'cookies': cookies, 'browser_access': '--cookies-from-browser' in args}) + '\\n')
mode = os.environ['TEST_MODE']
if (mode in ('auth', 'denied') and metadata and not cookies) or (mode == 'subtitle_auth' and not metadata and not cookies):
    print('partial response')
    print('ERROR: Sign in to confirm you are not a bot', file=sys.stderr)
    sys.exit(1)
if mode == 'denied' and cookies:
    print('ERROR: Safari Cookie access denied', file=sys.stderr)
    sys.exit(1)
if mode == 'network':
    print('ERROR: Connection timed out', file=sys.stderr)
    sys.exit(1)
if metadata:
    print(json.dumps({'automatic_captions': {'ar-orig': [{'name': 'Arabic (Original)'}], 'en-orig': [{'name': 'English (Original)'}]}}))
else:
    assert args[args.index('--sub-langs')+1] == '^en\\-orig$'
    pattern = args[args.index('-o')+1]
    Path(pattern.replace('%(ext)s','en-orig.json3')).write_text(json.dumps({'events':[{'segs':[{'utf8':'English transcript.'}]}]}))
'''

class SubtitleFlowTests(unittest.TestCase):
    def run_flow(self, mode, forwarded=False, legacy=True):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            fake = root / 'yt-dlp'
            fake.write_text(FAKE)
            fake.chmod(0o700)
            script = root / 'helper.sh'
            script.write_text(HELPER.read_text().replace('YTDLP="$(command -v yt-dlp)"', 'YTDLP=' + repr(str(fake))))
            calls = root / 'calls.jsonl'
            result_path = root / 'transcript.txt'
            env = os.environ | {'TEST_MODE': mode, 'TEST_CALLS': str(calls), 'YTSUB_ALLOW_SAFARI_COOKIE_FALLBACK': '1' if legacy else '0'}
            cookie_path = root / 'cookies.txt'
            cookie_path.write_text('# Netscape HTTP Cookie File\n')
            args = ['/bin/zsh',str(script),'https://www.youtube.com/watch?v=test',str(result_path)]
            if forwarded: args.append(str(cookie_path))
            result = subprocess.run(args,env=env,capture_output=True,text=True,timeout=10)
            transcript = result_path.read_text() if result_path.exists() else None
            return result, [json.loads(line) for line in calls.read_text().splitlines()], transcript

    def test_forwarded_login_avoids_protected_safari_directory(self):
        result, calls, transcript = self.run_flow('auth', forwarded=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(call['cookies'] for call in calls))
        self.assertFalse(any(call['browser_access'] for call in calls))
        self.assertIsNotNone(transcript)

    def test_ungranted_login_does_not_read_browser_database(self):
        result, calls, _ = self.run_flow('auth', legacy=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)
        self.assertFalse(calls[0]['browser_access'])

    def test_anonymous_success_avoids_cookie_access(self):
        result, calls, transcript = self.run_flow('success')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c['cookies'] for c in calls], [False,False])
        self.assertEqual(transcript, 'English transcript.\n')

    def test_auth_retry_cleans_partial_output_and_keeps_login_for_download(self):
        result,calls,transcript = self.run_flow('auth')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual([c['cookies'] for c in calls], [False,True,True])
        self.assertIsNotNone(transcript)

    def test_subtitle_auth_retry(self):
        result,calls,_ = self.run_flow('subtitle_auth')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual([c['cookies'] for c in calls], [False,False,True])

    def test_cookie_access_failure_stops_after_one_retry(self):
        result,calls,_ = self.run_flow('denied')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(len(calls),2)
        self.assertIn('Safari Cookie access denied',result.stderr)

    def test_network_error_does_not_read_cookies(self):
        result,calls,_ = self.run_flow('network')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(len(calls),1)
        self.assertFalse(calls[0]['cookies'])

    def test_language_priority_excludes_translated_auto_tracks(self):
        helper=HELPER.read_text()
        def selector(text):
            return text.split('# SELECTOR_PY_START\n',1)[1].split('# SELECTOR_PY_END',1)[0]
        fixtures=[
            ({'subtitles':{'ar':[{}],'en':[{}]}},'en'),
            ({'automatic_captions':{'ar-orig':[{}],'en-orig':[{}]}},'en-orig'),
            ({'subtitles':{'zh-Hans':[{}]}},'zh-Hans'),
            ({'automatic_captions':{'en':[{'url':'https://example.test/?lang=ar&tlang=en'}],'fa-orig':[{}]}},'fa-orig'),
        ]
        for data,expected in fixtures:
            with self.subTest(expected=expected), tempfile.TemporaryDirectory() as folder:
                root=Path(folder)
                metadata=root/'metadata.json'
                metadata.write_text(json.dumps(data))
                result=subprocess.run(['/usr/bin/python3','-',str(metadata),str(root)],input=selector(helper),text=True,capture_output=True)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual((root/'selected-code.txt').read_text(),expected)

if __name__ == '__main__':
    unittest.main()
