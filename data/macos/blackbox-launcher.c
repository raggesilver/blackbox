#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libgen.h>

// Resolve symlinks and return the real path of the executable.
// Caller must free() the result.
static char* real_exe_path(const char* argv0) {
  char* resolved = realpath(argv0, NULL);
  return resolved ? resolved : strdup(argv0);
}

// Set G_RESOURCE_OVERLAYS so the Adwaita CSS compat layer is active.
// When running from inside a .app bundle, the overlay lives at
// Contents/Resources/gtk-css-compat relative to the executable.
static void setup_adwaita_compat(const char* exe_path) {
  char* path_copy = strdup(exe_path);
  // exe_path is .../Contents/MacOS/BlackBox — go up two levels
  const char* macos_dir = dirname(path_copy);
  char contents_dir[1024];
  snprintf(contents_dir, sizeof(contents_dir), "%s/..", macos_dir);
  free(path_copy);

  char overlay_dir[1024];
  snprintf(overlay_dir, sizeof(overlay_dir), "%s/Resources/gtk-css-compat",
           contents_dir);

  if (access(overlay_dir, F_OK) == 0) {
    char overlay[2048];
    snprintf(overlay, sizeof(overlay), "/org/gnome/Adwaita=%s", overlay_dir);
    const char* existing = getenv("G_RESOURCE_OVERLAYS");
    if (existing && *existing) {
      char combined[4096];
      snprintf(combined, sizeof(combined), "%s:%s", overlay, existing);
      setenv("G_RESOURCE_OVERLAYS", combined, 1);
    } else {
      setenv("G_RESOURCE_OVERLAYS", overlay, 1);
    }
  }
}

int main(int argc, char* argv[]) {
  char* exe = real_exe_path(argv[0]);
  setup_adwaita_compat(exe);
  free(exe);

  const char* prefixes[] = { "/opt/homebrew", "/usr/local", NULL };

  for (int i = 0; prefixes[i] != NULL; i++) {
    char binary[1024];
    snprintf(binary, sizeof(binary), "%s/bin/blackbox-terminal", prefixes[i]);

    if (access(binary, X_OK) != 0) {
      continue;
    }

    if (!getenv("GSETTINGS_SCHEMA_DIR")) {
      char schema_dir[1024];
      snprintf(schema_dir, sizeof(schema_dir), "%s/share/glib-2.0/schemas",
               prefixes[i]);
      setenv("GSETTINGS_SCHEMA_DIR", schema_dir, 0);
    }

    char share_dir[1024];
    snprintf(share_dir, sizeof(share_dir), "%s/share", prefixes[i]);

    const char* existing_xdg = getenv("XDG_DATA_DIRS");
    if (existing_xdg && *existing_xdg) {
      char xdg[2048];
      snprintf(xdg, sizeof(xdg), "%s:%s", share_dir, existing_xdg);
      setenv("XDG_DATA_DIRS", xdg, 1);
    } else {
      setenv("XDG_DATA_DIRS", share_dir, 1);
    }

    const char* home = getenv("HOME");
    // Spawning the terminal from homebrew's folder causes it to open in with
    // `/` as cwd, so we need to cd into `~/` first.
    if (home) { chdir(home); }

    execv(binary, argv);
    perror("execv");
    return 1;
  }

  fprintf(stderr, "Error: blackbox-terminal not found.\n");
  fprintf(stderr, "Install Black Box with: brew install blackbox-terminal\n");
  return 1;
}
