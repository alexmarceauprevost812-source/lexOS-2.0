/* PLAY.exe — lance LexOS (clé USB-C) dans VirtualBox.
   Demande les droits administrateur (manifeste), puis exécute
   .lexos\jouer.ps1 situé à côté de ce programme, fenêtre réduite. */
#include <windows.h>
#include <wchar.h>
int WINAPI wWinMain(HINSTANCE h, HINSTANCE p, PWSTR cmd, int show) {
    wchar_t self[MAX_PATH], dir[MAX_PATH], script[MAX_PATH], args[MAX_PATH * 2];
    GetModuleFileNameW(NULL, self, MAX_PATH);
    wcscpy(dir, self);
    wchar_t *slash = wcsrchr(dir, L'\\');
    if (slash) *slash = 0;
    swprintf(script, MAX_PATH, L"%ls\\.lexos\\jouer.ps1", dir);
    if (GetFileAttributesW(script) == INVALID_FILE_ATTRIBUTES) {
        MessageBoxW(NULL, L"Le dossier .lexos est introuvable à côté de PLAY.\nRecopie le kit LexOS sur la clé.",
                    L"LexOS", MB_ICONERROR);
        return 1;
    }
    swprintf(args, MAX_PATH * 2,
             L"-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File \"%ls\"", script);
    HINSTANCE r = ShellExecuteW(NULL, L"open", L"powershell.exe", args, dir, SW_SHOWMINNOACTIVE);
    if ((INT_PTR)r <= 32) {
        MessageBoxW(NULL, L"Impossible de lancer PowerShell.", L"LexOS", MB_ICONERROR);
        return 1;
    }
    return 0;
}
