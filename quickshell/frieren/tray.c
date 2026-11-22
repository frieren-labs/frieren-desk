// Frieren tray helper: StatusNotifierItem + DBusMenu in C.
//
// This is the tray icon for Frieren. It speaks the StatusNotifierItem and
// DBusMenu interfaces the DMS bar expects, uses only GIO, and exits with the
// qs process through a parent death signal.
//
// Build:
//   cc -O2 -o frieren-tray tray.c $(pkg-config --cflags --libs gio-2.0)

#include <gio/gio.h>
#include <glib-unix.h>
#include <glib/gstdio.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef __linux__
#include <sys/prctl.h>
#endif

#define BUS_NAME "org.kde.StatusNotifierItem-frieren"
#define SNI_PATH "/StatusNotifierItem"
#define MENU_PATH "/MenuBar"
#define CONFIG_NAME "frieren"

#define ID_TOGGLE_PET 1
#define ID_CHAT 2
#define ID_STOP 4
#define ID_SEP_1 5
#define ID_SETTINGS 6
#define ID_WANDER 7
#define ID_SLEEP 8
#define ID_BLINK 9
#define ID_SIZE 10
#define ID_SMALL 11
#define ID_MEDIUM 12
#define ID_LARGE 13
#define ID_RESET 14
#define ID_SEP_2 15
#define ID_QUIT 16
#define ID_AUTH 17
#define ID_LOG 18
#define ID_ABOUT 19

typedef struct {
    gboolean minimized;
    gboolean wander;
    gboolean sleep;
    gboolean blink;
    gboolean log;
    gboolean auth;
    gboolean busy;
    gboolean chatOpen;
    double scale;
} State;

typedef struct {
    guchar *data;
    gsize len;
    gint32 size;
} IconBuf;

typedef struct {
    GMainLoop *loop;
    GDBusConnection *bus;
    guint owner_id;
    guint sni_reg;
    guint menu_reg;
    GDBusNodeInfo *sni_info;
    GDBusNodeInfo *menu_info;
    GFileMonitor *monitor;
    guint poll_id;
    guint register_id;
    gchar *state_path;
    gchar *icon_name;
    gchar *qs_bin;
    IconBuf icons[3];
    State state;
    gint64 last_mtime;
    guint32 revision;
    gboolean shutting_down;
} App;

static const char *sni_xml =
    "<node>"
    " <interface name='org.kde.StatusNotifierItem'>"
    "  <method name='Activate'>"
    "   <arg name='x' type='i' direction='in'/>"
    "   <arg name='y' type='i' direction='in'/>"
    "  </method>"
    "  <method name='ContextMenu'>"
    "   <arg name='x' type='i' direction='in'/>"
    "   <arg name='y' type='i' direction='in'/>"
    "  </method>"
    "  <method name='SecondaryActivate'>"
    "   <arg name='x' type='i' direction='in'/>"
    "   <arg name='y' type='i' direction='in'/>"
    "  </method>"
    "  <method name='Scroll'>"
    "   <arg name='delta' type='i' direction='in'/>"
    "   <arg name='orientation' type='s' direction='in'/>"
    "  </method>"
    "  <property name='Category' type='s' access='read'/>"
    "  <property name='Id' type='s' access='read'/>"
    "  <property name='Title' type='s' access='read'/>"
    "  <property name='Status' type='s' access='read'/>"
    "  <property name='WindowId' type='i' access='read'/>"
    "  <property name='IconName' type='s' access='read'/>"
    "  <property name='IconPixmap' type='a(iiay)' access='read'/>"
    "  <property name='OverlayIconName' type='s' access='read'/>"
    "  <property name='OverlayIconPixmap' type='a(iiay)' access='read'/>"
    "  <property name='AttentionIconName' type='s' access='read'/>"
    "  <property name='AttentionIconPixmap' type='a(iiay)' access='read'/>"
    "  <property name='AttentionMovieName' type='s' access='read'/>"
    "  <property name='ToolTip' type='(sa(iiay)ss)' access='read'/>"
    "  <property name='ItemIsMenu' type='b' access='read'/>"
    "  <property name='Menu' type='o' access='read'/>"
    " </interface>"
    "</node>";

