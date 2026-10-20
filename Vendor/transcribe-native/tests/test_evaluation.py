import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from evaluate import membership,verify_dataset,edit_metrics,normalizers
class EvaluationTests(unittest.TestCase):
    def test_full_corpus_membership(self):
        membership([{'sample_id':'a'},{'sample_id':'b'}],['a','b'])
        for rows in [[{'sample_id':'a'}],[{'sample_id':'a'},{'sample_id':'a'}],[{'sample_id':'a'},{'sample_id':'b'},{'sample_id':'extra'}]]:
            with self.assertRaises(ValueError): membership(rows,['a','b'])
    def test_bad_snapshot_digest(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'dataset.json';path.write_text(json.dumps({'entries':[]}))
            with self.assertRaises(ValueError):verify_dataset(path,'bad',False)
    def test_edit_counts_and_alignments(self):
        m=edit_metrics('one two','one three four',lambda x:x)
        self.assertEqual(m['word']['edits'],2)
        self.assertEqual(m['word']['denominator'],2)
        self.assertTrue(m['word']['alignments'])
    def test_frozen_protocols(self):
        n=normalizers();self.assertEqual(set(n),{'base','aliases','hesitation_base','hesitation_aliases'})
        self.assertEqual(n['base']('Ёж, 21!'),'еж двадцать один')
        self.assertEqual(n['aliases']('Jira GPT ML'),n['aliases']('жира джипити эмэлем'))
        self.assertEqual(n['hesitation_base']('one эээ two'),'one two')
        self.assertNotEqual(n['aliases']('ML'),n['aliases']('email'))
if __name__=='__main__':unittest.main()

class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.entries=[{'id':'a','reference':'one two'}]
        self.calls=[{'sample_id':'a','repeat':i,'text':'one two','status':0,'native_wall_s':.1} for i in range(3)]
        self.oracle=[{'sample_id':'a','text':'one two'}]
        self.identity={'window_policy':'stock25-v1','role':'native-F16','model_sha256':'native'}
        self.reference={'window_policy':'stock25-v1','role':'matched-window-F32-oracle','model_sha256':'reference'}
    def test_candidate_failures_remain_unaccepted(self):
        from evaluate import evaluate
        passed=evaluate(self.entries,self.calls,self.oracle,self.calls,self.identity,self.reference)
        self.assertTrue(passed['accepted'])
        changed=[{**r,'text':'one three'} for r in self.calls]
        failed=evaluate(self.entries,changed,self.oracle,self.calls,self.identity,self.reference)
        self.assertFalse(failed['accepted'])
        self.assertEqual(len(failed['failures']),2)
    def test_reference_and_precision_identity_are_distinct(self):
        from evaluate import evaluate
        with self.assertRaises(ValueError):
            evaluate(self.entries,self.calls,self.oracle,self.calls,self.identity,{**self.reference,'model_sha256':'native'})

class QuantizationAcceptanceTests(unittest.TestCase):
    def test_local_or_any_protocol_regression_blocks_q8(self):
        from copy import deepcopy
        from evaluate import quantized_nonregression
        baseline={'recordings':[{'sample_id':'a','protocols':{'base':{'word':{'edits':1},'character':{'edits':2}}}}], 'aggregate':{p:{'word':{'wer':.1},'character':{'cer':.1}} for p in normalizers()}}
        self.assertTrue(quantized_nonregression(baseline,baseline)['accepted'])
        q8=deepcopy(baseline);q8['recordings'][0]['protocols']['base']['character']['edits']=3
        self.assertFalse(quantized_nonregression(q8,baseline)['accepted'])
        q8=deepcopy(baseline);q8['aggregate']['hesitation_aliases']['word']['wer']=.11
        self.assertFalse(quantized_nonregression(q8,baseline)['accepted'])

class FrozenDigestTests(unittest.TestCase):
    def test_changed_policy_is_rejected(self):
        from evaluate import verify_policy_digests
        root=Path(__file__).resolve().parents[1]
        pins=json.loads((root/'pins.json').read_text())
        verify_policy_digests(pins)
        pins['evaluation_inputs']['aliases_sha256']='bad'
        with self.assertRaises(ValueError):verify_policy_digests(pins)
