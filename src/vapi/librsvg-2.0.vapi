/* Minimal handcrafted vapi for librsvg-2.0 — only covers symbols used in this project */

[CCode (cprefix = "Rsvg", lower_case_cprefix = "rsvg_", cheader_filename = "librsvg/rsvg.h")]
namespace Rsvg {
  [CCode (cname = "RsvgRectangle")]
  public struct Rectangle {
    public double x;
    public double y;
    public double width;
    public double height;
  }

  [CCode (cname = "RsvgHandle", ref_function = "g_object_ref", unref_function = "g_object_unref")]
  public class Handle : GLib.Object {
    [CCode (cname = "rsvg_handle_new_from_data")]
    public Handle.from_data ([CCode (array_length_type = "gsize")] uint8[] data) throws GLib.Error;

    [CCode (cname = "rsvg_handle_render_document")]
    public bool render_document (Cairo.Context cr, Rectangle viewport) throws GLib.Error;
  }
}
