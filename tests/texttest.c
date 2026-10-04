/* texttest.c - a grid of known strings, to compare glyph layout between the
 * shim's Render path and cairo's core-protocol fallback (the ground truth for
 * "what GTK2 does on X11").
 *
 * Left-aligned labels in a fixed order, so a diff of the two captures shows
 * exactly which glyphs land in the wrong place.
 *
 * Build: see tests/Makefile (scripts/build-tests.sh).
 */
#include <gtk/gtk.h>

static const char *lines[] = {
    "Hamburgefonstiv",
    "Desktop",
    "Documents",
    "Downloads",
    "Music",
    "Pictures",
    "Videos",
    "Network",
    "Browse Network",
    "File System",
    "The quick brown fox jumps over the lazy dog",
    "iiiiiiiiii WWWWWWWWWW 0123456789",
    "Hello from GTK+ 2 on Wayland",
    "AVWA To Ta LT  fjord  office",
    NULL
};

static gboolean quit_cb(gpointer d)
{
    (void)d;
    gtk_main_quit();
    return FALSE;
}

int main(int argc, char **argv)
{
    gtk_init(&argc, &argv);

    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(win), "text layout");
    gtk_window_set_default_size(GTK_WINDOW(win), 560, 440);

    GtkWidget *vbox = gtk_vbox_new(FALSE, 3);
    for (int i = 0; lines[i]; i++) {
        GtkWidget *l = gtk_label_new(lines[i]);
        gtk_misc_set_alignment(GTK_MISC(l), 0.0f, 0.5f);
        gtk_box_pack_start(GTK_BOX(vbox), l, FALSE, FALSE, 0);
    }
    gtk_container_add(GTK_CONTAINER(win), vbox);
    g_signal_connect(win, "destroy", G_CALLBACK(gtk_main_quit), NULL);
    gtk_widget_show_all(win);

    guint lifetime = 4000;
    const char *env = g_getenv("SMOKE_MS");
    if (env && *env) lifetime = (guint)g_ascii_strtoull(env, NULL, 10);

    g_timeout_add(lifetime, quit_cb, NULL);
    gtk_main();
    return 0;
}
