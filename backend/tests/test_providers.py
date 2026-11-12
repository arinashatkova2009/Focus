import os,sys,unittest
from unittest.mock import patch
sys.path.insert(0,os.path.dirname(os.path.dirname(__file__)))
import providers,security,app
class ProviderTests(unittest.TestCase):
 def test_local_request(self):
  with patch.dict(os.environ,{'OLLAMA_URL':'http://127.0.0.1:11434','OLLAMA_MODEL':'test-model'}):
   with patch('providers.post',return_value={'response':'Готово'}) as req:
    self.assertEqual(providers.generate('ollama','проверка','данные'),'Готово');self.assertTrue(req.call_args.args[0].endswith('/api/generate'));self.assertEqual(req.call_args.args[2]['model'],'test-model')
 def test_remote_ollama_url_blocked(self):
  for url in ('http://localhost:11434@evil.example','http://127.0.0.1:11434/evil','https://127.0.0.1:11434','http://evil.example:11434'):
   with patch.dict(os.environ,{'OLLAMA_URL':url}):
    with patch('providers.post') as post:
     with self.assertRaises(providers.ProviderError):providers.generate('ollama','test')
     post.assert_not_called()
 def test_cloud_adapters_without_real_network(self):
  env={'EXTERNAL_DEMO_ONLY':'1','EXTERNAL_NO_TRAINING_CONFIRMED':'1','EXTERNAL_NO_CONTENT_STORAGE_CONFIRMED':'1','OPENAI_API_KEY':'test','ANTHROPIC_API_KEY':'test'}
  with patch.dict(os.environ,env):
   with patch('providers.post',return_value={'choices':[{'message':{'content':'ok'}}]}) as req:
    self.assertEqual(providers.generate('openai','проверка'),'ok');self.assertIn('api.openai.com',req.call_args.args[0])
   with patch('providers.post',return_value={'content':[{'type':'text','text':'ok'}]}) as req:
    self.assertEqual(providers.generate('anthropic','проверка'),'ok');self.assertIn('api.anthropic.com',req.call_args.args[0])
 def test_routing_provider_and_redaction(self):
  with patch.dict(os.environ,{'FOCUS_AGENT_EVA_PROVIDER':'anthropic'}):self.assertEqual(app.selected_provider('eva',{}),'anthropic')
  self.assertEqual(security.redact('deadline 2026-12-01'), 'deadline 2026-12-01');self.assertNotIn('a@example.com',security.redact('a@example.com'))
 def test_openai_json_planner_and_no_response_storage(self):
  with patch.dict(os.environ,{'FOCUS_ALLOW_EXTERNAL':'1','OPENAI_API_KEY':'test-key'}):
   with patch('providers.post',return_value={'choices':[{'message':{'content':'{"answer":"ok"}'}}]}) as request:
    providers.generate('openai','Верни строго один JSON-объект без markdown')
    payload=request.call_args.args[2]
    self.assertEqual(payload['response_format'],{'type':'json_object'})
    self.assertFalse(payload['store']);self.assertEqual(payload['model'],'gpt-4.1-mini')
 def test_empty_credit_balance_has_explicit_message(self):
  import io,json,urllib.error
  error=urllib.error.HTTPError('https://api.openai.com/v1/chat/completions',429,'limit',{},io.BytesIO(json.dumps({'error':{'type':'insufficient_quota','code':'credit_balance_exhausted'}}).encode()))
  with patch('urllib.request.build_opener') as opener:
   opener.return_value.open.side_effect=error
   with self.assertRaisesRegex(providers.ProviderError,'Баланс API OpenAI исчерпан'):
    providers.post('https://api.openai.com/v1/chat/completions',{}, {})
if __name__=='__main__':unittest.main(verbosity=2)
