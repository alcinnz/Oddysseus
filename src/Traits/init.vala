/**
* This file is part of Odysseus Web Browser (Copyright Adrian Cochrane 2017-2020).
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

namespace Odysseus.Traits {
    public void setup_context(WebKit.WebContext ctx) {
        var sec = ctx.get_security_manager();

        // NOTE: In early versions I misspelled Odysseus's name,
        //      hence in case I still have bad links pointing to it,
        //      support the misspelled name in internal URIs. 
        ctx.register_uri_scheme("oddysseus", Services.handle_odysseus_uri);
        ctx.register_uri_scheme("odysseus", Services.handle_odysseus_uri);
        // Explicitly do not enable CORs, as the information here is quite sensitive. 
        sec.register_uri_scheme_as_secure("oddysseus"); // so resources load in error pages on an HTTPS connection
        sec.register_uri_scheme_as_no_access("oddysseus"); // Forces us to not rely on the Internet
        sec.register_uri_scheme_as_secure("odysseus");
        sec.register_uri_scheme_as_no_access("odysseus");

        ctx.register_uri_scheme("source", handle_source_uri);
        ctx.register_uri_scheme("icon", Services.handle_sysicon_uri);
        sec.register_uri_scheme_as_secure("icon");
        ctx.register_uri_scheme("odysseusproxy", handle_odysseusproxy_uri);
        sec.register_uri_scheme_as_secure("odysseusproxy");

        configure_context(ctx);
        DownloadSet.setup_ctx(ctx);
    }

    public void setup_webview(WebTab tab) {
        setup_other_mimetypes(tab); // Absolute first, overrides autodownload.
        setup_autodownload(tab); // This most come first, so as to cancel errors.
        setup_newtab_shortcuts(tab.web);

        setup_settings(tab.web);
        setup_report_errors(tab);
        setup_alerts(tab);
        setup_permits(tab);
        setup_persist_tab_history(tab);
        setup_internal_favicons(tab);
        setup_autoscroll(tab.web);
        fix_google_plus(tab.web);
        setup_history_tracker(tab);
        Database.setup_pseudorest(tab);
        setup_addressbar_autofocus(tab);
        tab.web.show_notification.connect(show_notification);
        setup_recommendations_harvester(tab);

        // Indicators
        tab.populate_indicators.connect(report_https);
        tab.populate_indicators.connect(report_local);
        tab.links_parsed.connect(discover_webfeeds);
        setup_youtube_feed_discovery(tab);
        detect_readability(tab);
    }

    public void setup_autosuggest() {
        var completers = get_main_completers();
        completers.register(typeof(ImplyHTTP));
        completers.register(typeof(Bookmarks));
        completers.register(typeof(HistoryAutocompleter));
        completers.register(typeof(Search.DuckDuckGo));
        completers.register(typeof(Search.DDGOnlineCompletions));
        //completers.register(typeof(RedPanda));

        DownloadSet.get_downloads().add.connect(show_download_progress_on_icon);
        DownloadSet.get_downloads().add.connect(download_window_handle_download);
    }
}
