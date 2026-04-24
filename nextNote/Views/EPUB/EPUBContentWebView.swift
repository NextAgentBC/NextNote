import SwiftUI
import WebKit

#if os(macOS)
typealias EPUBPlatformWebView = NSViewRepresentable
#else
typealias EPUBPlatformWebView = UIViewRepresentable
#endif

// Holds a weak ref to the active WKWebView so the reader's toolbar / key
// handlers can page imperatively without waiting on a SwiftUI refresh.
final class EPUBPager: ObservableObject {
    enum Command { case pageDown, pageUp }
    weak var webView: WKWebView?

    func page(_ cmd: Command) {
        let dir = (cmd == .pageDown) ? "down" : "up"
        webView?.evaluateJavaScript("window.nnPage && window.nnPage('\(dir)');")
    }
}

// Renders one EPUB chapter (XHTML on disk) and bridges selection events +
// scroll position back to the SwiftUI parent. Also replays existing
// highlights on load.
struct EPUBContentWebView: EPUBPlatformWebView {
    let chapterURL: URL
    let readAccessRoot: URL
    let fontSize: Double
    let theme: BookTheme
    let initialScrollRatio: Double
    let pendingAnchor: String?
    let highlights: [BookHighlight]
    /// Selection reported from JS. Payload contains rangeStart/rangeEnd/text.
    var onSelectionHighlight: (HighlightPayload) -> Void
    var onScroll: (Double) -> Void
    /// Fired when user pages past the chapter's end (next) or start (prev).
    var onPageBoundary: (PageBoundary) -> Void = { _ in }
    /// Observable command channel — parent writes, view reads.
    @ObservedObject var pager: EPUBPager

    struct HighlightPayload {
        let rangeStart: Int
        let rangeEnd: Int
        let text: String
    }

    enum PageBoundary { case atStart, atEnd }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { buildWebView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        pager.webView = webView
        updateStyles(webView: webView)
        context.coordinator.reloadIfNeeded(webView: webView)
    }
    #else
    func makeUIView(context: Context) -> WKWebView { buildWebView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        pager.webView = webView
        updateStyles(webView: webView)
        context.coordinator.reloadIfNeeded(webView: webView)
    }
    #endif

    private func buildWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()

        controller.add(context.coordinator, name: "nnHighlight")
        controller.add(context.coordinator, name: "nnScroll")
        controller.add(context.coordinator, name: "nnBoundary")

        let script = WKUserScript(
            source: Coordinator.bridgeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        controller.addUserScript(script)
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        pager.webView = webView
        context.coordinator.loadChapter(webView: webView)
        return webView
    }

    private func updateStyles(webView: WKWebView) {
        let js = """
        (function(){
          var r = document.documentElement;
          if (!r) return;
          r.style.setProperty('--nn-font-size', '\(fontSize)px');
          r.setAttribute('data-nn-theme', '\(theme.rawValue)');
        })();
        """
        webView.evaluateJavaScript(js)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: EPUBContentWebView
        private var loadedChapterURL: URL?
        private var loadedHighlightHash: Int = 0
        private var lastAppliedAnchor: String?

        init(parent: EPUBContentWebView) {
            self.parent = parent
        }

        func reloadIfNeeded(webView: WKWebView) {
            if loadedChapterURL != parent.chapterURL {
                loadChapter(webView: webView)
                return
            }
            let newHash = Self.hashHighlights(parent.highlights)
            if newHash != loadedHighlightHash {
                loadedHighlightHash = newHash
                applyHighlights(webView: webView)
            }
            if lastAppliedAnchor != parent.pendingAnchor, let anchor = parent.pendingAnchor {
                lastAppliedAnchor = anchor
                scrollTo(anchor: anchor, webView: webView)
            }
        }

        private func scrollTo(anchor: String, webView: WKWebView) {
            let js = """
            (function(){
              var a = \(jsString(anchor));
              var el = document.getElementById(a) || document.querySelector('[name="' + a + '"]');
              if (el) { el.scrollIntoView({ block: 'start', behavior: 'smooth' }); }
            })();
            """
            webView.evaluateJavaScript(js)
        }

        func loadChapter(webView: WKWebView) {
            loadedChapterURL = parent.chapterURL
            loadedHighlightHash = Self.hashHighlights(parent.highlights)
            lastAppliedAnchor = parent.pendingAnchor
            webView.loadFileURL(parent.chapterURL, allowingReadAccessTo: parent.readAccessRoot)
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let js = """
            (function(){
              var r = document.documentElement;
              r.style.setProperty('--nn-font-size', '\(parent.fontSize)px');
              r.setAttribute('data-nn-theme', '\(parent.theme.rawValue)');
            })();
            """
            webView.evaluateJavaScript(js)
            applyHighlights(webView: webView)

            // Restore scroll after layout settles. Anchor wins over saved ratio.
            let ratio = parent.initialScrollRatio
            let anchor = parent.pendingAnchor ?? ""
            let restoreJS = """
            (function(){
              var anchor = \(jsString(anchor));
              if (anchor && anchor.length > 0) {
                var el = document.getElementById(anchor) || document.querySelector('[name="' + anchor + '"]');
                if (el) { el.scrollIntoView({ block: 'start' }); return; }
              }
              var h = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight);
              var vh = window.innerHeight;
              var y = Math.max(0, (h - vh) * \(ratio));
              window.scrollTo(0, y);
            })();
            """
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                webView.evaluateJavaScript(restoreJS)
            }
        }

