import Foundation

/// Script for the live preview. It reports the top visible source line and heading clicks to the app,
/// and scrolls to a source line when the app asks. Exports do not include it.
public enum PreviewScript {
    /// The message handler name the app registers on the web view.
    public static let handlerName = "preview"

    public static let source = """
    (function () {
      var lineOf = function (el) { return +el.getAttribute('data-line'); };
      var topOf = function (el) { return el.getBoundingClientRect().top + window.scrollY; };
      var blocks = function () { return document.querySelectorAll('[data-line]'); };

      // Maps a source line to a vertical position, interpolating between the blocks around it.
      var yForLine = function (line) {
        var nodes = blocks(), prev = null, next = null;
        for (var i = 0; i < nodes.length; i++) {
          if (lineOf(nodes[i]) <= line) { prev = nodes[i]; } else { next = nodes[i]; break; }
        }
        if (!prev) { return next ? topOf(next) : 0; }
        if (!next) { return topOf(prev); }
        var span = lineOf(next) - lineOf(prev);
        var fraction = span > 0 ? (line - lineOf(prev)) / span : 0;
        return topOf(prev) + fraction * (topOf(next) - topOf(prev));
      };

      // The inverse of yForLine: the source line at a vertical position.
      var lineForY = function (y) {
        var nodes = blocks(), prev = null, next = null;
        for (var i = 0; i < nodes.length; i++) {
          if (topOf(nodes[i]) <= y) { prev = nodes[i]; } else { next = nodes[i]; break; }
        }
        if (!prev) { return 1; }
        if (!next) { return lineOf(prev); }
        var height = topOf(next) - topOf(prev);
        var fraction = height > 0 ? (y - topOf(prev)) / height : 0;
        return Math.floor(lineOf(prev) + fraction * (lineOf(next) - lineOf(prev)));
      };

      var post = function (message) {
        var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.preview;
        if (handler) { handler.postMessage(message); }
      };

      // Only scrolls the reader starts are reported. Scrolls the app starts to follow the editor are not,
      // so the two panes cannot chase each other.
      var reading = false, idle = null, pending = false;
      var holdReading = function () { reading = true; };
      var releaseReading = function () {
        clearTimeout(idle);
        idle = setTimeout(function () { reading = false; }, 300);
      };
      document.addEventListener('wheel', function () { holdReading(); releaseReading(); }, { passive: true });
      ['mousedown', 'touchstart', 'keydown'].forEach(function (name) {
        document.addEventListener(name, holdReading, { passive: true });
      });
      ['mouseup', 'touchend', 'keyup'].forEach(function (name) {
        document.addEventListener(name, releaseReading, { passive: true });
      });

      window.addEventListener('scroll', function () {
        if (!reading || pending) { return; }
        pending = true;
        requestAnimationFrame(function () {
          pending = false;
          post({ type: 'scroll', line: lineForY(window.scrollY + 8) });
        });
      }, { passive: true });

      document.addEventListener('click', function (event) {
        var heading = event.target.closest && event.target.closest('h1, h2, h3, h4, h5, h6');
        if (heading && heading.hasAttribute('data-line')) {
          post({ type: 'heading', line: lineOf(heading) });
        }
      });

      window.notepadScrollToLine = function (line) {
        window.scrollTo(0, Math.max(0, yForLine(line) - 8));
      };
    })();
    """
}
