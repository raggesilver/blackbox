#include <dirent.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Returns a malloc'd string pointing to .../BlackBox.app/Contents, or NULL.
static char* get_bundle_contents_dir(void) {
  char buf[PATH_MAX];
  uint32_t size = sizeof(buf);
  if (_NSGetExecutablePath(buf, &size) != 0) return NULL;

  char* exe = realpath(buf, NULL);
  if (!exe) return NULL;

  // exe = .../BlackBox.app/Contents/MacOS/BlackBox
  // Strip two path components to reach Contents/
  char* p = strrchr(exe, '/');
  if (!p) { free(exe); return NULL; }
  *p = '\0';

  p = strrchr(exe, '/');
  if (!p) { free(exe); return NULL; }
  *p = '\0';

  return exe; // caller must free
}

// Prepend value to an existing env var (colon-separated), or set it.
static void prepend_env(const char* key, const char* value) {
  const char* existing = getenv(key);
  if (existing && *existing) {
    char buf[4096];
    snprintf(buf, sizeof(buf), "%s:%s", value, existing);
    setenv(key, buf, 1);
  } else {
    setenv(key, value, 1);
  }
}

// Set GDK_PIXBUF_MODULEDIR to the bundled loaders directory if present.
static void setup_pixbuf_loaders(const char* contents) {
  char pixbuf_base[PATH_MAX];
  snprintf(pixbuf_base, sizeof(pixbuf_base), "%s/Resources/lib/gdk-pixbuf-2.0", contents);

  DIR* d = opendir(pixbuf_base);
  if (!d) return;

  struct dirent* ent;
  while ((ent = readdir(d)) != NULL) {
    if (ent->d_name[0] == '.') continue;
    char loaders[PATH_MAX];
    snprintf(loaders, sizeof(loaders), "%s/%s/loaders", pixbuf_base, ent->d_name);
    if (access(loaders, F_OK) == 0) {
      setenv("GDK_PIXBUF_MODULEDIR", loaders, 0);
      break;
    }
  }
  closedir(d);
}

int main(int argc, char* argv[]) {
  char* contents = get_bundle_contents_dir();
  if (!contents) {
    fprintf(stderr, "blackbox: cannot determine bundle location\n");
    return 1;
  }

  char share[PATH_MAX];
  snprintf(share, sizeof(share), "%s/Resources/share", contents);

  // GSettings schemas — prefer bundled, fall back to what is already set.
  char schema_dir[PATH_MAX];
  snprintf(schema_dir, sizeof(schema_dir), "%s/glib-2.0/schemas", share);
  if (access(schema_dir, F_OK) == 0)
    setenv("GSETTINGS_SCHEMA_DIR", schema_dir, 0);

  // XDG data dirs — prepend bundle share so GLib finds icons, schemes, etc.
  prepend_env("XDG_DATA_DIRS", share);

  // GDK-pixbuf loaders (optional; the bundle may not include them).
  setup_pixbuf_loaders(contents);

  // Adwaita CSS compat overlay (suppresses thousands of GTK CSS warnings).
  char overlay_dir[PATH_MAX];
  snprintf(overlay_dir, sizeof(overlay_dir), "%s/Resources/gtk-css-compat", contents);
  if (access(overlay_dir, F_OK) == 0) {
    char overlay[2048];
    snprintf(overlay, sizeof(overlay), "/org/gnome/Adwaita=%s", overlay_dir);
    prepend_env("G_RESOURCE_OVERLAYS", overlay);
  }

  // Launch from home so the initial working directory is sensible.
  const char* home = getenv("HOME");
  if (home) chdir(home);

  char binary[PATH_MAX];
  snprintf(binary, sizeof(binary), "%s/MacOS/blackbox-terminal", contents);
  free(contents);

  execv(binary, argv);
  perror("blackbox: execv");
  return 1;
}