static const char *menu_xml =
    "<node>"
    " <interface name='com.canonical.dbusmenu'>"
    "  <method name='GetLayout'>"
    "   <arg name='parentId' type='i' direction='in'/>"
    "   <arg name='recursionDepth' type='i' direction='in'/>"
    "   <arg name='propertyNames' type='as' direction='in'/>"
    "   <arg name='revision' type='u' direction='out'/>"
    "   <arg name='layout' type='(ia{sv}av)' direction='out'/>"
    "  </method>"
    "  <method name='GetGroupProperties'>"
    "   <arg name='ids' type='ai' direction='in'/>"
    "   <arg name='propertyNames' type='as' direction='in'/>"
    "   <arg name='properties' type='a(ia{sv})' direction='out'/>"
    "  </method>"
    "  <method name='GetProperty'>"
    "   <arg name='id' type='i' direction='in'/>"
    "   <arg name='name' type='s' direction='in'/>"
    "   <arg name='value' type='v' direction='out'/>"
    "  </method>"
    "  <method name='Event'>"
    "   <arg name='id' type='i' direction='in'/>"
    "   <arg name='eventId' type='s' direction='in'/>"
    "   <arg name='data' type='v' direction='in'/>"
    "   <arg name='timestamp' type='u' direction='in'/>"
    "  </method>"
    "  <method name='AboutToShow'>"
    "   <arg name='id' type='i' direction='in'/>"
    "   <arg name='needUpdate' type='b' direction='out'/>"
    "  </method>"
    "  <method name='AboutToShowGroup'>"
    "   <arg name='ids' type='ai' direction='in'/>"
    "   <arg name='updatesNeeded' type='ai' direction='out'/>"
    "   <arg name='idErrors' type='ai' direction='out'/>"
    "  </method>"
    "  <signal name='LayoutUpdated'>"
    "   <arg name='revision' type='u'/>"
    "   <arg name='parent' type='i'/>"
    "  </signal>"
    "  <signal name='ItemsPropertiesUpdated'>"
    "   <arg name='updatedProps' type='a(ia{sv})'/>"
    "   <arg name='removedProps' type='a(ias)'/>"
    "  </signal>"
    " </interface>"
    "</node>";

static void read_state(App *app);
static GVariant *build_node(App *app, gint32 id);
static GVariant *props_for_id(App *app, gint32 id);
static void activate(App *app, gint32 id);

static gboolean json_bool(const gchar *text, const gchar *key, gboolean fallback) {
    gchar *pattern = g_strdup_printf("\"%s\"", key);
    const gchar *p = strstr(text, pattern);
    g_free(pattern);
    if (!p) return fallback;
    p += strlen(key) + 2;
    while (*p && *p != ':') p++;
    if (*p == ':') p++;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
    if (g_str_has_prefix(p, "true")) return TRUE;
    if (g_str_has_prefix(p, "false")) return FALSE;
    return fallback;
}

static double json_number(const gchar *text, const gchar *key, double fallback) {
    gchar *pattern = g_strdup_printf("\"%s\"", key);
    const gchar *p = strstr(text, pattern);
    g_free(pattern);
    if (!p) return fallback;
    p += strlen(key) + 2;
    while (*p && *p != ':') p++;
    if (*p == ':') p++;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
    gchar *end = NULL;
    double value = g_ascii_strtod(p, &end);
    return end == p ? fallback : value;
}

static void read_state(App *app) {
    gchar *data = NULL;
    if (!g_file_get_contents(app->state_path, &data, NULL, NULL)) return;
    app->state.minimized = json_bool(data, "minimized", app->state.minimized);
    app->state.wander = json_bool(data, "wander", app->state.wander);
    app->state.sleep = json_bool(data, "sleep", app->state.sleep);
    app->state.blink = json_bool(data, "blink", app->state.blink);
    app->state.log = json_bool(data, "log", app->state.log);
    app->state.auth = json_bool(data, "auth", app->state.auth);
    app->state.busy = json_bool(data, "busy", app->state.busy);
    app->state.chatOpen = json_bool(data, "chatOpen", app->state.chatOpen);
    app->state.scale = json_number(data, "scale", app->state.scale);
    g_free(data);
}

static GVariant *empty_props(void) {
    GVariantBuilder builder;
    g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
    return g_variant_builder_end(&builder);
}

