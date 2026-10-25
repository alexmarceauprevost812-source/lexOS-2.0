import sys


def main():
    if "--version" in sys.argv:
        from . import __version__
        print("REA Studio " + __version__)
        return
    try:
        from .app import main as gui
        gui()
    except ImportError as exc:
        if exc.name in ("tkinter", "_tkinter"):
            print("Tkinter manque : sudo apt install python3-tk", file=sys.stderr)
            raise SystemExit(1)
        raise


if __name__ == "__main__":
    main()
