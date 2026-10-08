/* printtest.c — GtkPrint under the shim, exported to PDF.
 *
 * GtkPrint is display-server-independent: it renders through cairo and its
 * backends (`file`, `lpr`, `cups`) do the I/O themselves.  This drives a
 * GtkPrintOperation in EXPORT mode, which needs no print server, and checks the
 * PDF it writes.
 */
#include <gtk/gtk.h>
#include <string.h>

static void draw_page(GtkPrintOperation *op, GtkPrintContext *ctx,
                      gint page_nr, gpointer data)
{
    (void)op; (void)page_nr; (void)data;
    cairo_t *cr = gtk_print_context_get_cairo_context(ctx);
    cairo_set_source_rgb(cr, 0, 0, 0);
    cairo_set_font_size(cr, 24);
    cairo_move_to(cr, 72, 72);
    cairo_show_text(cr, "Motif/Wayland print test");
}

int main(int argc, char **argv)
{
    setbuf(stdout, NULL);
    gtk_init(&argc, &argv);

    const char *out = g_getenv("PRINT_OUT");
    if (!out) out = "/tmp/gtk2-print.pdf";

    GtkPrintOperation *op = gtk_print_operation_new();
    GtkPageSetup *setup = gtk_page_setup_new();
    gtk_page_setup_set_paper_size_and_default_margins(
        setup, gtk_paper_size_new("iso_a4"));
    gtk_print_operation_set_default_page_setup(op, setup);
    gtk_print_operation_set_export_filename(op, out);
    gtk_print_operation_set_n_pages(op, 1);
    g_signal_connect(op, "draw-page", G_CALLBACK(draw_page), NULL);

    GError *err = NULL;
    GtkPrintOperationResult r =
        gtk_print_operation_run(op, GTK_PRINT_OPERATION_ACTION_EXPORT, NULL, &err);
    if (err) {
        fprintf(stderr, "print: %s\n", err->message);
        g_error_free(err);
    }
    int ok = (r == GTK_PRINT_OPERATION_RESULT_APPLY ||
              r == GTK_PRINT_OPERATION_RESULT_IN_PROGRESS) &&
             g_file_test(out, G_FILE_TEST_EXISTS);
    printf("PRINT:result=%d exists=%d file=%s\n", (int)r, ok, out);
    return ok ? 0 : 1;
}
