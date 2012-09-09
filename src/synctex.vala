/*
 * This file is part of LaTeXila.
 *
 * Copyright © 2012 Sébastien Wilmet
 *
 * LaTeXila is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * LaTeXila is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with LaTeXila.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Sébastien Wilmet
 */

// SyncTeX: forward and backward search with evince.

using Gtk;

[DBus (name = "org.gnome.evince.Daemon")]
interface EvinceDaemon : Object
{
    // Returns the bus name owner (the evince instance).
    public abstract string find_document (string uri, bool spawn) throws IOError;
}

[DBus (name = "org.gnome.evince.Application")]
interface EvinceApplication : Object
{
    public abstract string[] get_window_list () throws IOError;
}

private struct DocPosition
{
    int32 line;
    int32 column;
}

[DBus (name = "org.gnome.evince.Window")]
interface EvinceWindow : Object
{
    public abstract void sync_view (string source_file, DocPosition source_point,
        uint32 timestamp) throws IOError;

    public signal void sync_source (string source_file, DocPosition source_point,
        uint32 timestamp);
}

public class Synctex : Object
{
    public void forward_search (Document doc)
    {
        string? pdf_uri = get_pdf_uri (doc);

        if (pdf_uri == null)
        {
            show_warning (_("The document is not saved."));
            return;
        }

        File pdf_file = File.new_for_uri (pdf_uri);
        if (! pdf_file.query_exists ())
        {
            show_warning (_("The PDF file doesn't exist."));
            return;
        }

        string synctex_uri = Utils.get_shortname (pdf_uri) + ".synctex.gz";
        File synctex_file = File.new_for_uri (synctex_uri);
        if (! synctex_file.query_exists ())
        {
            string synctex_basename = synctex_file.get_basename ();
            show_warning (_("The file \"%s\" doesn't exist.").printf (synctex_basename));
            return;
        }

        EvinceWindow? ev_window = get_evince_window (pdf_uri);
        if (ev_window == null)
        {
            show_warning (_("Can not communicate with evince."));
            return;
        }

        string tex_path = doc.location.get_path ();
        DocPosition pos = get_doc_position (doc);

        sync_view (ev_window, tex_path, pos);
    }

    private void show_warning (string message)
    {
        MainWindow main_window = Latexila.get_instance ().active_window;

        MessageDialog dialog = new MessageDialog (main_window,
            DialogFlags.DESTROY_WITH_PARENT,
            MessageType.ERROR,
            ButtonsType.OK,
            "%s", _("Impossible to do the forward search."));

        dialog.format_secondary_text ("%s", message);

        dialog.run ();
        dialog.destroy ();
    }

    private DocPosition get_doc_position (Document doc)
    {
        TextIter iter;
        TextMark insert = doc.get_insert ();
        doc.get_iter_at_mark (out iter, insert);

        DocPosition pos = DocPosition ();

        pos.line = iter.get_line () + 1;
        pos.column = iter.get_line_offset ();

        return pos;
    }

    private string? get_pdf_uri (Document doc)
    {
        File? main_file = doc.get_main_file ();

        if (main_file == null)
            return null;

        string uri = main_file.get_uri ();
        return Utils.get_shortname (uri) + ".pdf";
    }

    private EvinceWindow? get_evince_window (string pdf_uri)
    {
        EvinceDaemon daemon = null;

        try
        {
            daemon = Bus.get_proxy_sync (BusType.SESSION, "org.gnome.evince.Daemon",
                "/org/gnome/evince/Daemon");
        }
        catch (IOError e)
        {
            warning ("SyncTeX: can not connect to evince daemon: %s", e.message);
            return null;
        }

        string owner = null;

        try
        {
            owner = daemon.find_document (pdf_uri, true);
        }
        catch (IOError e)
        {
            warning ("SyncTeX: find document: %s", e.message);
            return null;
        }

        EvinceApplication app = null;

        try
        {
            app = Bus.get_proxy_sync (BusType.SESSION, owner, "/org/gnome/evince/Evince");
        }
        catch (IOError e)
        {
            warning ("SyncTeX: can not connect to evince application: %s", e.message);
            return null;
        }

        string[] window_list = {};

        try
        {
            window_list = app.get_window_list ();
        }
        catch (IOError e)
        {
            warning ("SyncTeX: can not get window list: %s", e.message);
            return null;
        }

        if (window_list.length == 0)
        {
            warning ("SyncTeX: the window list is empty.");
            return null;
        }

        // There is normally only one window.
        string window_path = window_list[0];
        EvinceWindow window = null;

        try
        {
            window = Bus.get_proxy_sync (BusType.SESSION, owner, window_path);
        }
        catch (IOError e)
        {
            warning ("SyncTeX: can not connect to evince window: %s", e.message);
            return null;
        }

        return window;
    }

    private void sync_view (EvinceWindow window, string tex_path, DocPosition pos)
    {
        try
        {
            window.sync_view (tex_path, pos, Gdk.CURRENT_TIME);
        }
        catch (IOError e)
        {
            warning ("SyncTeX: can not sync view: %s", e.message);
        }
    }
}
