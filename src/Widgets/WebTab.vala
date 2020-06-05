/**
* This file is part of Odysseus Web Browser (Copyright Adrian Cochrane 2016-2019).
*
* Odysseus is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Odysseus is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.

* You should have received a copy of the GNU General Public License
* along with Odysseus.  If not, see <http://www.gnu.org/licenses/>.
*/
public class Odysseus.WebTab : Granite.Widgets.Tab {
    public WebKit.WebView web; // To allow it to be wrapped in layout views.
    private Gtk.Revealer find;
    public Overlay.InfoContainer info; // for prompts.
    public bool is_restoring = false;

    public int64 tab_id;
    public int order = -1;

    public Gee.List<StatusIndicator> indicators = new Gee.ArrayList<StatusIndicator>();
    public signal void populate_indicators(Gee.List<StatusIndicator> indicators, WebKit.WebView web);
    public signal void links_parsed(Model.Link[] links, Gee.List<StatusIndicator> indicators);
    public signal void indicators_loaded(Gee.List<StatusIndicator> indicators);

    public string url {
        get {return web.uri;}
    }
    private Granite.Widgets.OverlayBar status_bar;
    public string status {
        get {return status_bar.label;}
        set {
            if (value == "" || value == null) {
                status_bar.visible = false;
            } else {
                status_bar.visible = true;
                status_bar.label = value;
            }
        }
    }
    public string default_status;

    public int historical_id = 0;

    public WebTab(Granite.Widgets.DynamicNotebook parent, int64 tab_id, string? url = null) {
        this.tab_id = tab_id;

        var user_content = new WebKit.UserContentManager();
        this.web = (WebKit.WebView) Object.@new(typeof(WebKit.WebView),
                "web-context", get_web_context(),
                "user-content-manager", user_content);
        if (url != null) web.load_uri(url);

        var inspector = web.get_inspector();
        inspector.open_window.connect(() => {
            new Chromeless(inspector).show_all();
            return true;
        });

        this.info = new Overlay.InfoContainer();
        info.expand = true;
        this.page = info;

        var container = new Gtk.Overlay();
        container.expand = true;
        container.add(this.web);
        info.add(container);
        report_fullscreen();


        container.add_overlay(build_findbar());
        status_bar = new Granite.Widgets.OverlayBar(container);


        this.page.show_all();

        connect_webview(parent);
        Traits.setup_webview(this);
        Persist.setup_tab(this, parent, url == null);
    }

    private Gtk.Widget build_findbar() {
        var revealer = new Gtk.Revealer();
        var find = new Overlay.FindToolbar(web.get_find_controller());
        revealer.add(find);

        find.counted_matches.connect((search, count) => {
            if (revealer.child_revealed && search != "")
                default_status = status = ngettext("%u match of \"%s\" found",
                        "%u matches of \"%s\" found", count).printf(count, search);
            else default_status = status = "";
        });
        find.escape_pressed.connect(() => revealer.reveal_child = false);

        revealer.notify["reveal-child"].connect((pspec) => {
            if (!revealer.reveal_child) {
                default_status = status = "";
                web.get_find_controller().search_finish();
            } else find.grab_focus();
        });
        revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
        revealer.halign = Gtk.Align.END;
        revealer.valign = Gtk.Align.START;
        revealer.show_all();

        this.find = revealer;
        return revealer;
    }

    private void connect_webview(Granite.Widgets.DynamicNotebook parent) {
        web.bind_property("title", this, "label");
        web.bind_property("title", this, "tooltip_text");
        this.icon = new ThemedIcon("text-x-generic-symbolic");
        web.notify["favicon"].connect((sender, property) => {
            restore_favicon();
        });
        web.bind_property("is-loading", this, "working");

        web.create.connect((nav_action) => {
            var tab = new WebTab.with_new_entry(parent, nav_action.get_request().uri, true);
            parent.insert_tab(tab, order >= 0 ? order + 1 : -1);
            return tab.web;
        });
        web.button_press_event.connect((evt) => {
            find.set_reveal_child(false);
            return false;
        });
        web.grab_focus.connect(() => {
            find.set_reveal_child(false);
        });
        web.mouse_target_changed.connect((target, modifiers) => {
            if (target.context_is_link()) {
                status = target.link_uri;
            } else status = default_status;
        });

        var page_active = new Cancellable();
        web.load_changed.connect((load_evt) => {
            page_active.cancel();
            Persist.on_browse();
            if (load_evt != WebKit.LoadEvent.COMMITTED) return;

            indicators.clear();
            populate_indicators(indicators, web);
            indicators_loaded(indicators);
        });
        // This handler uses `hxwls` to scan a page for links.
        //      This is used to discover webfeeds, etc and to approximate
        //      personalized suggestions.
        web.load_changed.connect((load_evt) => {
            if (load_evt != WebKit.LoadEvent.FINISHED) return;
            page_active.reset();
            parse_links.begin(page_active, null);
        });
    }