static GVariant *item_props(const gchar *label, gboolean enabled,
                            const gchar *type, const gchar *children_display,
                            const gchar *toggle_type, gint32 toggle_state) {
    GVariantBuilder builder;
    g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
    if (label) g_variant_builder_add(&builder, "{sv}", "label", g_variant_new_string(label));
    g_variant_builder_add(&builder, "{sv}", "enabled", g_variant_new_boolean(enabled));
    g_variant_builder_add(&builder, "{sv}", "visible", g_variant_new_boolean(TRUE));
    g_variant_builder_add(&builder, "{sv}", "type",
                          g_variant_new_string(type ? type : "standard"));
    if (children_display)
        g_variant_builder_add(&builder, "{sv}", "children-display",
                              g_variant_new_string(children_display));
    if (toggle_type) {
        g_variant_builder_add(&builder, "{sv}", "toggle-type",
                              g_variant_new_string(toggle_type));
        g_variant_builder_add(&builder, "{sv}", "toggle-state",
                              g_variant_new_int32(toggle_state));
    }
    return g_variant_builder_end(&builder);
}

static GVariant *props_for_id(App *app, gint32 id) {
    const State *s = &app->state;
    switch (id) {
        case ID_TOGGLE_PET:
            return item_props(s->minimized ? "Show pet" : "Hide pet", TRUE, NULL, NULL, NULL, 0);
        case ID_CHAT:
            return item_props(s->chatOpen ? "Close chat" : "Open chat", TRUE, NULL, NULL, NULL, 0);
        case ID_STOP:
            return item_props("Stop", s->busy, NULL, NULL, NULL, 0);
        case ID_SEP_1:
        case ID_SEP_2:
            return item_props(NULL, TRUE, "separator", NULL, NULL, 0);
        case ID_SETTINGS:
            return item_props("Settings", TRUE, "submenu", "submenu", NULL, 0);
        case ID_WANDER:
            return item_props("Wander", TRUE, NULL, NULL, "checkmark", s->wander ? 1 : 0);
        case ID_SLEEP:
            return item_props("Sleep when idle", TRUE, NULL, NULL, "checkmark", s->sleep ? 1 : 0);
        case ID_BLINK:
            return item_props("Blink", TRUE, NULL, NULL, "checkmark", s->blink ? 1 : 0);
        case ID_LOG:
            return item_props("Activity log", TRUE, NULL, NULL, "checkmark", s->log ? 1 : 0);
        case ID_SIZE:
            return item_props("Size", TRUE, "submenu", "submenu", NULL, 0);
        case ID_SMALL:
            return item_props("Small", TRUE, NULL, NULL, "radio", s->scale <= 0.92 ? 1 : 0);
        case ID_MEDIUM:
            return item_props("Medium", TRUE, NULL, NULL, "radio",
                              (s->scale > 0.92 && s->scale < 1.08) ? 1 : 0);
        case ID_LARGE:
            return item_props("Large", TRUE, NULL, NULL, "radio", s->scale >= 1.08 ? 1 : 0);
        case ID_RESET:
            return item_props("Reset position", TRUE, NULL, NULL, NULL, 0);
        case ID_ABOUT:
            return item_props("About", TRUE, NULL, NULL, NULL, 0);
        case ID_QUIT:
            return item_props("Quit", TRUE, NULL, NULL, NULL, 0);
        case ID_AUTH:
            return item_props(s->auth ? "Account" : "Setup account",
                              TRUE, NULL, NULL, NULL, 0);
        default:
            return empty_props();
    }
}

static GVariant *make_node(gint32 id, GVariant *props, GVariant *children) {
    return g_variant_new("(i@a{sv}@av)", id, props, children);
}

static GVariant *empty_children(void) {
    GVariantBuilder builder;
    g_variant_builder_init(&builder, G_VARIANT_TYPE("av"));
    return g_variant_builder_end(&builder);
}

static GVariant *children_of(App *app, const gint32 *ids, gsize count) {
    GVariantBuilder builder;
    g_variant_builder_init(&builder, G_VARIANT_TYPE("av"));
    for (gsize i = 0; i < count; i++) {
        g_variant_builder_add(&builder, "v", build_node(app, ids[i]));
    }
    return g_variant_builder_end(&builder);
}

