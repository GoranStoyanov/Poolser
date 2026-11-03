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
            <div class="brand"><strong>Poolser</strong><span>Wallet handoff</span></div>
            <span class="chip" title="\(escape(request.owner))">\(escape(shortAddress(request.owner)))</span>
          </header>
          <div class="intro"><div class="eyebrow">COLLECT FEES</div><h1>Review collection</h1><p>Check the details before confirming in your wallet.</p></div>
          <section class="card hero">
            <div class="label">Unclaimed fees</div>
            <div class="amount">\(escape(request.feesLabel))</div>
            <div class="pair">\(escape(request.pairLabel)) <span>· \(escape(request.versionLabel)) #\(escape(request.tokenId)) on \(escape(request.chainName))</span></div>
          </section>
          <h2>Transaction review</h2>
          <section class="card rows" aria-label="Transaction review">
            <div class="row"><span>Network</span><span>\(escape(request.chainName))</span></div>
            <div class="row"><span>Wallet account</span><span><code>\(escape(request.owner))</code></span></div>
            <div class="row"><span>Sent to</span><span><code>\(escape(request.to))</code></span></div>
            <div class="row"><span>Fees go to</span><span><code>\(escape(request.owner))</code></span></div>
          </section>
          <button id="go" type="button">Connect wallet and collect fees</button>
          <div id="status" role="status" aria-live="polite"></div>
          <footer>
            <p>Your wallet signs. Poolser never sees your keys.</p>
            <p>This local session expires after 15 minutes. Reopen Collect in Poolser if it stops responding.</p>
            <p>Close this tab when you are done.</p>
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
                button.textContent = 'Try again with the correct account';
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
              button.textContent = 'Transaction sent';
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
              button.textContent = 'Try collecting again';
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
        :root { color-scheme: light dark; --bg: #f5f7f3; --card: #fff; --line: #dce7e3; --hair: #e8efeb;
                --text: #153d47; --muted: #536d76; --strong: #153d47; --on-strong: #fff;
                --jade: #187c67; --blue: #3979b7; --ok: #187c67; --ok-bg: #e9f5f0;
                --bad: #a64f53; --bad-bg: #faeeee; --focus: #3979b7;
                --wave-start: #278d78; --wave-middle: #42b69c; --wave-end: #3979b7; }
        @media (prefers-color-scheme: dark) {
          :root { --bg: #10262d; --card: #18343c; --line: #35525a; --hair: #2c4850; --text: #eaf4f2;
                  --muted: #a4bec3; --strong: #eaf4f2; --on-strong: #10262d; --jade: #68d4b5;
                  --blue: #629fe0; --ok: #68d4b5; --ok-bg: #1d493f;
                  --bad: #eda6a6; --bad-bg: #3e2b2e; --focus: #629fe0;
                  --wave-start: #42b69c; --wave-middle: #68d4b5; --wave-end: #629fe0; }
        }
        * { box-sizing: border-box; }
        body { margin: 0; background: var(--bg); color: var(--text);
               font: 15px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
               -webkit-font-smoothing: antialiased; }
        main { max-width: 600px; margin: 0 auto; padding: 32px 20px 48px; }
        header { display: flex; align-items: center; gap: 12px; margin-bottom: 40px; }
        .logo { width: 40px; height: 40px; border-radius: 10px; box-shadow: 0 1px 3px rgba(0,0,0,.18); flex: none; }
        .logo-fallback { display: grid; place-items: center; background: linear-gradient(135deg, var(--wave-start), var(--wave-end)); color: #fff;
                         font-weight: 800; }
        .brand { display: flex; flex-direction: column; line-height: 1.2; }
        .brand strong { font: 700 17px/1.2 "Avenir Next", -apple-system, BlinkMacSystemFont, sans-serif; letter-spacing: -0.2px; }
        .brand span { color: var(--muted); font-size: 13px; }
        .chip { margin-left: auto; font: 600 12px ui-monospace, SFMono-Regular, Menlo, monospace; color: var(--muted);
                background: var(--card); border: 1px solid var(--line); border-radius: 999px; padding: 4px 10px; }
        .intro { margin-bottom: 20px; }
        .eyebrow { color: var(--jade); font-size: 11px; font-weight: 700; letter-spacing: .12em; }
        h1 { font: 700 28px/1.2 "Avenir Next", -apple-system, BlinkMacSystemFont, sans-serif; margin: 4px 0 6px; }
        .intro p { color: var(--muted); margin: 0; }
        h2 { font-size: 15px; line-height: 1.3; margin: 24px 0 10px; }
        .card { background: var(--card); border: 1px solid var(--line); border-radius: 18px; }
        .hero { position: relative; overflow: hidden; padding: 28px 24px 24px; }
        .hero::before { content: ""; position: absolute; inset: 0 0 auto; height: 5px;
                        background: linear-gradient(90deg, var(--wave-start), var(--wave-middle) 48%, var(--wave-end)); }
        .label { color: var(--muted); font-size: 13px; font-weight: 600; }
        .amount { font: 700 clamp(28px, 8vw, 36px)/1.2 "Avenir Next", -apple-system, BlinkMacSystemFont, sans-serif;
                  letter-spacing: -0.8px; font-variant-numeric: tabular-nums; overflow-wrap: anywhere; margin: 4px 0 8px; }
        .pair { font-weight: 600; }
        .pair span { color: var(--muted); font-weight: 400; }
        .rows { padding: 0 20px; }
        .row { display: grid; grid-template-columns: minmax(110px, 34%) minmax(0, 1fr); gap: 16px; padding: 14px 0;
               border-top: 1px solid var(--hair); }
        .row:first-child { border-top: 0; }
        .row span:first-child { color: var(--muted); }
        .row span:last-child { min-width: 0; overflow-wrap: anywhere; }
        code { font: 12.5px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; word-break: break-all; user-select: all; }
        button { margin-top: 20px; width: 100%; min-height: 48px; border: 0; border-radius: 12px;
                 background: var(--strong); color: var(--on-strong); font: inherit; font-weight: 600; cursor: pointer; }
        button:hover:not(:disabled) { opacity: .88; }
        :is(button, input, a):focus-visible { outline: 3px solid var(--focus); outline-offset: 3px; }
        button:disabled { opacity: .45; cursor: default; }
        #status { margin-top: 16px; min-height: 1.5em; }
        #status:empty { display: none; }
        #status.ok, #status.error { padding: 14px 16px; border-radius: 12px; border: 1px solid var(--line); overflow-wrap: anywhere; }
        #status.ok { color: var(--ok); background: var(--ok-bg); }
        #status.error { color: var(--bad); background: var(--bad-bg); }
        a { color: inherit; font-weight: 600; text-underline-offset: 3px; }
        footer { margin-top: 28px; color: var(--muted); font-size: 13px; text-align: center; }
        footer p { margin: 4px 0; }
        @media (max-width: 420px) {
          main { padding: 20px 16px 40px; }
          header { margin-bottom: 28px; }
          .chip { max-width: 115px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
          .hero { padding: 26px 18px 20px; }
          .rows { padding: 0 18px; }
          .row { grid-template-columns: 1fr; gap: 4px; }
        }
        @media (prefers-reduced-motion: no-preference) {
          button { transition: opacity .15s ease; }
        }
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