    private async void parse_links(Cancellable? cancellable = null) {
        try {
            var source = yield web.get_main_resource().get_data(cancellable);
            var links = yield Model.parse_links(source, url);

            links_parsed(links, indicators);
            indicators_loaded(indicators);
        } catch (Error err) {
            warning("Failed to get source for link extraction: %s", err.message);
        }
    }

    private static Sqlite.Statement? Qinsert_new;
    public WebTab.with_new_entry(Granite.Widgets.DynamicNotebook parent,
                  string uri_ = "odysseus:home", bool load_immediate = true) {
        // Allocate a historical_id for odysseus:history
        var stmt = Database.parse("""SELECT historical_id FROM tab ORDER BY historical_id;""");
        int h_id = 0;
        for (; stmt.step() == Sqlite.ROW; h_id++)
            if (stmt.column_int(0) != h_id) break;

        var uri = uri_ == "" ? "about:blank" : uri_;
        var history_json = @"{\"current\": \"$(uri.escape())\"}";
        if (Qinsert_new == null)
            Qinsert_new = Database.parse("""INSERT
                    INTO tab(window_id, order_, pinned, history, historical_id)
                    VALUES (?, -1, 0, ?, ?);""");
        Qinsert_new.reset();
        var window = parent.get_toplevel() as BrowserWindow;
        Qinsert_new.bind_int64(1, window.window_id);
        Qinsert_new.bind_text(2, history_json);
        Qinsert_new.bind_int(3, h_id);

        var resp = Qinsert_new.step();
        assert(resp == Sqlite.ROW || resp == Sqlite.DONE);
        this(parent, Database.get_database().last_insert_rowid(),
                load_immediate ? uri : null);
    }

    public WebTab.rebuild_existing(Granite.Widgets.DynamicNotebook parent,
                    string title, Icon? icon, string history_json) {
        if (Qinsert_new == null)
            Qinsert_new = Database.parse("""INSERT
                    INTO tab(window_id, order_, pinned, history)
                    VALUES (?, -1, 0, ?);""");
        Qinsert_new.reset();
        var window = parent.get_toplevel() as BrowserWindow;
        Qinsert_new.bind_int64(1, window.window_id);
        Qinsert_new.bind_text(2, history_json);

        var resp = Qinsert_new.step();
        assert(resp == Sqlite.ROW || resp == Sqlite.DONE);
        this(parent, Database.get_database().last_insert_rowid());

        this.label = title;
        if (icon != null) this.icon = icon;
    }

    public Icon coloured_icon {get; set; default = new ThemedIcon("text-x-generic-symbolic");}

    public void restore_favicon() {
        if (web.get_favicon() != null) {
            var fav = ImageUtil.surface_to_pixbuf(web.get_favicon());
            coloured_icon = fav.scale_simple(16, 16, Gdk.InterpType.BILINEAR);
            // Has to be recoloured first, or we'll loose important details.
            // This colour was chosen to a) be amongst the elementary colour pallette
            //      & b) blend in with text (#333) despite heavier digital ink usage
            icon = ImageUtil.recolour(fav, "#666").scale_simple(16, 16, Gdk.InterpType.BILINEAR);
        } else icon = coloured_icon = new ThemedIcon("text-x-generic-symbolic");
    }

    public void find_in_page() {
        find.reveal_child = true;
        find.get_child().grab_focus();
    }

    public void report_fullscreen() {
        window_state_event.connect((evt) => {
            if (Gdk.WindowState.FULLSCREEN in evt.new_window_state)
                status = _("Press [esc] to leave fullscreen"); // TODO make this more dominant.
            return false;
        });
    }

    public void close_find() {
        find.reveal_child = false;
        default_status = status = "";
    }
}