static GVariant *build_node(App *app, gint32 id) {
    static const gint32 root_children[] = {
        ID_TOGGLE_PET, ID_CHAT, ID_STOP, ID_SEP_1,
        ID_AUTH, ID_SETTINGS, ID_ABOUT, ID_SEP_2, ID_QUIT
    };
    static const gint32 settings_children[] = {
        ID_WANDER, ID_SLEEP, ID_BLINK, ID_LOG, ID_SIZE, ID_RESET
    };
    static const gint32 size_children[] = {ID_SMALL, ID_MEDIUM, ID_LARGE};

    if (id == 0) {
        GVariantBuilder props;
        g_variant_builder_init(&props, G_VARIANT_TYPE("a{sv}"));
        g_variant_builder_add(&props, "{sv}", "type", g_variant_new_string("submenu"));
        g_variant_builder_add(&props, "{sv}", "children-display",
                              g_variant_new_string("submenu"));
        return make_node(0, g_variant_builder_end(&props),
                         children_of(app, root_children,
                                     G_N_ELEMENTS(root_children)));
    }
    if (id == ID_SETTINGS) {
        return make_node(id, props_for_id(app, id),
                         children_of(app, settings_children,
                                     G_N_ELEMENTS(settings_children)));
    }
    if (id == ID_SIZE) {
        return make_node(id, props_for_id(app, id),
                         children_of(app, size_children,
                                     G_N_ELEMENTS(size_children)));
    }
    return make_node(id, props_for_id(app, id), empty_children());
}

static GVariant *build_pixmaps(App *app, gboolean include) {
    GVariantBuilder builder;
    g_variant_builder_init(&builder, G_VARIANT_TYPE("a(iiay)"));
    if (include) {
        for (gsize i = 0; i < G_N_ELEMENTS(app->icons); i++) {
            IconBuf *icon = &app->icons[i];
            if (!icon->data || icon->len == 0) continue;
            GVariant *bytes = g_variant_new_fixed_array(
                G_VARIANT_TYPE_BYTE, icon->data, icon->len, 1);
            g_variant_builder_add(&builder, "(ii@ay)",
                                  icon->size, icon->size, bytes);
        }
    }
    return g_variant_builder_end(&builder);
}

// ---------------- StatusNotifierItem ----------------

static GVariant *on_sni_property(GDBusConnection *connection,
                                 const gchar *sender,
                                 const gchar *object_path,
                                 const gchar *interface_name,
                                 const gchar *property_name,
                                 GError **error,
                                 gpointer user_data) {
    (void)connection;
    (void)sender;
    (void)object_path;
    (void)interface_name;
    App *app = user_data;

    if (g_strcmp0(property_name, "Category") == 0)
        return g_variant_new_string("ApplicationStatus");
    if (g_strcmp0(property_name, "Id") == 0)
        return g_variant_new_string("frieren");
    if (g_strcmp0(property_name, "Title") == 0)
        return g_variant_new_string("Frieren");
    if (g_strcmp0(property_name, "Status") == 0)
        return g_variant_new_string("Active");
    if (g_strcmp0(property_name, "WindowId") == 0)
        return g_variant_new_int32(0);
    if (g_strcmp0(property_name, "IconName") == 0)
        return g_variant_new_string(app->icon_name);
    if (g_strcmp0(property_name, "IconPixmap") == 0)
        return build_pixmaps(app, TRUE);
    if (g_strcmp0(property_name, "OverlayIconName") == 0 ||
        g_strcmp0(property_name, "AttentionIconName") == 0 ||
        g_strcmp0(property_name, "AttentionMovieName") == 0)
        return g_variant_new_string("");
    if (g_strcmp0(property_name, "OverlayIconPixmap") == 0 ||
        g_strcmp0(property_name, "AttentionIconPixmap") == 0)
        return build_pixmaps(app, FALSE);
    if (g_strcmp0(property_name, "ToolTip") == 0)
        return g_variant_new("(s@a(iiay)ss)", "", build_pixmaps(app, FALSE),
                             "Frieren", "Desktop assistant");
    if (g_strcmp0(property_name, "ItemIsMenu") == 0)
        return g_variant_new_boolean(TRUE);
    if (g_strcmp0(property_name, "Menu") == 0)
        return g_variant_new_object_path(MENU_PATH);

    g_set_error(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                "Unknown property %s", property_name);
    return NULL;
}

