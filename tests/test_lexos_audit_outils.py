#!/usr/bin/env python3
import os, pathlib, subprocess, tempfile, unittest
R=pathlib.Path(__file__).resolve().parents[1]
HOOK=R/'config/hooks/normal/0262-lexos-audit-outils.hook.chroot'
class AuditTools(unittest.TestCase):
    def run_hook(self, flavour='pro', fail=False):
        temp=tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        p=pathlib.Path(temp.name); bin=p/'bin'; bin.mkdir(); root=p/'root'; root.mkdir()
        (root/'usr/share/lexos').mkdir(parents=True)
        (root/'usr/share/lexos/audit-tools.packages').write_text((R/'config/includes.chroot/usr/share/lexos/audit-tools.packages').read_text())
        conf=p/'build.conf'; conf.write_text('LEXOS_FLAVOUR='+flavour+'\n')
        stub=bin/'stub'
        stub.write_text('''#!/usr/bin/python3
import os, sys, pathlib
name=pathlib.Path(sys.argv[0]).name; args=sys.argv[1:]
with open(os.environ['CALLS'],'a') as f: f.write(name+' '+ ' '.join(args)+'\\n')
if name=='apt-get' and os.environ.get('FAIL')=='1': sys.exit(1)
if name=='dpkg-query':
 print('install ok installed' if args[-1]=='git' else 'not-installed'); sys.exit(0)
if name=='git':
 if args[0]=='clone':
  p=pathlib.Path(args[-1]); p.mkdir(); (p/'LICENSE').write_text('license'); (p/'johnny').write_text('#!/bin/sh\\nexit 0\\n'); (p/'johnny').chmod(0o755)
 else: print('c862833d4be43fad559d2d3866d514017d47e0c9')
if name=='ldd': print('libQt5Widgets.so => /lib/libQt5Widgets.so')
'''); stub.chmod(0o755)
        for name in ['apt-get','dpkg-query','git','qmake','make','ldconfig','ldd','john','hashcat']:
            (bin/name).symlink_to(stub)
        calls=p/'calls'; calls.touch()
        env=dict(os.environ,PATH=str(bin)+':'+os.environ['PATH'],LEXOS_AUDIT_ROOT=str(root),LEXOS_AUDIT_CONF=str(conf),CALLS=str(calls),FAIL='1' if fail else '0')
        result=subprocess.run(['bash',str(HOOK)],env=env,capture_output=True,text=True)
        return root,calls.read_text(),result
    def test_pro(self):
        root,calls,result=self.run_hook()
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('john hashcat',calls)
        self.assertIn('cuda-nvrtc-13-4 cuda-nvrtc-dev-13-4',calls)
        self.assertEqual((root/'etc/ld.so.conf.d/lexos-cuda-13-4.conf').read_text().strip(),'/usr/local/cuda-13.4/targets/x86_64-linux/lib')
        self.assertTrue((root/'usr/local/bin/johnny').is_file())
        self.assertIn('Categories=System;Security;', (root/'usr/share/applications/johnny.desktop').read_text())
        self.assertIn('source=c862833d', (root/'etc/lexos/audit-outils-report').read_text())
        purge=[l for l in calls.splitlines() if 'purge' in l][0]
        self.assertNotIn(' git',purge) # paquet déjà installé conservé
        self.assertNotIn('autoremove',calls)
    def test_manifest(self):
        names=[line.strip() for line in (R/'config/includes.chroot/usr/share/lexos/audit-tools.packages').read_text().splitlines() if line.strip() and not line.startswith('#')]
        self.assertEqual(len(names),99)
        self.assertEqual(len(set(names)),99)
        for tool in ['john','hashcat','nmap','wireshark','aircrack-ng','yara']: self.assertIn(tool,names)
        self.assertFalse(any(n.startswith('kali-') for n in names))
    def test_other_flavour(self):
        root,calls,result=self.run_hook('standard')
        self.assertEqual(result.returncode,0); self.assertEqual(calls,''); self.assertFalse((root/'etc').exists())
    def test_install_failure_fatal(self):
        root,calls,result=self.run_hook(fail=True)
        self.assertNotEqual(result.returncode,0)
        self.assertFalse((root/'etc/lexos/audit-outils-report').exists())
if __name__=='__main__': unittest.main()
