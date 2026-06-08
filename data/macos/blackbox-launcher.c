#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char* argv[]) {
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