static void on_sni_method(GDBusConnection *connection,
                          const gchar *sender,
                          const gchar *object_path,
                          const gchar *interface_name,
                          const gchar *method_name,
                          GVariant *parameters,
                          GDBusMethodInvocation *invocation,
                          gpointer user_data) {
    (void)connection;
    (void)sender;
    (void)object_path;
    (void)interface_name;
    (void)parameters;
    App *app = user_data;

    if (g_strcmp0(method_name, "Activate") == 0 ||
        g_strcmp0(method_name, "SecondaryActivate") == 0) {
        read_state(app);
        activate(app, ID_CHAT);
    }
    g_dbus_method_invocation_return_value(invocation, NULL);
}

// ---------------- DBusMenu ----------------

static void emit_state_changed(App *app) {
    app->revision += 1;
    GError *error = NULL;
    g_dbus_connection_emit_signal(
        app->bus, NULL, MENU_PATH, "com.canonical.dbusmenu", "LayoutUpdated",
        g_variant_new("(ui)", app->revision, 0), &error);
    if (error) {
        g_printerr("frieren-tray: LayoutUpdated failed: %s\n", error->message);
        g_error_free(error);
        error = NULL;
    }

    static const gint32 dynamic_ids[] = {
        ID_TOGGLE_PET, ID_CHAT, ID_STOP, ID_AUTH,
        ID_WANDER, ID_SLEEP, ID_BLINK, ID_LOG,
        ID_SMALL, ID_MEDIUM, ID_LARGE
    };
    GVariantBuilder updated;
    g_variant_builder_init(&updated, G_VARIANT_TYPE("a(ia{sv})"));
    for (gsize i = 0; i < G_N_ELEMENTS(dynamic_ids); i++) {
        g_variant_builder_add(&updated, "(i@a{sv})", dynamic_ids[i],
                              props_for_id(app, dynamic_ids[i]));
    }
    GVariantBuilder removed;
    g_variant_builder_init(&removed, G_VARIANT_TYPE("a(ias)"));
    g_dbus_connection_emit_signal(
        app->bus, NULL, MENU_PATH, "com.canonical.dbusmenu",
        "ItemsPropertiesUpdated",
        g_variant_new("(@a(ia{sv})@a(ias))",
                      g_variant_builder_end(&updated),
                      g_variant_builder_end(&removed)),
        &error);
    if (error) {
        g_printerr("frieren-tray: ItemsPropertiesUpdated failed: %s\n",
                   error->message);
        g_error_free(error);
    }
}

static gint64 state_mtime(App *app) {
    GStatBuf st;
    if (g_stat(app->state_path, &st) != 0) return 0;
    return ((gint64)st.st_mtime) * 1000 + st.st_mtim.tv_nsec / 1000000;
}

static gboolean poll_state(gpointer user_data) {
    App *app = user_data;
    gint64 mtime = state_mtime(app);
    if (mtime != app->last_mtime) {
        app->last_mtime = mtime;
        read_state(app);
        emit_state_changed(app);
    }
    return G_SOURCE_CONTINUE;
}

static void on_state_changed(GFileMonitor *monitor, GFile *file,
                             GFile *other_file, GFileMonitorEvent event_type,
                             gpointer user_data) {
    (void)monitor;
    (void)file;
    (void)other_file;
    (void)event_type;
    poll_state(user_data);
}

