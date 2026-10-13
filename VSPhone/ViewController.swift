import UIKit
import WebKit

// MARK: - Config
private enum Config {
    // URL chính — turbolite mod server
    static let targetURL = URL(string: "https://cloud.turbolite.xyz/vsphone/")!

    // Key lấy từ UserDefaults (người dùng nhập 1 lần, lưu mãi)
    // Nếu muốn hardcode: đổi thành static let storedKey = "KEY_CỦA_BẠN"
    static var storedKey: String {
        get { UserDefaults.standard.string(forKey: "tl_key") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "tl_key") }
    }

    // JavaScript inject vào trang trước khi DOM load
    static func buildInjectionScript(key: String) -> String {
        let escaped = key
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return """
        (function() {
            try {
                if (window.__TL_IOS_INJECTED) return;
                window.__TL_IOS_INJECTED = true;

                // Inject key và các metadata mà APK Android inject
                localStorage.setItem('tl_key', '\(escaped)');
                localStorage.setItem('tl_android', 'false');
                localStorage.setItem('tl_ios', 'true');
                localStorage.setItem('tl_region', 'vn');
                localStorage.setItem('tl_theme', 'dark');

                // Override z-index như APK làm — đảm bảo vsphone-ui luôn nổi trên cùng
                var style = document.createElement('style');
                style.id = 'tl-ios-inject';
                style.textContent = [
                    '#vsphone-ui, #aliyunCaptcha-window-popup,',
                    '.phone-container, .phone-wrapper, .custom-phone-ui {',
                    '  z-index: 2147483647 !important;',
                    '}'
                ].join(' ');
                (document.head || document.documentElement).appendChild(style);

                console.log('[TL-iOS] Injected key:', '\(escaped)'.substring(0, 4) + '...');
            } catch(e) {
                console.error('[TL-iOS] Injection error:', e);
            }
        })();
        """
    }
}

// MARK: - ViewController
class ViewController: UIViewController {

    private var webView: WKWebView!
    private var progressBar: UIProgressView!
    private var progressObserver: NSKeyValueObservation?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Lần đầu chưa có key -> hỏi người dùng
        if Config.storedKey.isEmpty {
            promptForKey()
        } else {
            setupWebView(key: Config.storedKey)
        }
    }

    // MARK: - Key prompt (lần đầu)
    private func promptForKey() {
        let alert = UIAlertController(
            title: "VSPhone",
            message: "Nhập Turbolite Key của bạn.\nLấy key miễn phí tại: turbolite.xyz/getkey",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Turbolite Key..."
            tf.autocorrectionType = .no
            tf.autocapitalizationType = .none
            tf.clearButtonMode = .whileEditing
        }
        let confirmAction = UIAlertAction(title: "Xác nhận", style: .default) { [weak self] _ in
            let key = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
            if key.isEmpty {
                self?.promptForKey()
            } else {
                Config.storedKey = key
                self?.setupWebView(key: key)
            }
        }
        alert.addAction(confirmAction)
        alert.preferredAction = confirmAction
        present(alert, animated: true)
    }

    // MARK: - WebView setup
    private func setupWebView(key: String) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Inject key TRƯỚC khi document load (at_document_start)
        let userScript = WKUserScript(
            source: Config.buildInjectionScript(key: key),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(userScript)

        // Preferences
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black

        // Custom User-Agent — giả vờ là app iOS native
        webView.customUserAgent = "VSPhone/4.0 (iPhone; iOS 17.0; Scale/3.00)"

        view.addSubview(webView)

        // Progress bar
        progressBar = UIProgressView(progressViewStyle: .default)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.tintColor = UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0)
        progressBar.trackTintColor = .clear
        view.addSubview(progressBar)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            progressBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 2)
        ])

        progressObserver = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
            guard let self = self else { return }
            let progress = Float(change.newValue ?? 0)
            DispatchQueue.main.async {
                self.progressBar.setProgress(progress, animated: true)
                self.progressBar.isHidden = progress >= 1.0
            }
        }

        // Load
        var request = URLRequest(url: Config.targetURL)
        request.setValue("https://cloud.turbolite.xyz", forHTTPHeaderField: "Origin")
        webView.load(request)
    }

    // MARK: - Settings menu (đổi key)
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            let alert = UIAlertController(
                title: "Đổi Key",
                message: "Nhập Turbolite Key mới",
                preferredStyle: .alert
            )
            alert.addTextField { tf in
                tf.text = Config.storedKey
                tf.placeholder = "Turbolite Key..."
                tf.autocorrectionType = .no
            }
            alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
            alert.addAction(UIAlertAction(title: "Lưu & Reload", style: .default) { [weak self] _ in
                let key = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
                if !key.isEmpty {
                    Config.storedKey = key
                    self?.webView?.reload()
                }
            })
            present(alert, animated: true)
        }
    }
}

// MARK: - WKNavigationDelegate
extension ViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Re-inject sau khi page load xong (safety net)
        let reinject = Config.buildInjectionScript(key: Config.storedKey)
        webView.evaluateJavaScript(reinject, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        // Bỏ qua lỗi cancel (người dùng navigate đi nơi khác)
        if nsError.code == NSURLErrorCancelled { return }
        showError(error)
    }

    private func showError(_ error: Error) {
        let html = """
        <!DOCTYPE html><html><head>
        <meta name='viewport' content='width=device-width,initial-scale=1'>
        <style>
          body { background:#0d1117; color:#8b949e; font-family:-apple-system; display:flex;
                 flex-direction:column; align-items:center; justify-content:center;
                 height:100vh; margin:0; padding:20px; text-align:center; }
          h2 { color:#58a6ff; margin-bottom:8px; }
          button { margin-top:24px; padding:12px 28px; background:#1f6feb;
                   color:#fff; border:none; border-radius:8px; font-size:16px; }
        </style></head><body>
        <h2>Mất kết nối</h2>
        <p>\(error.localizedDescription)</p>
        <button onclick='window.location.reload()'>Thử lại</button>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: Config.targetURL)
    }

    // Cho phép mở links trong cùng WebView (thay vì bắn ra Safari)
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url,
           url.host?.contains("turbolite") == true || url.host?.contains("vsphone") == true {
            decisionHandler(.allow)
        } else {
            decisionHandler(.allow) // cho phép tất cả, dj tự filter nếu cần
        }
    }
}

// MARK: - WKUIDelegate (popup windows, alerts)
extension ViewController: WKUIDelegate {

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // window.open() -> load trong cùng WebView
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
