/* demowalk.c - run a single gtk-demo demo, for automated graphical review.
 *
 * Builds against the gtk-demo objects (all of them except main.o), and
 * replaces main()/demo_find_file().  --index N selects the N-th demo in the
 * depth-first flattened table; --ms sets how long to show it; --list prints the
 * index/title of every demo.
 */
#include <gtk/gtk.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include "demos.h"

#ifndef DEMOCODEDIR
#define DEMOCODEDIR "."
#endif

gchar *demo_find_file (const gchar *base, GError **err)
{
    if (g_file_test ("gtk-logo-rgb.gif", G_FILE_TEST_EXISTS) &&
        g_file_test (base, G_FILE_TEST_EXISTS))
        return g_strdup (base);
    char *filename = g_build_filename (DEMOCODEDIR, base, NULL);
    if (!g_file_test (filename, G_FILE_TEST_EXISTS)) {
        g_set_error (err, G_FILE_ERROR, G_FILE_ERROR_NOENT,
                     "Cannot find demo data file \"%s\"", base);
        g_free (filename);
        return NULL;
    }
    return filename;
}

extern Demo testgtk_demos[];

static Demo *flat[512];
static int nflat;

static void flatten (Demo *d)
{
    for (; d->title; d++)
    {
        if (d->func) flat[nflat++] = d;
        if (d->children) flatten (d->children);
    }
}

int main (int argc, char **argv)
{
    int idx = 0, ms = 2500, list = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp (argv[i], "--index") && i + 1 < argc) idx = atoi (argv[++i]);
        else if (!strcmp (argv[i], "--ms") && i + 1 < argc) ms = atoi (argv[++i]);
        else if (!strcmp (argv[i], "--list")) list = 1;
    }

    gtk_init (&argc, &argv);
    flatten (testgtk_demos);

    if (list) {
        for (int i = 0; i < nflat; i++) g_print ("%d\t%s\n", i, flat[i]->title);
        return 0;
    }
    if (idx < 0 || idx >= nflat) { g_print ("BAD index\n"); return 2; }

    GtkWidget *parent = gtk_window_new (GTK_WINDOW_TOPLEVEL);
    gtk_window_set_default_size (GTK_WINDOW (parent), 1, 1);
    g_print ("DEMO\t%d\t%s\n", idx, flat[idx]->title);
    fflush (stdout);
    flat[idx]->func (parent);

    g_timeout_add (ms, (GSourceFunc) gtk_main_quit, NULL);
    gtk_main ();
    return 0;
}
