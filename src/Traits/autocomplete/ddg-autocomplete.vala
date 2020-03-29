/**
* This file is part of Odysseus Web Browser (Copyright Adrian Cochrane 2017).
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
/** Loads autocompletions from DuckDuckGo. */
namespace Odysseus.Traits.Search {
    public class DDGOnlineCompletions : Tokenized.CompleterDelegate {
        private Soup.Session session = new Soup.Session();
        private Cancellable in_progress = new Cancellable();
        private DuckDuckGo output;

        construct {
            output = new DuckDuckGo();
        }

        public override void autocomplete(string query, Tokenized.Completer c) {
            // Don't want this to be a keylogger, even for DuckDuckGo.
            if (!(" " in query)) return;
            // Cancel current request if any, then reset for reuse.
            in_progress.cancel(); in_progress.reset();

            fetch_completions.begin(query, c);
        }

        private async void fetch_completions(string query, Tokenized.Completer c) {
            try {
                var uri = "https://duckduckgo.com/ac/?q=" + Soup.URI.encode(query, null);
                var request = session.request(uri);
                var response = yield request.send_async(in_progress);

                // See sample-completion.json for what is being parsed here.
                // Streams data in for subtle performance improvements.
                var jsonParser = new Json.Parser();
                jsonParser.object_member.connect((obj, member) => {
                    if (member != "phrase") return;
                    var jsonString = obj.get_string_member(member);
                    if (jsonString == null) return;

                    output.autocomplete(jsonString, c);
                });
                yield jsonParser.load_from_stream_async(response, in_progress);
            } catch (Error e) {
                // No biggy.
            }
        }
    }
}
