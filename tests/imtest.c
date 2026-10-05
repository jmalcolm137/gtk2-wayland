/* imtest.c — GTK2 input-method end to end.
 *
 * GTK2 picks up the shim's XIM bridge through its loadable im-xim module
 * (GTK_IM_MODULE=xim).  The headless compositor's scripted text-input server
 * sends a canned preedit and then commits "你好"; a real GtkEntry must receive
 * that commit through its GtkIMContext and end up containing the string.
 */
#include <gtk/gtk.h>

#include <stdio.h>
#include <string.h>

static GtkWidget *entry;
static const char *want = "\xe4\xbd\xa0\xe5\xa5\xbd";   /* 你好 */
static int ticks;

static gboolean check(gpointer data)
{
    (void)data;
    const char *t = gtk_entry_get_text(GTK_ENTRY(entry));
    if (t && strcmp(t, want) == 0) {
        printf("IMTEST:COMMIT %s\n", t);
        fflush(stdout);
        gtk_main_quit();
        return FALSE;
    }
    if (++ticks > 240) {   /* ~6s */
        printf("IMTEST:TIMEOUT text='%s'\n", t ? t : "");
        fflush(stdout);
        gtk_main_quit();
        return FALSE;
    }
    return TRUE;
}

int main(int argc, char **argv)
{
    gtk_init(&argc, &argv);

    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_default_size(GTK_WINDOW(win), 300, 60);
    entry = gtk_entry_new();
    gtk_container_add(GTK_CONTAINER(win), entry);
    gtk_widget_show_all(win);
    gtk_window_present(GTK_WINDOW(win));
    gtk_widget_grab_focus(entry);

    g_timeout_add(25, check, NULL);
    gtk_main();

    const char *t = gtk_entry_get_text(GTK_ENTRY(entry));
    printf("IMTEST:RESULT text='%s'\n", t ? t : "");
    fflush(stdout);
    return (t && strcmp(t, want) == 0) ? 0 : 1;
}