static void on_menu_method(GDBusConnection *connection,
                           const gchar *sender,
                           const gchar *object_path,
                           const gchar *interface_name,
                           const gchar *method_name,
                           GVariant *parameters,
                           GDBusMethodInvocation *invocation,
                           gpointer user_data) {
    (void)connection;
    (void)sender;
    (void)object_path;
    (void)interface_name;
    App *app = user_data;

    if (g_strcmp0(method_name, "GetLayout") == 0) {
        gint32 parent = 0;
        gint32 depth = 0;
        GVariant *names = NULL;
        g_variant_get(parameters, "(ii@as)", &parent, &depth, &names);
        (void)depth;
        g_variant_unref(names);

        read_state(app);
        GVariant *node;
        if (parent == 0 || parent == ID_SETTINGS || parent == ID_SIZE) {
            node = build_node(app, parent);
        } else {
            node = make_node(parent, empty_props(), empty_children());
        }
        g_dbus_method_invocation_return_value(
            invocation, g_variant_new("(u@(ia{sv}av))", app->revision, node));
        return;
    }

    if (g_strcmp0(method_name, "GetGroupProperties") == 0) {
        GVariant *ids = NULL;
        GVariant *names = NULL;
        g_variant_get(parameters, "(@ai@as)", &ids, &names);
        g_variant_unref(names);
        read_state(app);

        GVariantBuilder out;
        g_variant_builder_init(&out, G_VARIANT_TYPE("a(ia{sv})"));
        gsize count = g_variant_n_children(ids);
        for (gsize i = 0; i < count; i++) {
            gint32 id = 0;
            g_variant_get_child(ids, i, "i", &id);
            g_variant_builder_add(&out, "(i@a{sv})", id, props_for_id(app, id));
        }
        g_variant_unref(ids);
        g_dbus_method_invocation_return_value(
            invocation, g_variant_new("(@a(ia{sv}))",
                                      g_variant_builder_end(&out)));
        return;
    }

    if (g_strcmp0(method_name, "GetProperty") == 0) {
        gint32 id = 0;
        const gchar *name = NULL;
        g_variant_get(parameters, "(i&s)", &id, &name);
        read_state(app);
        GVariant *props = props_for_id(app, id);
        GVariant *value = g_variant_lookup_value(props, name, NULL);
        if (!value) value = g_variant_new_string("");
        g_variant_unref(props);
        GVariant *reply = g_variant_new("(v)", value);
        g_variant_unref(value);
        g_dbus_method_invocation_return_value(invocation, reply);
        return;
    }

    if (g_strcmp0(method_name, "Event") == 0) {
        gint32 id = 0;
        const gchar *event = NULL;
        GVariant *data = NULL;
        guint32 timestamp = 0;
        g_variant_get(parameters, "(i&svu)", &id, &event, &data, &timestamp);
        (void)timestamp;
        if (g_strcmp0(event, "clicked") == 0) {
            read_state(app);
            activate(app, id);
        }
        g_variant_unref(data);
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }

    if (g_strcmp0(method_name, "AboutToShow") == 0) {
        g_dbus_method_invocation_return_value(invocation,
                                             g_variant_new("(b)", FALSE));
        return;
    }

    if (g_strcmp0(method_name, "AboutToShowGroup") == 0) {
        GVariantBuilder updates;
        GVariantBuilder errors;
        g_variant_builder_init(&updates, G_VARIANT_TYPE("ai"));
        g_variant_builder_init(&errors, G_VARIANT_TYPE("ai"));
        g_dbus_method_invocation_return_value(
            invocation, g_variant_new("(@ai@ai)",
                                      g_variant_builder_end(&updates),
                                      g_variant_builder_end(&errors)));
        return;
    }

    g_dbus_method_invocation_return_error(invocation, G_IO_ERROR,
                                          G_IO_ERROR_NOT_SUPPORTED,
                                          "Unknown menu method %s", method_name);
}

// ---------------- actions ----------------

static void spawn_ipc(App *app, const gchar *action, const gchar *arg) {
    const gchar *argv[9];
    gint index = 0;
    argv[index++] = app->qs_bin;
    argv[index++] = "-c";
    argv[index++] = CONFIG_NAME;
    argv[index++] = "ipc";
    argv[index++] = "call";
    argv[index++] = CONFIG_NAME;
    argv[index++] = action;
    if (arg) argv[index++] = arg;
    argv[index] = NULL;

    GError *error = NULL;
    if (!g_spawn_async(NULL, (gchar **)argv, NULL,
                       G_SPAWN_STDOUT_TO_DEV_NULL | G_SPAWN_STDERR_TO_DEV_NULL,
                       NULL, NULL, NULL, &error)) {
        g_printerr("frieren-tray: could not run qs: %s\n", error->message);
        g_error_free(error);
    }
}

