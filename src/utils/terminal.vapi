[CCode (cheader_filename = "terminal.h")]
namespace Terminal {
  public int get_foreground_process (int terminal_fd);
  public string? get_process_cmdline (int pid);
  public int get_euid_from_pid (int pid) throws GLib.Error;
  public bool check_pid_running (int pid);
}
