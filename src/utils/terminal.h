/* terminal.h
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

#pragma once

#include <glib.h>

/**
 * terminal_get_foreground_process:
 * @terminal_fd: the file descriptor of the terminal
 *
 * Returns the process group ID of the foreground process running in the
 * terminal associated with @terminal_fd.
 *
 * Returns: the foreground process group ID, or -1 on error
 */
int terminal_get_foreground_process(int terminal_fd);

/**
 * terminal_get_process_cmdline:
 * @pid: the process ID
 *
 * Reads the command line of the process with ID @pid from `/proc/@pid/cmdline`.
 *
 * Returns: (transfer full) (nullable): the command line string, or %NULL if
 *   the process does not exist or the command line cannot be read
 */
gchar *terminal_get_process_cmdline(int pid);

/**
 * terminal_get_euid_from_pid:
 * @pid: the process ID
 * @error: return location for a #GError, or %NULL
 *
 * Returns the effective user ID of the process with ID @pid by stating
 * `/proc/@pid`.
 *
 * Returns: the effective UID of the process, or -1 on error
 */
int terminal_get_euid_from_pid(int pid, GError **error);

/**
 * terminal_check_pid_running:
 * @pid: the process ID
 *
 * Checks whether a process with ID @pid is currently running by sending
 * signal 0 to it.
 *
 * Returns: %TRUE if the process is running, %FALSE otherwise
 */
gboolean terminal_check_pid_running(int pid);
