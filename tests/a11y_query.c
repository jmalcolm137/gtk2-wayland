/* a11y_query.c — an AT-SPI client that looks for a widget in another app.
 *
 * Connects to the accessibility bus (via org.a11y.Bus), walks the desktop's
 * applications and reports whether it finds a push button named
 * "hello-a11y" — i.e. whether the GTK2 app published its accessible tree.
 */
#include <atspi/atspi.h>

#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int find_button(AtspiAccessible *obj, const char *needle, int depth)
{
    if (!obj || depth > 8)
        return 0;
    GError *e = NULL;
    char *name = atspi_accessible_get_name(obj, &e);
    if (e) { g_error_free(e); e = NULL; }
    char *role = atspi_accessible_get_role_name(obj, &e);
    if (e) { g_error_free(e); e = NULL; }

    int hit = name && role && !strcmp(role, "push button") && strstr(name, needle);
    if (hit)
        printf("A11Y:BUTTON role=%s name=%s\n", role, name);
    g_free(name);
    g_free(role);
    if (hit)
        return 1;

    int n = atspi_accessible_get_child_count(obj, &e);
    if (e) { g_error_free(e); e = NULL; }
    for (int i = 0; i < n; i++) {
        AtspiAccessible *c = atspi_accessible_get_child_at_index(obj, i, &e);
        if (e) { g_error_free(e); e = NULL; }
        if (!c) continue;
        int r = find_button(c, needle, depth + 1);
        g_object_unref(c);
        if (r) return 1;
    }
    return 0;
}

int main(int argc, char **argv)
{
    setbuf(stdout, NULL);
    const char *needle = argc > 1 ? argv[1] : "hello-a11y";
    atspi_init();

    int found = 0;
    for (int i = 0; i < 60 && !found; i++) {
        AtspiAccessible *desk = atspi_get_desktop(0);
        if (desk) {
            GError *e = NULL;
            int n = atspi_accessible_get_child_count(desk, &e);
            if (e) { g_error_free(e); e = NULL; }
            for (int j = 0; j < n && !found; j++) {
                AtspiAccessible *app = atspi_accessible_get_child_at_index(desk, j, &e);
                if (e) { g_error_free(e); e = NULL; }
                if (!app) continue;
                if (find_button(app, needle, 0))
                    found = 1;
                g_object_unref(app);
            }
        }
        if (!found)
            usleep(200000);
    }

    printf("A11Y:RESULT found=%d\n", found);
    return found ? 0 : 1;
}
