import Foundation

/// The page the browser opens to collect fees: it shows exactly what will be sent and passes it
/// to the injected wallet (EIP-1193 `window.ethereum`), after checking the account and network.
enum CollectPage {
    static func html(for request: CollectRequest, nonce: String) -> String {
        let explorer = request.explorerTxPrefix ?? ""
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Collect fees · Poolser</title>
        <style nonce="\(nonce)">
        :root { color-scheme: light dark; --bg: #fafafa; --card: #fff; --line: #e6e6ea; --text: #111113;
                --muted: #62626c; --strong: #111113; --on-strong: #fff; --ok: #0b7a55; --bad: #c2410c; }
        @media (prefers-color-scheme: dark) {
          :root { --bg: #161618; --card: #1f1f22; --line: #2e2e33; --text: #f4f4f5; --muted: #a1a1aa;
                  --strong: #f4f4f5; --on-strong: #111113; --ok: #4ade9a; --bad: #ff9b5c; }
        }
        body { margin: 0; background: var(--bg); color: var(--text);
               font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
        main { max-width: 520px; margin: 48px auto; padding: 0 16px; }
        h1 { font-size: 24px; margin: 0 0 4px; }
        p.lead { color: var(--muted); margin: 0 0 20px; }
        .card { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 4px 16px; }
        .row { display: flex; justify-content: space-between; gap: 16px; padding: 10px 0; border-top: 1px solid var(--line); }
        .row:first-child { border-top: 0; }
        .row span:first-child { color: var(--muted); }
        .row span:last-child { text-align: right; overflow-wrap: anywhere; }
        code { font: 13px ui-monospace, SFMono-Regular, Menlo, monospace; }
        button { margin-top: 20px; width: 100%; min-height: 44px; border: 0; border-radius: 10px;
                 background: var(--strong); color: var(--on-strong); font: inherit; font-weight: 600; cursor: pointer; }
        button:disabled { opacity: .5; cursor: default; }
        #status { margin-top: 16px; min-height: 1.5em; }
        #status.ok { color: var(--ok); }
        #status.error { color: var(--bad); }
        a { color: inherit; }
        footer { margin-top: 24px; color: var(--muted); font-size: 13px; }
        </style>
        </head>
        <body>
        <main>
          <h1>Collect fees</h1>
          <p class="lead">Your wallet will ask you to confirm. Poolser never sees your keys.</p>
          <div class="card">
            <div class="row"><span>Position</span><span>\(escape(request.pairLabel)) · \(escape(request.versionLabel)) #\(escape(request.tokenId))</span></div>
            <div class="row"><span>Unclaimed fees</span><span>\(escape(request.feesLabel))</span></div>
            <div class="row"><span>Network</span><span>\(escape(request.chainName))</span></div>
            <div class="row"><span>Sent to</span><span><code>\(escape(request.to))</code></span></div>
            <div class="row"><span>Fees go to</span><span><code>\(escape(request.owner))</code></span></div>
          </div>
          <button id="go" type="button">Connect wallet and collect</button>
          <div id="status" role="status" aria-live="polite"></div>
          <footer>Opened by Poolser from this Mac. You can close this tab when you are done.</footer>
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
        let object: [String: Any] = [
            "to": request.to,
            "data": "0x" + request.data.hexString,
            "owner": request.owner,
            "chainId": request.chainId,
            "chainName": request.chainName,
            "explorer": explorer,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json.replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
    }
}
