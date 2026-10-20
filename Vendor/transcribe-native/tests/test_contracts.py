import json
from pathlib import Path
import sys
import unittest
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from convert import validate_config, transform_tensor, inverse_transform, validate_catalog
from parity import compare, collapse, window_plan, validate_policy

ROOT=Path(__file__).resolve().parents[1]

class ConversionTests(unittest.TestCase):
    def test_profile_configuration(self):
        cfg=json.loads((ROOT/'model-config.json').read_text())
        validate_config(cfg)
        for key,value in [('n_layers',16),('num_classes',70),('center',True),('source_revision','unknown')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_config({**cfg,key:value})
        with self.assertRaises(ValueError):
            validate_config({**cfg,'vocabulary':cfg['vocabulary'][::-1]})

    def test_inverse_layouts_are_exact(self):
        for name,shape in [('preprocessor.mel_filter',(5,4)),('encoder.layers.0.conv.depthwise_conv.weight',(6,5,1)),('norm',(3,))]:
            a=np.arange(np.prod(shape),dtype=np.float16).reshape(shape)
            np.testing.assert_array_equal(inverse_transform(name,transform_tensor(name,a)),a)

    def test_exact_tensor_accounting(self):
        schema=[{'source':'a','shape':[3,2]}]
        validate_catalog({'a':np.zeros((3,2))},schema)
        for sd in [{},{'b':np.zeros((3,2))},{'a':np.zeros((3,2)),'extra':np.zeros(1)},{'a':np.zeros((2,3))},{'a':np.full((3,2),np.nan)}]:
            with self.assertRaises(ValueError): validate_catalog(sd,schema)

class ParityTests(unittest.TestCase):
    def test_gates_fail_nonfinite_shape_and_local_error(self):
        self.assertTrue(compare(np.ones(8),np.ones(8),'block', 'F32')['pass'])
        for a,b in [(np.full(8,np.nan),np.ones(8)),(np.ones(7),np.ones(8)),(np.zeros(8),np.ones(8))]:
            self.assertFalse(compare(a,b,'block','F32')['pass'])
        self.assertTrue(compare(np.zeros(8),np.zeros(8),'block','F32')['pass'])
        self.assertFalse(compare(np.full(8,2e-6),np.zeros(8),'block','F32')['pass'])

    def test_frontend_elementwise_gate(self):
        self.assertFalse(compare(np.array([1.,0.001]),np.array([1.,0.]),'mel','F32')['pass'])

    def test_window_boundaries_and_exact_coverage(self):
        for frames in [1,624,625,626,627,1050,1051,2029,10000]:
            windows=window_plan(frames)
            coverage=[]
            for w in windows:
                a,b,ws,we=w
                self.assertLessEqual(we-ws,625)
                self.assertLessEqual(a-ws,50)
                self.assertLessEqual(we-b,50)
                coverage.extend(range(a,b))
            self.assertEqual(coverage,list(range(frames)))
        self.assertEqual(len(window_plan(625)),1)
        self.assertEqual(len(window_plan(626)),2)

    def test_one_collapse_across_boundaries_preserves_repetition(self):
        self.assertEqual(collapse([1,1,70,1,2,2,70,2],70),[1,1,2,2])
        self.assertEqual(collapse([1,1]+[1,1],70),[1])

    def test_policy_mismatch_is_rejected(self):
        validate_policy('stock25-v1','stock25-v1')
        with self.assertRaises(ValueError): validate_policy('whole-input-diagnostic','stock25-v1')

if __name__=='__main__': unittest.main()

class TensorIntegrityTests(unittest.TestCase):
    def test_serialized_payload_corruption_is_detected(self):
        from convert import tensor_crc32
        original=np.arange(32,dtype=np.float16)
        altered=original.copy();altered.view(np.uint8)[0]^=1
        self.assertNotEqual(tensor_crc32(original),tensor_crc32(altered))
        self.assertEqual(tensor_crc32(original),tensor_crc32(original.copy()))