        private func jsString(_ s: String) -> String {
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            return "'\(escaped)'"
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "nnScroll":
                if let dict = message.body as? [String: Any],
                   let r = dict["ratio"] as? Double {
                    parent.onScroll(max(0, min(1, r)))
                }
            case "nnHighlight":
                if let dict = message.body as? [String: Any],
                   let start = dict["start"] as? Int,
                   let end = dict["end"] as? Int,
                   let text = dict["text"] as? String,
                   end > start, !text.isEmpty {
                    parent.onSelectionHighlight(HighlightPayload(
                        rangeStart: start,
                        rangeEnd: end,
                        text: text
                    ))
                }
            case "nnBoundary":
                if let dict = message.body as? [String: Any],
                   let edge = dict["edge"] as? String {
                    parent.onPageBoundary(edge == "start" ? .atStart : .atEnd)
                }
            default: break
            }
        }

        // MARK: Highlights

        private func applyHighlights(webView: WKWebView) {
            let payload = parent.highlights.map {
                ["id": $0.id.uuidString,
                 "start": $0.rangeStart,
                 "end": $0.rangeEnd,
                 "color": $0.color]
            }
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8)
            else { return }
            let js = "window.nnApplyHighlights && window.nnApplyHighlights(\(json));"
            webView.evaluateJavaScript(js)
        }

        private static func hashHighlights(_ highlights: [BookHighlight]) -> Int {
            var h = Hasher()
            for hl in highlights {
                h.combine(hl.id)
                h.combine(hl.rangeStart)
                h.combine(hl.rangeEnd)
                h.combine(hl.color)
            }
            return h.finalize()
        }

        // MARK: Injected JS

        /// Selection → offsets, scroll → ratio, theme/font CSS. Offsets are
        /// into document.body's visible text (not HTML source), which is what
        /// we persist as `BookHighlight.rangeStart/rangeEnd`.
        static let bridgeScript = """
        (function(){
          const css = `
            :root { --nn-font-size: 17px; }
            html, body { font-size: var(--nn-font-size); line-height: 1.65; }
            html[data-nn-theme='light']  { background:#fdfdfd; color:#1d1d1f; }
            html[data-nn-theme='sepia']  { background:#f4ecd8; color:#3a2d1f; }
            html[data-nn-theme='dark']   { background:#16161a; color:#e6e6ea; }
            html[data-nn-theme='dark'] a { color:#7eb6ff; }
            body { margin: 0 auto; padding: 32px 48px; max-width: 720px; }
            .nn-highlight { background: rgba(255,229,100,0.55); border-radius:2px; }
            .nn-highlight[data-color='pink']  { background: rgba(255,170,200,0.55); }
            .nn-highlight[data-color='blue']  { background: rgba(150,200,255,0.55); }
            .nn-highlight[data-color='green'] { background: rgba(170,230,170,0.55); }
          `;
          const styleEl = document.createElement('style');
          styleEl.textContent = css;
          document.head && document.head.appendChild(styleEl);

          // Walk body text, record offset-to-node map.
          function buildOffsetMap() {
            const map = [];
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            let offset = 0;
            let node = walker.nextNode();
            while (node) {
              map.push({ node, start: offset, end: offset + node.nodeValue.length });
              offset += node.nodeValue.length;
              node = walker.nextNode();
            }
            return { map, length: offset };
          }

          function selectionOffsets() {
            const sel = window.getSelection();
            if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return null;
            const range = sel.getRangeAt(0);
            const { map } = buildOffsetMap();
            function offsetFor(node, localOffset) {
              // Walk nodes; if the exact node is in map, return its start + local.
              for (const entry of map) {
                if (entry.node === node) return entry.start + localOffset;
              }
              // Container isn't a text node — fall back to pre-range string length.
              const r = document.createRange();
              r.setStart(document.body, 0);
              r.setEnd(node, localOffset);
              return r.toString().length;
            }
            const start = offsetFor(range.startContainer, range.startOffset);
            const end = offsetFor(range.endContainer, range.endOffset);
            const text = sel.toString();
            return { start, end, text };
          }

          document.addEventListener('mouseup', function(){
            const off = selectionOffsets();
            if (!off || off.end <= off.start) return;
            window.webkit.messageHandlers.nnHighlight.postMessage(off);
          });

          // Click-to-page: right edge → next, left edge → prev.
          // Middle 40% reserved for link clicks / text selection.
          document.addEventListener('click', function(e){
            if (window.getSelection().toString().length > 0) return;
            if (e.target && e.target.closest && e.target.closest('a')) return;
            const x = e.clientX;
            const w = window.innerWidth;
            if (x > w * 0.7) { window.nnPage('down'); }
            else if (x < w * 0.3) { window.nnPage('up'); }
          });

          let scrollTick = null;
          window.addEventListener('scroll', function(){
            if (scrollTick) return;
            scrollTick = setTimeout(function(){
              scrollTick = null;
              const h = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight);
              const vh = window.innerHeight;
              const denom = Math.max(1, h - vh);
              const ratio = Math.max(0, Math.min(1, window.scrollY / denom));
              window.webkit.messageHandlers.nnScroll.postMessage({ ratio });
            }, 120);
          });

          window.nnPage = function(dir) {
            const h = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight);
            const vh = window.innerHeight;
            const step = Math.max(1, vh - 40);
            const denom = Math.max(1, h - vh);
            const before = window.scrollY;
            const target = dir === 'up' ? before - step : before + step;
            window.scrollTo({ top: target, behavior: 'smooth' });
            setTimeout(function(){
              const after = window.scrollY;
              if (dir === 'down' && after >= denom - 2 && before >= denom - 2) {
                window.webkit.messageHandlers.nnBoundary.postMessage({ edge: 'end' });
              } else if (dir === 'up' && after <= 2 && before <= 2) {
                window.webkit.messageHandlers.nnBoundary.postMessage({ edge: 'start' });
              }
            }, 220);
          };

          window.nnApplyHighlights = function(list) {
            // Wipe previous marks.
            document.querySelectorAll('.nn-highlight').forEach(function(el){
              const parent = el.parentNode;
              while (el.firstChild) parent.insertBefore(el.firstChild, el);
              parent.removeChild(el);
              parent.normalize();
            });
            if (!list || !list.length) return;
            const { map } = buildOffsetMap();
            list.forEach(function(hl){
              try { applyOne(map, hl); } catch(e) { /* ignore malformed */ }
            });
          };

          function applyOne(map, hl) {
            const start = hl.start, end = hl.end;
            for (const entry of map) {
              if (end <= entry.start || start >= entry.end) continue;
              const s = Math.max(start, entry.start) - entry.start;
              const e = Math.min(end, entry.end) - entry.start;
              if (e <= s) continue;
              const range = document.createRange();
              range.setStart(entry.node, s);
              range.setEnd(entry.node, e);
              const mark = document.createElement('mark');
              mark.className = 'nn-highlight';
              mark.dataset.id = hl.id;
              mark.dataset.color = hl.color || 'yellow';
              try { range.surroundContents(mark); } catch(e) { /* spans element boundary */ }
            }
          }
        })();
        """
    }
}