static void activate(App *app, gint32 id) {
    switch (id) {
        case ID_TOGGLE_PET:
            spawn_ipc(app, app->state.minimized ? "restore" : "minimize", NULL);
            break;
        case ID_CHAT:
            spawn_ipc(app, "toggle", NULL);
            break;
        case ID_STOP:
            spawn_ipc(app, "stop", NULL);
            break;
        case ID_WANDER:
            spawn_ipc(app, "wander", "toggle");
            break;
        case ID_SLEEP:
            spawn_ipc(app, "sleep", "toggle");
            break;
        case ID_BLINK:
            spawn_ipc(app, "blink", "toggle");
            break;
        case ID_LOG:
            spawn_ipc(app, "log", "toggle");
            break;
        case ID_SMALL:
            spawn_ipc(app, "scale", "0.85");
            break;
        case ID_MEDIUM:
            spawn_ipc(app, "scale", "1.0");
            break;
        case ID_LARGE:
            spawn_ipc(app, "scale", "1.15");
            break;
        case ID_RESET:
            spawn_ipc(app, "resetpos", NULL);
            break;
        case ID_ABOUT:
            spawn_ipc(app, "about", NULL);
            break;
        case ID_AUTH:
            spawn_ipc(app, "auth", NULL);
            break;
        case ID_QUIT:
            spawn_ipc(app, "quit", NULL);
            break;
        default:
            break;
    }
}

// ---------------- DBus registration ----------------

static const GDBusInterfaceVTable sni_vtable = {
    .method_call = on_sni_method,
    .get_property = on_sni_property,
    .set_property = NULL,
};

static const GDBusInterfaceVTable menu_vtable = {
    .method_call = on_menu_method,
    .get_property = NULL,
    .set_property = NULL,
};

static gboolean register_with_watcher(gpointer user_data) {
    App *app = user_data;
    GError *error = NULL;
    GVariant *reply = g_dbus_connection_call_sync(
        app->bus, "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
        "org.kde.StatusNotifierWatcher", "RegisterStatusNotifierItem",
        g_variant_new("(s)", g_dbus_connection_get_unique_name(app->bus)),
        NULL, G_DBUS_CALL_FLAGS_NONE, 2000, NULL, &error);
    if (reply) {
        g_variant_unref(reply);
        g_print("[frieren-tray] registered with StatusNotifierWatcher\n");
    } else {
        if (error) g_error_free(error);
    }
    return G_SOURCE_CONTINUE;
}

static void on_name_acquired(GDBusConnection *connection, const gchar *name,
                             gpointer user_data) {
    (void)connection;
    (void)name;
    App *app = user_data;
    register_with_watcher(app);
}

static void on_name_lost(GDBusConnection *connection, const gchar *name,
                         gpointer user_data) {
    (void)connection;
    (void)name;
    App *app = user_data;
    if (!app->shutting_down) {
        g_printerr("[frieren-tray] another tray helper is already running\n");
    }
    g_main_loop_quit(app->loop);
}

static gboolean on_quit_signal(gpointer user_data) {
    App *app = user_data;
    app->shutting_down = TRUE;
    g_main_loop_quit(app->loop);
    return G_SOURCE_REMOVE;
}

static void set_parent_death_signal(void) {
#ifdef __linux__
    prctl(PR_SET_PDEATHSIG, SIGTERM);
#endif
}

static gboolean load_icon(IconBuf *icon, const gchar *path, gint32 size) {
    icon->size = size;
    return g_file_get_contents(path, (gchar **)&icon->data, &icon->len, NULL);
}

static void free_app(App *app) {
    if (app->monitor) g_object_unref(app->monitor);
    if (app->sni_reg) g_dbus_connection_unregister_object(app->bus, app->sni_reg);
    if (app->menu_reg) g_dbus_connection_unregister_object(app->bus, app->menu_reg);
    if (app->owner_id) g_bus_unown_name(app->owner_id);
    if (app->sni_info) g_dbus_node_info_unref(app->sni_info);
    if (app->menu_info) g_dbus_node_info_unref(app->menu_info);
    if (app->bus) g_object_unref(app->bus);
    if (app->loop) g_main_loop_unref(app->loop);
    for (gsize i = 0; i < G_N_ELEMENTS(app->icons); i++) g_free(app->icons[i].data);
    g_free(app->state_path);
    g_free(app->icon_name);
    g_free(app->qs_bin);
}

