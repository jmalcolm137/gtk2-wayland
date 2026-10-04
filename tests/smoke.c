/* smoke.c — the smallest GTK2 client that opens a window and quits.
 *
 * Used by scripts/run-app.sh to prove the GDK -> libX11 shim -> Wayland path
 * end to end inside nested labwc.  It is deliberately boring: one toplevel,
 * one label, a timed quit.
 */
#include <gtk/gtk.h>

static gboolean quit_cb(gpointer data)
{
    (void)data;
    gtk_main_quit();
    return FALSE;
}

int main(int argc, char **argv)
{
    gtk_init(&argc, &argv);

    /* How long to stay up.  The headless compositor captures at its own
     * --timeout, so a capture run sets SMOKE_MS longer than that. */
    guint lifetime = 1500;
    const char *env = g_getenv("SMOKE_MS");
    if (env && *env) lifetime = (guint)g_ascii_strtoull(env, NULL, 10);

    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(win), "GTK+ 2 on Wayland");
    gtk_window_set_default_size(GTK_WINDOW(win), 320, 200);
    g_signal_connect(win, "destroy", G_CALLBACK(gtk_main_quit), NULL);

    GtkWidget *label = gtk_label_new("Hello from GTK+ 2 on Wayland");
    gtk_container_add(GTK_CONTAINER(win), label);
    gtk_widget_show_all(win);

    g_timeout_add(lifetime, quit_cb, NULL);
    gtk_main();
    return 0;
}
