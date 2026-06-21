/* terminal.c
 *
 * Copyright 2026 Paulo Queiroz <pvaqueiroz@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "terminal.h"

#include <glib-object.h>
#include <glib.h>
#include <sys/stat.h>
#include <unistd.h>

int terminal_get_foreground_process(int terminal_fd) {
  return tcgetpgrp(terminal_fd);
}

gchar *terminal_get_process_cmdline(int pid) {
  GError *error = NULL;
  gchar *response = NULL;
  g_autofree gchar *path = g_strdup_printf("/proc/%d/cmdline", pid);

  if (!g_file_get_contents(path, &response, NULL, &error)) {
    if (error != NULL) {
      g_warning("Failed to read cmdline for pid %d: %s", pid, error->message);
    }
    g_clear_error(&error);
    g_clear_pointer(&response, g_free);
    return NULL;
  }

  return g_strstrip(response);
}

int terminal_get_euid_from_pid(int pid, GError **error) {
  g_autofree gchar *path = g_strdup_printf("/proc/%d", pid);

  struct stat buf;

  if (stat(path, &buf) == 0) {
    return buf.st_uid;
  } else {
    g_set_error(error, G_FILE_ERROR, g_file_error_from_errno(errno),
                "Failed to stat process directory for pid %d: %s", pid,
                g_strerror(errno));
    return -1;
  }
}

gboolean terminal_check_pid_running(int pid) { return kill(pid, 0) == 0; }
