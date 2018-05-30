/**
* This file is part of Odysseus Web Browser (Copyright Adrian Cochrane 2018).
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
/** Odysseus follows elementary's principal of "build small apps that work
        together", but that can often lead to a usability hurdle for adoption
        of technologies the user doesn't have apps for. This is a concern
        expressed by: https://blogg.forteller.net/2013/first-steps/ .

Unfortunately I have to duplicate some AppCenter UI due to the way the AppStream
        standards are designed, but that'll give Odysseus a chance to explain
        why it's bringing up this UI.

And given I can link to app descriptions where they can be installed via simple
        URLs, it looks quite trivial to write that UI in Prosody. The
        challenging bit is getting at the data, which is what's done here. */
namespace Odysseus.Templating.xAppStram {
    using AppStream;

    public class AppStreamBuilder : TagBuilder, Object {
        private weak AppStream.Pool pool;
        public Template? build(Parser parser, WordIter args) throws SyntaxError {
            var variables = new Gee.ArrayList<Variable>();
            foreach (var arg in args) variables.add(new Variable(arg));

            // Ideally this would be called rarely if ever,
            // leading to setup and teardown happening each time.
            // But this parsing infrastracture helps us take advantage
            // of the off-chance where this can be better optimized than that.
            var appstream = pool;
            if (appstream == null) {
                appstream = new AppStream.Pool();
                this.pool = appstream;
                try {
                    appstream.load();
                } catch (Error err) {
                    // The system might not support AppStream so disable those features.
                    warning(err.message);
                    return null;
                }
            }
            try {
                return new AppStreamTag(variables.to_array(), appstream);
            } catch (SyntaxError err) {
                throw err;
            } catch (Error err) {
                var msg = new Slice.s(@"<p style='color: red;'>$(err.message)</p>");
                return new Echo(msg);
            }
        }
    }
    private class AppStreamTag : Template {
        private AppStream.Pool pool;
        private Variable[] vars;

        private Template renderer;
        public AppStreamTag(Variable[] vars, AppStream.Pool appstream) throws Error {
            this.vars = vars; this.pool = appstream;

            var path = "/io/github/alcinnz/Odysseus/odysseus:/special/applist.html";
            ErrorData? error_data = null; // ignored
            this.renderer = get_for_resource(path, ref error_data);
        }
        public override async void exec(Data.Data ctx, Writer output) {
            // 1. Assemble the MIMEtype query
            var mime = new StringBuilder();
            foreach (var variable in vars) mime.append(variable.eval(ctx).to_string());

            // 2. Query AppStream
            var apps = pool.get_components_by_provided_item(ProvidedKind.MIMETYPE, mime.str);

            // 3. Construct a datamodel for rendering
            var app_list = new Data.Data[apps.length];
            for (var i = 0; i < apps.length; i++) {
                var app_data = app_list[i] = new Data.Mapping(null, apps[i].id);
                app_data["icon"] = new Data.Literal(apps[i].icons.data.get_url());
                app_data["name"] = new Data.Literal(apps[i].name);
            }

            // 4. What was the package manager again?
            var pacman = AppInfo.get_default_for_uri_scheme("appstream").get_display_name();

            // 5. Render via a common template
            var data = Data.Let.builds("pacman", new Data.Literal(pacman),
                    Data.Let.builds("apps", new Data.List.from_array(app_list)));
            yield renderer.exec(data, output);
        }
    }
}
