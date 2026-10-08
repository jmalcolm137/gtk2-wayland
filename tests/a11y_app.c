/* a11y_app.c — a GTK2 app whose accessible tree a client will query.
 *
 * GAIL exposes the ATK tree; with GTK_MODULES including atk-bridge it is
 * published on the accessibility bus.  The app quits after a few seconds so the
 * test can collect the query result.
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
    g_set_application_name("a11ytest");

    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(win), "a11ytest window");
    GtkWidget *box = gtk_vbox_new(FALSE, 0);
    gtk_container_add(GTK_CONTAINER(win), box);
    GtkWidget *btn = gtk_button_new_with_label("hello-a11y");
    gtk_box_pack_start(GTK_BOX(box), btn, FALSE, FALSE, 0);
    gtk_widget_show_all(win);

    g_timeout_add(6000, quit_cb, NULL);
    gtk_main();
    return 0;
}
