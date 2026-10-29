import Foundation
import PoolserKit

/// The page the browser opens to collect fees: it shows exactly what will be sent and passes it
/// to the injected wallet (EIP-1193 `window.ethereum`), after checking the account and network.
enum CollectPage {
    /// `logoPNG` is the app logo, inlined as a data URI so the page needs nothing else from
    /// the server.
    static func html(for request: CollectRequest, nonce: String, logoPNG: Data? = nil) -> String {
        let explorer = request.explorerTxPrefix ?? ""
        let (logoMark, favicon) = logo(logoPNG)
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Collect fees · Poolser</title>
        \(favicon)
        <style nonce="\(nonce)">
        \(styles)
        </style>
        </head>
        <body>
        <main>
          <header>
            \(logoMark)
            <div class="brand"><strong>Poolser</strong><span>Collect fees</span></div>
            <span class="chip">\(escape(shortAddress(request.owner)))</span>
          </header>
          <section class="card hero">
            <div class="label">Unclaimed fees</div>
            <div class="amount">\(escape(request.feesLabel))</div>
            <div class="pair">\(escape(request.pairLabel)) <span>· \(escape(request.versionLabel)) #\(escape(request.tokenId)) on \(escape(request.chainName))</span></div>
          </section>
          <section class="card rows">
            <div class="row"><span>Network</span><span>\(escape(request.chainName))</span></div>
            <div class="row"><span>Sent to</span><span><code>\(escape(request.to))</code></span></div>
            <div class="row"><span>Fees go to</span><span><code>\(escape(request.owner))</code></span></div>
          </section>
          <button id="go" type="button">Connect wallet and collect</button>
          <div id="status" role="status" aria-live="polite"></div>
          <footer>
            <p>Your wallet signs. Poolser never sees your keys.</p>
            <p>Opened by Poolser on this Mac — close this tab when you are done.</p>
          </footer>
        </main>
        <script type="application/json" id="tx">\(transactionJSON(request, explorer: explorer))</script>
        <script nonce="\(nonce)">
        (function () {
          const tx = JSON.parse(document.getElementById('tx').textContent);
          const status = document.getElementById('status');
          const button = document.getElementById('go');

          function show(text, kind) { status.className = kind || ''; status.textContent = text; }
          function report(body) {
            fetch(location.pathname + '/result', {
              method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
            }).catch(function () {});
          }

          async function collect() {
            const eth = window.ethereum;
            if (!eth) {
              show('No browser wallet found. Open this page in a browser with MetaMask, Rabby or another wallet extension.', 'error');
              return;
            }
            button.disabled = true;
            try {
              show('Connect your wallet…');
              const accounts = await eth.request({ method: 'eth_requestAccounts' });
              const account = accounts && accounts[0];
              if (!account || account.toLowerCase() !== tx.owner.toLowerCase()) {
                show('The connected account ' + (account || 'none') + ' does not own this position. Switch to ' + tx.owner + ' in your wallet and try again.', 'error');
                button.disabled = false;
                return;
              }
              const chainId = await eth.request({ method: 'eth_chainId' });
              if (parseInt(chainId, 16) !== tx.chainId) {
                show('Switch the wallet to ' + tx.chainName + '…');
                await eth.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: '0x' + tx.chainId.toString(16) }] });
              }
              show('Confirm the transaction in your wallet…');
              const hash = await eth.request({
                method: 'eth_sendTransaction',
                params: [{ from: account, to: tx.to, data: tx.data, value: '0x0' }]
              });
              show('Sent. The fees arrive once the transaction is confirmed. ', 'ok');
              if (tx.explorer && /^0x[0-9a-fA-F]{64}$/.test(hash)) {
                const link = document.createElement('a');
                link.href = tx.explorer + hash;
                link.textContent = 'View transaction';
                link.rel = 'noreferrer';
                status.appendChild(link);
              }
              report({ hash: hash });
            } catch (error) {
              const rejected = error && error.code === 4001;
              const message = rejected ? 'Cancelled in the wallet.' : 'Failed: ' + ((error && error.message) || error);
              show(message, 'error');
              button.disabled = false;
              report({ error: message });
            }
          }

          button.addEventListener('click', collect);
        })();
        </script>
        </body>
        </html>
        """
    }

    /// The page look, shared with `BatchCollectPage`.
    static let styles = """
        :root { color-scheme: light dark; --bg: #f2f2f4; --card: #fff; --line: #e6e6ea; --hair: #f0f0f2;
                --text: #111113; --muted: #62626c; --strong: #111113; --on-strong: #fff;
                --ok: #0b7a55; --ok-bg: #e8f4ef; --bad: #c2410c; --bad-bg: #fdeee6; }
        @media (prefers-color-scheme: dark) {
          :root { --bg: #0f0f11; --card: #1f1f22; --line: #2e2e33; --hair: #29292d; --text: #f4f4f5;
                  --muted: #a1a1aa; --strong: #f4f4f5; --on-strong: #111113; --ok: #4ade9a; --ok-bg: #16302a;
                  --bad: #ff9b5c; --bad-bg: #3a2417; }
        }
        * { box-sizing: border-box; }
        body { margin: 0; background: var(--bg); color: var(--text);
               font: 15px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
               -webkit-font-smoothing: antialiased; }
        main { max-width: 520px; margin: 0 auto; padding: 40px 16px 48px; }
        header { display: flex; align-items: center; gap: 12px; margin-bottom: 28px; }
        .logo { width: 40px; height: 40px; border-radius: 10px; box-shadow: 0 1px 3px rgba(0,0,0,.18); flex: none; }
        .logo-fallback { display: grid; place-items: center; background: var(--strong); color: var(--on-strong);
                         font-weight: 800; }
        .brand { display: flex; flex-direction: column; line-height: 1.2; }
        .brand strong { font-size: 17px; letter-spacing: -0.2px; }
        .brand span { color: var(--muted); font-size: 13px; }
        .chip { margin-left: auto; font: 600 12px ui-monospace, SFMono-Regular, Menlo, monospace; color: var(--muted);
                background: var(--card); border: 1px solid var(--line); border-radius: 999px; padding: 4px 10px; }
        .card { background: var(--card); border: 1px solid var(--line); border-radius: 16px; }
        .hero { padding: 20px; margin-bottom: 12px; }
        .label { color: var(--muted); font-size: 13px; font-weight: 600; }
        .amount { font-size: 36px; font-weight: 700; letter-spacing: -0.8px; font-variant-numeric: tabular-nums;
                  margin: 2px 0 6px; }
        .pair { font-weight: 600; }
        .pair span { color: var(--muted); font-weight: 400; }
        .rows { padding: 0 20px; }
        .row { display: flex; justify-content: space-between; gap: 16px; padding: 12px 0; border-top: 1px solid var(--hair); }
        .row:first-child { border-top: 0; }
        .row span:first-child { color: var(--muted); white-space: nowrap; }
        .row span:last-child { text-align: right; overflow-wrap: anywhere; }
        code { font: 12.5px ui-monospace, SFMono-Regular, Menlo, monospace; word-break: break-all; }
        button { margin-top: 20px; width: 100%; min-height: 48px; border: 0; border-radius: 12px;
                 background: var(--strong); color: var(--on-strong); font: inherit; font-weight: 600; cursor: pointer; }
        button:hover:not(:disabled) { opacity: .88; }
        button:focus-visible { outline: 3px solid var(--muted); outline-offset: 2px; }
        button:disabled { opacity: .45; cursor: default; }
        #status { margin-top: 16px; min-height: 1.5em; }
        #status:empty { display: none; }
        #status.ok, #status.error { padding: 12px 14px; border-radius: 12px; }
        #status.ok { color: var(--ok); background: var(--ok-bg); }
        #status.error { color: var(--bad); background: var(--bad-bg); }
        a { color: inherit; font-weight: 600; }
        footer { margin-top: 28px; color: var(--muted); font-size: 13px; text-align: center; }
        footer p { margin: 4px 0; }
        """

    /// The header logo and the favicon, from the app logo when there is one.
    static func logo(_ png: Data?) -> (mark: String, favicon: String) {
        let uri = png.map { "data:image/png;base64," + $0.base64EncodedString() }
        let mark = uri.map { "<img class=\"logo\" src=\"\($0)\" alt=\"\" width=\"40\" height=\"40\">" }
            ?? "<span class=\"logo logo-fallback\" aria-hidden=\"true\">P</span>"
        return (mark, uri.map { "<link rel=\"icon\" href=\"\($0)\">" } ?? "")
    }

    /// "0x8f3c…a21c".
    static func shortAddress(_ address: String) -> String {
        address.count > 12 ? "\(address.prefix(6))…\(address.suffix(4))" : address
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// JSON for a `<script type="application/json">` block, with `<`, `>` and `&` escaped so the
    /// data cannot close the block.
    static func transactionJSON(_ request: CollectRequest, explorer: String) -> String {
        scriptJSON([
            "to": request.to,
            "data": "0x" + request.data.hexString,
            "owner": request.owner,
            "chainId": request.chainId,
            "chainName": request.chainName,
            "explorer": explorer,
        ])
    }

    /// Any JSON object for a `<script type="application/json">` block, escaped the same way.
    static func scriptJSON(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json.replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
    }
}
