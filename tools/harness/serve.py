#!/usr/bin/env python3
"""Serves tools/harness/fixtures over loopback on an OS-chosen free port.

The harness used to pick port 8765, which Windows refused to bind with
PermissionError [WinError 10013] (excluded port range), so the pages silently
never loaded and every browser scenario failed for the wrong reason. Binding
port 0 and printing the assigned port removes that whole class of failure.

The port is the first line of stdout; everything else goes to stderr. The
harness reads the first line, then wires `adb reverse` to it.
"""

import http.server
import os
import socketserver
import sys


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    """Logs one line per request to stderr; no default noisy timestamp format."""

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.path, fmt % args))
        sys.stderr.flush()


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)) + os.sep + "fixtures")
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", 0), QuietHandler) as httpd:
        print(httpd.server_address[1], flush=True)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
