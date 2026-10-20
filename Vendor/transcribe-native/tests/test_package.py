from pathlib import Path
import json
import sys
import tempfile
import struct
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from package import files,verify
class PackageTests(unittest.TestCase):
    def test_rebuild_normalization_preserves_code_differences(self):
        from package_regression import normalized_macho
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'library'
            header=struct.pack('<8I',0xfeedfacf,0x100000c,0,6,2,40,0,0)
            uuid=struct.pack('<II',0x1b,24)+bytes(16)
            signature=struct.pack('<4I',0x1d,16,83,4)
            original=header+uuid+signature+b'codepayload'+b'sign'
            path.write_bytes(original);expected,_=normalized_macho(path)
            changed=bytearray(original);changed[40]=1;changed[-1]=0
            path.write_bytes(changed);self.assertEqual(normalized_macho(path)[0],expected)
            changed[72]^=1;path.write_bytes(changed)
            self.assertNotEqual(normalized_macho(path)[0],expected)

    def test_checksum_missing_resource_and_interface_fail_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            r=Path(temp);(r/'kernels').write_text('embedded mock');(r/'license').write_text('MIT')
            m={'schema_version':1,'interface_version':'0.4.0','target':{'deployment_target':'15.0'},'licenses':['license'],'files':files(r)}
            (r/'manifest.json').write_text(json.dumps(m));verify(r)
            (r/'extra').mkdir();(r/'extra/manifest.json').write_text('{}')
            with self.assertRaises(ValueError):verify(r)
            (r/'extra/manifest.json').unlink();(r/'extra').rmdir()
            (r/'kernels').write_text('altered')
            with self.assertRaises(ValueError):verify(r)
            (r/'kernels').unlink()
            with self.assertRaises(ValueError):verify(r)
            m['interface_version']='bad';(r/'manifest.json').write_text(json.dumps(m))
            with self.assertRaises(ValueError):verify(r)
if __name__=='__main__':unittest.main()

class UpdateGateTests(unittest.TestCase):
    def test_missing_acceptance_evidence_cannot_advance_pin(self):
        from update_gate import REQUIRED,validate,validation_inputs_sha256
        from prepare import sha256
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);(root/'license').write_text('MIT')
            manifest={'schema_version':1,'candidate':'synthetic','interface_version':'0.4.0','target':{'deployment_target':'15.0'},'licenses':['license'],'files':files(root)}
            (root/'manifest.json').write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):validate(root,{})
            report=root.parent/(root.name+'-report.json')
            try:
                reports={name:report for name in REQUIRED}
                for result in [{'pass':False,'candidate_manifest_sha256':sha256(root/'manifest.json')},{'pass':True,'candidate_manifest_sha256':'0'*64}]:
                    report.write_text(json.dumps(result))
                    with self.assertRaises(ValueError):validate(root,reports)
                report.write_text(json.dumps({'pass':True,'candidate_manifest_sha256':sha256(root/'manifest.json'),'validation_inputs_sha256':'0'*64}))
                with self.assertRaises(ValueError):validate(root,reports)
                report.write_text(json.dumps({'pass':True,'candidate_manifest_sha256':sha256(root/'manifest.json'),'validation_inputs_sha256':validation_inputs_sha256()}))
                self.assertTrue(validate(root,reports)['pass'])
            finally:report.unlink(missing_ok=True)
