#  Joue les VRAIES lignes de build.sh qui portent les soupapes : la résolution
#  des drapeaux, et le gabarit qui écrit build.conf. Une construction entière
#  prendrait des minutes et demanderait root ; ces trois morceaux-là suffisent,
#  et ce sont EXACTEMENT ceux qui étaient cassés.
import subprocess, sys, tempfile, os
racine, sp, ss = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(racine + "/build.sh", encoding="utf-8").read()
try:
    i = src.index('[[ -n "$CLI_ARCH"    ]] && LEXOS_ARCH=')
    j = src.index('case "$LEXOS_FLAVOUR" in', i)
    k = src.index("cat > config/includes.chroot/etc/lexos/build.conf <<EOF")
    l = src.index("\nEOF\n", k) + len("\nEOF\n")
except ValueError:
    print("SANS_ANCRE"); raise SystemExit
d = tempfile.mkdtemp(); os.makedirs(d + "/config/includes.chroot/etc/lexos", exist_ok=True)
VARS = "\n".join(v + "=x" for v in """LEXOS_NAME LEXOS_ID LEXOS_VERSION LEXOS_CODENAME
LEXOS_TAGLINE LEXOS_HOME_URL LEXOS_BUG_URL LEXOS_TIMEZONE LEXOS_LOCALE
LEXOS_KEYBOARD_LAYOUT LEXOS_KEYBOARD_VARIANT LEXOS_BRAND LEXOS_LICENSE
LEXOS_ACCENT_NAME LEXOS_BG LEXOS_FG LEXOS_TERM_FG LEXOS_GTK_BASE_THEME
LEXOS_ICON_THEME LEXOS_CRT_EFFECTS LEXOS_DOCK_POSITION LEXOS_PERF_PROFILE
LEXOS_WIFI_AUTO_OPEN LEXOS_DISK_ENCRYPTION LEXOS_KERNEL_CHANNEL BUILD_DATE
BUILD_ID""".split())
script = ("set -u\nwarn() { :; }\nCLI_ARCH=\"\"\nLEXOS_ARCH=amd64\n"
          "LEXOS_DEBIAN_SUITE=trixie\nLEXOS_FLAVOUR=pro\n"
          "SANS_PILOTE=%s\nSANS_SECOURS=%s\n%s\ncd %s\n" % (sp, ss, VARS, d)
          + src[i:j] + "\n" + src[k:l]
          + "\nprintf 'CONF=%s ' \"$(sed -n 's/^LEXOS_NVIDIA_FACULTATIF=\"\\(.*\\)\"/\\1/p' "
            "config/includes.chroot/etc/lexos/build.conf || echo '<absente>')\""
          + "\nprintf 'ENV=%s\\n' \"$(bash -c 'printf %s \"${LEXOS_SECOURS_FACULTATIF:-<non-exporte>}\"')\"\n")
r = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
print((r.stdout or ("ERREUR " + r.stderr[:160])).strip())
