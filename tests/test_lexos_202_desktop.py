#!/usr/bin/env python3
import os, pathlib, subprocess, tempfile, unittest, xml.etree.ElementTree as ET
R=pathlib.Path(__file__).resolve().parents[1]
C=R/'config/includes.chroot'
class Desktop202(unittest.TestCase):
    def test_trash_and_bindings(self):
        x=C/'etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml'
        d=ET.parse(x/'xfce4-desktop.xml')
        self.assertEqual(d.find(".//property[@name='show-trash']").get('value'),'true')
        keys=ET.parse(x/'xfce4-keyboard-shortcuts.xml')
        for direction,action in [('Left','tile_left_key'),('Right','tile_right_key')]:
            key='<Super><Primary>'+direction
            matches=keys.findall("./property[@name='xfwm4']/property[@name='custom']/property")
            self.assertEqual([m.get('value') for m in matches if m.get('name')==key],[action])
            commands=keys.findall("./property[@name='commands']/property[@name='custom']/property")
            self.assertFalse(any(m.get('name')==key for m in commands))
    def test_unpin_uri_and_copies(self):
        with tempfile.TemporaryDirectory() as td:
            p=pathlib.Path(td); apps=p/'apps'; apps.mkdir(); docks=p/'launchers'; docks.mkdir()
            (apps/'lexos-pro.desktop').write_text('[Desktop Entry]\n')
            for n,uri in enumerate(['file:/usr/share/applications/lexos-pro.desktop','file:///home/lex/Bureau/lexos-pro.desktop','file:///home/lex/Bureau/lexos%2Dpro.desktop','application://lexos-pro.desktop']):
                (docks/f'{n}.dockitem').write_text('[PlankDockItemPreferences]\nLauncher='+uri+'\n')
            other=docks/'other.dockitem'; other.write_text('Launcher=file:///usr/share/applications/lexos-pro-terminal.desktop\n')
            before=other.read_bytes()
            env=dict(os.environ,LEXOS_PLANK=str(docks),LEXOS_APPS_DIRS=str(apps))
            cmd=['bash',str(C/'usr/bin/lexos-epingler'),'--enlever',str(apps/'lexos-pro.desktop')]
            subprocess.run(cmd,env=env,check=True,stdout=subprocess.PIPE)
            self.assertEqual(list(docks.iterdir()),[other]); self.assertEqual(other.read_bytes(),before)
            subprocess.run(cmd,env=env,check=True,stdout=subprocess.PIPE)
    def test_persistent_migration(self):
        with tempfile.TemporaryDirectory() as td:
            p=pathlib.Path(td); stub=p/'xfconf-query'; data=p/'state.json'
            stub.write_text("""#!/usr/bin/env python3
import json, os, sys, pathlib
p=pathlib.Path(os.environ['FAKE_XFCONF']); a=sys.argv[1:]; d=json.loads(p.read_text())
if '-lv' in a:
    print(d); sys.exit(0)
key=a[a.index('-p')+1]
if '-r' in a: d.pop(key,None)
elif '-s' in a: d[key]=a[a.index('-s')+1]
else:
    if key not in d: sys.exit(1)
    print(d[key]); sys.exit(0)
p.write_text(json.dumps(d))
""")
            stub.chmod(0o755)
            import json
            unrelated='/xfwm4/custom/<Alt>F4'
            data.write_text(json.dumps({'/xfwm4/custom/<Super>Left':'left_workspace_key', '/commands/custom/<Super><Primary>Right':'bad-command', unrelated:'close_window_key'}))
            env=dict(os.environ,PATH=str(p)+':'+os.environ['PATH'],XDG_STATE_HOME=str(p/'persist'),FAKE_XFCONF=str(data))
            cmd=['bash',str(C/'usr/bin/lexos-raccourcis-mosaique')]
            subprocess.run(cmd,env=env,check=True,stdout=subprocess.PIPE)
            got=json.loads(data.read_text())
            self.assertEqual(got['/xfwm4/custom/<Super>Left'],'tile_left_key')
            self.assertEqual(got['/xfwm4/custom/<Super><Primary>Right'],'tile_right_key')
            self.assertNotIn('/commands/custom/<Super><Primary>Right',got)
            self.assertEqual(got[unrelated],'close_window_key')
            before=data.read_bytes()
            subprocess.run(cmd,env=env,check=True,stdout=subprocess.PIPE)
            self.assertEqual(data.read_bytes(),before)
            self.assertEqual(len(list((p/'persist/lexos/mosaique-202').glob('avant.*'))),1)
    def test_no_default_dashboard(self):
        for p in (C/'etc/skel/.config/plank/dock1/launchers').glob('*'):
            self.assertNotIn('/lexos-pro.desktop',p.read_text())
        self.assertIn('lock-items=false',(C/'etc/dconf/db/local.d/00-lexos-dock').read_text())
        self.assertIn('[Desktop Action Unpin]',(C/'usr/share/applications/lexos-pro.desktop').read_text())
    def test_secure_boot_preserved(self):
        self.assertIn('--uefi-secure-boot enable',(R/'auto/config').read_text())
        packages=(C.parent/'package-lists/lexos-core.list.chroot').read_text()
        for pkg in ['shim-signed','grub-efi-amd64-signed','mokutil']: self.assertIn(pkg,packages)
        script=(C/'usr/share/lexos/shell/secure-boot.sh').read_text()
        self.assertNotIn('Secure Boot  ->  Disabled',script)
if __name__=='__main__': unittest.main()
