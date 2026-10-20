from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest

TOOLS=Path(__file__).resolve().parents[1]/'tools'
sys.path.insert(0,str(TOOLS))
from run import run


class WatchdogTests(unittest.TestCase):
    def test_parent_timeout_unwinds_nested_child_group(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            command=['uv','--native-tls','run','--offline','--no-project','--python','3.13',str(TOOLS/'run.py'),'--log',str(root/'child.log'),'--timeout','20','--','/bin/sleep','30']
            with self.assertRaises(subprocess.TimeoutExpired):
                run(command,root/'parent.log',5)
            child=json.loads((root/'child.process.json').read_text())
            self.assertEqual(child['exit_code'],-15)
            self.assertNotEqual(json.loads((root/'parent.process.json').read_text())['exit_code'],0)
