/* HeaderBar.vala
 *
 * Copyright 2022 Paulo Queiroz <pvaqueiroz@gmail.com>
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

[GtkTemplate(ui = "/com/raggesilver/BlackBox/gtk/header-bar.ui")]
public class Terminal.HeaderBar : Adw.Bin {
  [GtkChild] public unowned Adw.TabBar tab_bar;

  public Window   window        { get; set; }
  public Settings settings      { get; construct set; }
  public bool     floating_mode { get; set; default = false; }

  public bool single_tab_mode {
    get {
      var settings = Settings.get_default();
      return (
        (this.window == null || this.window.tab_view.n_pages <= 1) &&
        settings.fill_tabs
      );
    }
  }

  static construct {
    set_css_name("headerbar");
    typeof (StyleSwitcher).class_ref();
  }

  construct {
    this.settings = Settings.get_default();
  }

  public HeaderBar (Window window) {
    Object(window: window);

    this.connect_signals();
  }

  private void connect_signals() {
    var settings = Settings.get_default();

    this.window.tab_view.notify["n-pages"]
    .connect(this.notify_single_tab_mode);

    settings.notify["fill-tabs"].connect(this.notify_single_tab_mode);

    settings.notify["headerbar-drag-area"].connect(
      this.on_drag_area_changed
    );
    this.on_drag_area_changed();

    this.notify["single-tab-mode"].connect(this.on_single_tab_mode_changed);
    this.on_single_tab_mode_changed();

    var gtk_settings = Gtk.Settings.get_default();
    gtk_settings.notify["gtk-decoration-layout"].connect(
      this.update_tabbar_empty_classes
    );
    settings.notify["show-search-toggle-button"].connect(
      this.update_tabbar_empty_classes
    );
    settings.notify["show-new-tab-button"].connect(
      this.update_tabbar_empty_classes
    );
    settings.notify["show-menu-button"].connect(
      this.update_tabbar_empty_classes
    );
    this.window.notify["fullscreened"].connect(
      this.update_tabbar_empty_classes);
    this.notify["floating-mode"].connect(this.update_tabbar_empty_classes);
    this.update_tabbar_empty_classes();

    var mcc = new Gtk.GestureClick() {
      button = Gdk.BUTTON_MIDDLE,
    };
    mcc.pressed.connect(() => {
      this.window.new_tab(null, null);
    });
    this.add_controller(mcc);
  }

  [GtkCallback]
  private void unfullscreen() {
    this.window.unfullscreen();
  }

  [GtkCallback]
  private bool show_window_controls(
    bool fullscreened,
    bool _is_floating,
    bool _is_single_tab_mode,
    bool is_header_bar_controls
  ) {
    return (
      (this.window == null || !fullscreened) &&
      (!_is_floating) &&
      (!is_header_bar_controls || _is_single_tab_mode)
    );
  }

  [GtkCallback]
  private string get_visible_stack_name(bool is_single_tab_mode) {
    return is_single_tab_mode ? "single-tab-page" : "multi-tab-page";
  }

  private void notify_single_tab_mode() {
    this.notify_property("single-tab-mode");
  }

  private void on_drag_area_changed() {
    var drag_area = Settings.get_default().headerbar_drag_area;

    set_css_class(this, "with-dragarea", drag_area);
  }

  private void on_single_tab_mode_changed() {
    bool single_tab_enabled = this.single_tab_mode;

    set_css_class(this, "single-tab-mode", single_tab_enabled);
  }

  private void update_tabbar_empty_classes() {
    set_css_class(this, "left-empty", this.is_tabbar_side_empty(true));
    set_css_class(this, "right-empty", this.is_tabbar_side_empty(false));
  }

  private bool is_tabbar_side_empty(bool start_side) {
    bool fullscreened = this.window != null && this.window.fullscreened;
    bool controls_visible = !this.floating_mode && !fullscreened;

    if (start_side) {
      bool controls_have_buttons =
        controls_visible && this.decoration_layout_side_has_buttons(true);
      bool search_visible =
        Settings.get_default().show_search_toggle_button;
      return !controls_have_buttons && !search_visible;
    } else {
      bool controls_have_buttons =
        controls_visible && this.decoration_layout_side_has_buttons(false);
      bool new_tab_visible = Settings.get_default().show_new_tab_button;
      bool menu_visible    = Settings.get_default().show_menu_button;
      return !controls_have_buttons && !new_tab_visible && !menu_visible &&
             !fullscreened;
    }
  }

  private bool decoration_layout_side_has_buttons(bool start_side) {
    var layout =
      Gtk.Settings.get_default().gtk_decoration_layout ?? "";
    var parts = layout.split(":");
    var side  = start_side
      ? (parts.length > 0 ? parts[0] : "")
      : (parts.length > 1 ? parts[1] : "");

    foreach (var token in side.split(",")) {
      var t = token.strip();
      if (t != "" && t != "spacer") { return true; }
    }
    return false;
  }
}
