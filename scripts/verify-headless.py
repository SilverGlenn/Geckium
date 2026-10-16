#!/usr/bin/env python3
"""Dependency-free Marionette regression test; never uses the real user profile."""
import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time


class Marionette:
    def __init__(self, port):
        self.sock = socket.create_connection(('127.0.0.1', port), timeout=3)
        self.sock.settimeout(60)
        self.seq = 0
        self.receive()  # server greeting

    def receive(self):
        size = b''
        while (c := self.sock.recv(1)) != b':':
            if not c:
                raise EOFError('Marionette disconnected')
            size += c
        data = b''
        while len(data) < int(size):
            data += self.sock.recv(int(size) - len(data))
        return json.loads(data)

    def call(self, name, args=None):
        self.seq += 1
        data = json.dumps([0, self.seq, name, args or {}]).encode()
        self.sock.sendall(str(len(data)).encode() + b':' + data)
        _, _, error, result = self.receive()
        if error:
            raise RuntimeError(error)
        return result

    def js(self, script):
        return self.call('WebDriver:ExecuteScript', {
            'script': script, 'args': [], 'newSandbox': False,
            'sandbox': 'system', 'line': 1, 'filename': 'geckium-regression',
        })['value']


def wait(fn, timeout=45):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        result = fn()
        if result:
            return result
        time.sleep(.2)
    raise TimeoutError('Timed out waiting for browser state')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--firefox', type=Path, default=Path.home()/'.local/opt/firefox-geckium/firefox')
    parser.add_argument('--payload', type=Path, required=True, help='Extracted compiled release root')
    parser.add_argument('--output', type=Path, default=Path('verification-result.json'))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='geckium-test-') as tmp:
        profile = Path(tmp)/'profile'
        shutil.copytree(args.payload/'Profile Folder', profile)
        # Skip only the setup UI/migration restart, not any user scripts.
        prefs = {
            'marionette.port': 0, 'browser.shell.checkDefaultBrowser': False,
            'browser.startup.homepage': 'about:blank', 'browser.startup.page': 0,
            'browser.aboutwelcome.enabled': False, 'browser.tabs.warnOnClose': False,
            'Geckium.firstRun.complete': True, 'Geckium.version.current': 'b0.20.21.2',
            'Geckium.version.iteration': 8, 'userChromeJS.firstRunShown': True,
            'toolkit.legacyUserProfileCustomizations.stylesheets': True,
            'userChromeJS.persistent_domcontent_callback': True,
            'browser.newtab.preload': False, 'Geckium.newTabHome.appsList': '[]',
            'userChromeJS.updates.update-check.enabled': False,
        }
        # Reserve an ephemeral port, then hand it to Marionette.
        with socket.socket() as s:
            s.bind(('127.0.0.1', 0))
            port = s.getsockname()[1]
        prefs['marionette.port'] = port
        (profile/'user.js').write_text(''.join(f'user_pref({json.dumps(k)}, {json.dumps(v)});\n' for k, v in prefs.items()))
        log_path = args.output.with_suffix('.log')
        with log_path.open('w') as log:
            proc = subprocess.Popen([str(args.firefox), '--headless', '--no-remote',
                                     '--remote-allow-system-access', '--marionette',
                                     '--profile', str(profile), 'about:blank'],
                                    stdout=log, stderr=subprocess.STDOUT,
                                    env={**os.environ, 'MOZ_CRASHREPORTER_DISABLE': '1'})
            try:
                def connect():
                    if proc.poll() is not None:
                        raise RuntimeError(f'Firefox exited: {proc.returncode}; see {log_path}')
                    try:
                        return Marionette(port)
                    except OSError:
                        return None
                client = wait(connect)
                session = client.call('WebDriver:NewSession', {'capabilities': {'alwaysMatch': {}}})
                client.call('Marionette:SetContext', {'value': 'chrome'})
                wait(lambda: client.js('return !!window.gBrowser && document.documentElement.hasAttribute("geckium-one");'))
                snapshot = '''
                    const { Scripts } = ChromeUtils.importESModule("chrome://userchromejs/content/uc_api.sys.mjs");
                    return Scripts.getScriptData().map(s => ({filename:s.filename, failed:s.injectionFailed, running:s.isRunning, enabled:s.isEnabled}));
                '''
                before = client.js(snapshot)
                client.js('''
                    window.__gkTabs = ["about:addons", "about:preferences", "about:newtab"].map(url =>
                        gBrowser.addTab(url, {triggeringPrincipal: Services.scriptSecurityManager.getSystemPrincipal()}));
                    return true;
                ''')
                wait(lambda: client.js('''return window.__gkTabs.every(t => {
                    const d = t.linkedBrowser.contentDocument;
                    return d && d.readyState === "complete" && d.location.href !== "about:blank";
                });'''))
                # Allow deferred handlers and new-tab scripts to finish too.
                time.sleep(2)
                pages = client.js('''return window.__gkTabs.map(t => {
                    const w = t.linkedBrowser.contentWindow;
                    return {url: w.location.href, geckiumOne:w.document.documentElement.hasAttribute("geckium-one"),
                            appConstants: typeof w.AppConstants !== "undefined"};
                });''')
                after_pages = client.js(snapshot)
                client.js('window.__gkSecond = window.OpenBrowserWindow(); return true;')
                wait(lambda: client.js('return window.__gkSecond && window.__gkSecond.document.readyState === "complete";'))
                time.sleep(2)
                second = client.js('return window.__gkSecond.document.documentElement.hasAttribute("geckium-one");')
                final = client.js(snapshot)
                failures = [s['filename'] for s in final if s['failed']]
                report = {'firefox': session, 'pages': pages, 'initialScripts': before,
                          'afterPagesScripts': after_pages, 'finalScripts': final,
                          'injectionFailures': failures, 'secondWindowGeckiumOne': second}
                args.output.write_text(json.dumps(report, indent=2) + '\n')
                assert final and all(s['running'] for s in final if s['enabled']), 'Enabled scripts not running'
                assert not failures, f'Injection failures: {failures}'
                assert all(p['appConstants'] and p['geckiumOne'] for p in pages), pages
                assert second, 'Second window is missing geckium-one'
                print(f'PASS: {len(final)} scripts, zero injection failures; second window geckium-one=true')
                print(f'Report: {args.output}; browser log: {log_path}')
                client.call('Marionette:Quit', {'flags': ['eForceQuit']})
            finally:
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.terminate()
                    proc.wait(timeout=10)


if __name__ == '__main__':
    main()
