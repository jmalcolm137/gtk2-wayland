/* settingstest.c — read GtkSettings backed by the shim's XSETTINGS manager.
 *
 * The shim owns _XSETTINGS_S0 and publishes the config file it is pointed at
 * with XLIB_WAYLAND_XSETTINGS.  GTK2 reads those through its XSettings client,
 * so a real GtkSettings must report the configured theme/font/icon theme.
 */
#include <gtk/gtk.h>

#include <stdio.h>

int main(int argc, char **argv)
{
    gtk_init(&argc, &argv);

    GtkSettings *s = gtk_settings_get_default();
    gchar *theme = NULL, *font = NULL, *icon = NULL;
    g_object_get(s,
                 "gtk-theme-name", &theme,
                 "gtk-font-name", &font,
                 "gtk-icon-theme-name", &icon,
                 NULL);

    printf("SETTINGS:theme=%s\n", theme ? theme : "");
    printf("SETTINGS:font=%s\n", font ? font : "");
    printf("SETTINGS:icon=%s\n", icon ? icon : "");
    fflush(stdout);

    g_free(theme); g_free(font); g_free(icon);
    return 0;
}