int main(int argc, char **argv) {
    if (argc < 6) {
        g_printerr("usage: frieren-tray ICON.png ICON-128.argb ICON-64.argb "
                   "ICON-32.argb STATE.json\n");
        return 2;
    }

    set_parent_death_signal();
#ifdef __linux__
    if (getppid() == 1) return 0;
#endif

    App app;
    memset(&app, 0, sizeof(app));
    app.loop = g_main_loop_new(NULL, FALSE);
    app.icon_name = g_strdup(argv[1]);
    app.state_path = g_strdup(argv[5]);
    app.qs_bin = g_find_program_in_path("qs");
    if (!app.qs_bin) app.qs_bin = g_strdup("/usr/bin/qs");
    app.state.wander = TRUE;
    app.state.sleep = TRUE;
    app.state.blink = TRUE;
    app.state.log = TRUE;
    app.state.scale = 1.0;
    app.revision = 1;

    load_icon(&app.icons[0], argv[2], 128);
    load_icon(&app.icons[1], argv[3], 64);
    load_icon(&app.icons[2], argv[4], 32);

    gchar *state_dir = g_path_get_dirname(app.state_path);
    if (state_dir) {
        g_mkdir_with_parents(state_dir, 0755);
        g_free(state_dir);
    }
    read_state(&app);
    app.last_mtime = state_mtime(&app);

    GError *error = NULL;
    app.bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (!app.bus) {
        g_printerr("frieren-tray: cannot connect to the session bus: %s\n",
                   error ? error->message : "unknown error");
        if (error) g_error_free(error);
        free_app(&app);
        return 1;
    }

    app.sni_info = g_dbus_node_info_new_for_xml(sni_xml, &error);
    app.menu_info = g_dbus_node_info_new_for_xml(menu_xml, &error);
    if (!app.sni_info || !app.menu_info) {
        g_printerr("frieren-tray: invalid introspection XML: %s\n",
                   error ? error->message : "unknown error");
        if (error) g_error_free(error);
        free_app(&app);
        return 1;
    }

    app.sni_reg = g_dbus_connection_register_object(
        app.bus, SNI_PATH,
        g_dbus_node_info_lookup_interface(app.sni_info,
                                          "org.kde.StatusNotifierItem"),
        &sni_vtable, &app, NULL, &error);
    if (!app.sni_reg) {
        g_printerr("frieren-tray: cannot register the tray object: %s\n",
                   error ? error->message : "unknown error");
        if (error) g_error_free(error);
        free_app(&app);
        return 1;
    }

    app.menu_reg = g_dbus_connection_register_object(
        app.bus, MENU_PATH,
        g_dbus_node_info_lookup_interface(app.menu_info,
                                          "com.canonical.dbusmenu"),
        &menu_vtable, &app, NULL, &error);
    if (!app.menu_reg) {
        g_printerr("frieren-tray: cannot register the menu object: %s\n",
                   error ? error->message : "unknown error");
        if (error) g_error_free(error);
        free_app(&app);
        return 1;
    }

    app.owner_id = g_bus_own_name_on_connection(
        app.bus, BUS_NAME, G_BUS_NAME_OWNER_FLAGS_DO_NOT_QUEUE,
        on_name_acquired, on_name_lost, &app, NULL);

    GFile *state_file = g_file_new_for_path(app.state_path);
    app.monitor = g_file_monitor_file(state_file, G_FILE_MONITOR_NONE, NULL, NULL);
    g_object_unref(state_file);
    if (app.monitor) {
        g_signal_connect(app.monitor, "changed", G_CALLBACK(on_state_changed), &app);
    } else {
        app.poll_id = g_timeout_add(500, poll_state, &app);
    }

    app.register_id = g_timeout_add_seconds(30, register_with_watcher, &app);
    g_unix_signal_add(SIGTERM, on_quit_signal, &app);
    g_unix_signal_add(SIGINT, on_quit_signal, &app);

    g_main_loop_run(app.loop);

    if (app.poll_id) g_source_remove(app.poll_id);
    if (app.register_id) g_source_remove(app.register_id);
    free_app(&app);
    return 0;
}
