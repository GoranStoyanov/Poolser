import Foundation

/// The page the browser opens to collect from several positions on one chain. It lists the
/// positions with checkboxes, asks the app to rebuild and check the transactions whenever the
/// selection changes (`POST <path>/build`), and passes them to the injected wallet: as one
/// EIP-5792 `wallet_sendCalls` batch when the wallet supports atomic batches, else one after
/// the other.
enum BatchCollectPage {
    static func html(
        for batch: CollectBatch, check: CollectBatchCheck, feeLabel: String?, nonce: String, logoPNG: Data? = nil
    ) -> String {
        let (logoMark, favicon) = CollectPage.logo(logoPNG)
        let escape = CollectPage.escape
        let rows = batch.items.map { item in
            let reason = check.failing[item.id]
            return """
            <label class="item\(reason == nil ? "" : " failing")">
              <input type="checkbox" value="\(escape(item.id))"\(reason == nil ? " checked" : " disabled")>
              <span class="what"><strong>\(escape(item.pairLabel))</strong><span>\(escape(item.versionLabel)) #\(item.tokenId)</span><span class="why">\(reason.map { escape("Would fail: \($0)") } ?? "")</span></span>
              <span class="fees">\(escape(item.feesLabel))</span>
            </label>
            """
        }.joined(separator: "\n")
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Collect fees · Poolser</title>
        \(favicon)
        <style nonce="\(nonce)">
        \(CollectPage.styles)
        .list { padding: 0 20px; margin-bottom: 12px; }
        .item { display: flex; align-items: center; gap: 12px; padding: 12px 0; border-top: 1px solid var(--hair);
                cursor: pointer; }
        .item:first-child { border-top: 0; }
        .item input { width: 18px; height: 18px; margin: 0; flex: none; accent-color: var(--strong); cursor: inherit; }
        .what { display: flex; flex-direction: column; flex: 1; min-width: 0; }
        .what span { color: var(--muted); font-size: 13px; }
        .what .why { color: var(--bad); }
        .what .why:empty { display: none; }
        .fees { font-weight: 600; font-variant-numeric: tabular-nums; white-space: nowrap; }
        .item.failing { cursor: default; }
        .item.failing strong, .item.failing .fees { opacity: .5; }
        #to code { display: block; }
        </style>
        </head>
        <body>
        <main>
          <header>
            \(logoMark)
            <div class="brand"><strong>Poolser</strong><span>Collect fees</span></div>
            <span class="chip">\(escape(CollectPage.shortAddress(batch.owner)))</span>
          </header>
          <section class="card hero">
            <div class="label">Unclaimed fees</div>
            <div class="amount" id="total"></div>
            <div class="pair" id="summary"></div>
          </section>
          <section class="card list" id="items">
        \(rows)
          </section>
          <section class="card rows">
            <div class="row"><span>Network</span><span>\(escape(batch.chain.displayName))</span></div>
            <div class="row"><span>Network fee</span><span id="gas"></span></div>
            <div class="row"><span>Sent to</span><span id="to"></span></div>
            <div class="row"><span>Fees go to</span><span><code>\(escape(batch.owner))</code></span></div>
          </section>
          <button id="go" type="button">Connect wallet and collect</button>
          <div id="status" role="status" aria-live="polite"></div>
          <footer>
            <p>Your wallet signs. Poolser never sees your keys.</p>
            <p>Opened by Poolser on this Mac — close this tab when you are done.</p>
          </footer>
        </main>
        <script type="application/json" id="batch">\(stateJSON(batch, check: check, feeLabel: feeLabel))</script>
        <script nonce="\(nonce)">
        (function () {
          const state = JSON.parse(document.getElementById('batch').textContent);
          const chainHex = '0x' + state.chainId.toString(16);
          const status = document.getElementById('status');
          const button = document.getElementById('go');
          const boxes = Array.from(document.querySelectorAll('#items input'));
          const usd = {};
          state.items.forEach(function (item) { usd[item.id] = item.usd; });
          const money = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' });
          let plan = state.plan;
          let latest = 0, settled = 0;
          // Hashes of the plan's transactions sent so far; the selection is locked once one is.
          let sent = [];

          function show(text, kind) { status.className = kind || ''; status.textContent = text; }
          function report(body) {
            fetch(location.pathname + '/result', {
              method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
            }).catch(function () {});
          }
          function selected() {
            return boxes.filter(function (box) { return box.checked && !box.disabled; }).map(function (box) { return box.value; });
          }

          function render() {
            const ids = selected();
            let total = 0, unpriced = 0;
            ids.forEach(function (id) { if (typeof usd[id] === 'number') total += usd[id]; else unpriced++; });
            document.getElementById('total').textContent = money.format(total) + (unpriced ? ' + ' + unpriced + ' unpriced' : '');
            const usable = boxes.filter(function (box) { return !box.disabled; }).length;
            document.getElementById('summary').textContent = ids.length + ' of ' + usable + ' position' + (usable === 1 ? '' : 's') + ' on ' + state.chainName;
            const building = latest !== settled;
            const count = plan.transactions.length;
            document.getElementById('gas').textContent = building ? 'Estimating…'
              : (plan.gas ? plan.gas + (count > 1 ? ' for ' + count + ' transactions' : '') : '—');
            const to = document.getElementById('to');
            to.replaceChildren.apply(to, plan.transactions.map(function (tx) {
              const code = document.createElement('code');
              code.textContent = tx.to + ' (' + tx.version + ')';
              return code;
            }));
            if (sent.length) {
              button.textContent = 'Send the remaining transaction';
            } else {
              button.textContent = count > 1 ? 'Connect wallet and collect · ' + count + ' transactions' : 'Connect wallet and collect';
            }
            button.disabled = building || count === 0 || sent.length === count;
          }

          function markFailing(failing) {
            boxes.forEach(function (box) {
              const reason = failing[box.value];
              if (!reason) return;
              box.checked = false;
              box.disabled = true;
              box.closest('.item').classList.add('failing');
              box.closest('.item').querySelector('.why').textContent = 'Would fail: ' + reason;
            });
          }

          async function rebuild() {
            const id = ++latest;
            render();
            try {
              const response = await fetch(location.pathname + '/build', {
                method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ids: selected() })
              });
              if (!response.ok) throw new Error('HTTP ' + response.status);
              const next = await response.json();
              if (id !== latest) return;
              plan = next;
              markFailing(plan.failing || {});
              if (plan.error) show(plan.error, 'error'); else show('');
            } catch (error) {
              if (id !== latest) return;
              plan = { transactions: [], gas: null };
              show('Could not update the transaction (' + error.message + '). Is Poolser still running?', 'error');
            } finally {
              if (id === latest) { settled = id; render(); }
            }
          }

          // EIP-5792 atomic batches the wallet already supports for this account. "ready" is left
          // out: the wallet would first ask to upgrade the account.
          async function batchVersion(eth, account) {
            try {
              const capabilities = await eth.request({ method: 'wallet_getCapabilities', params: [account, [chainHex]] });
              const chain = capabilities && capabilities[chainHex];
              if (chain && chain.atomic && chain.atomic.status === 'supported') return '2.0.0';
              if (chain && chain.atomicBatch && chain.atomicBatch.supported) return '1.0';
            } catch (error) {}
            return null;
          }

          async function sendBatch(eth, account, txs, version) {
            const calls = txs.map(function (tx) { return { to: tx.to, data: tx.data, value: '0x0' }; });
            const params = version === '1.0'
              ? { version: version, chainId: chainHex, from: account, calls: calls }
              : { version: version, chainId: chainHex, from: account, atomicRequired: true, calls: calls };
            const result = await eth.request({ method: 'wallet_sendCalls', params: [params] });
            const id = typeof result === 'string' ? result : result && result.id;
            show('Sent as one batch. Waiting for the wallet to report the transaction…', 'ok');
            for (let attempt = 0; id && attempt < 30; attempt++) {
              await new Promise(function (resolve) { setTimeout(resolve, 2000); });
              let calls;
              try { calls = await eth.request({ method: 'wallet_getCallsStatus', params: [id] }); } catch (error) { break; }
              if (!calls) continue;
              if (typeof calls.status === 'number' && calls.status >= 400) {
                throw new Error('the wallet reports the batch failed (status ' + calls.status + ')');
              }
              const hashes = (calls.receipts || []).map(function (receipt) { return receipt && receipt.transactionHash; })
                .filter(function (hash) { return /^0x[0-9a-fA-F]{64}$/.test(hash || ''); });
              if (hashes.length) return hashes.filter(function (hash, i) { return hashes.indexOf(hash) === i; });
              if (calls.status === 200 || calls.status === 'CONFIRMED') break;
            }
            return [];
          }

          function finish(hashes) {
            show(hashes.length > 1 ? 'Sent. The fees arrive once the transactions are confirmed. ' : 'Sent. The fees arrive once the transaction is confirmed. ', 'ok');
            hashes.forEach(function (hash, i) {
              if (!state.explorer) return;
              const link = document.createElement('a');
              link.href = state.explorer + hash;
              link.textContent = hashes.length > 1 ? 'View transaction ' + (i + 1) : 'View transaction';
              link.rel = 'noreferrer';
              if (i > 0) status.appendChild(document.createTextNode(' · '));
              status.appendChild(link);
            });
            button.disabled = true;
            button.textContent = 'Sent';
            report({ hashes: hashes });
          }

          async function collect() {
            const eth = window.ethereum;
            if (!eth) {
              show('No browser wallet found. Open this page in a browser with MetaMask, Rabby or another wallet extension.', 'error');
              return;
            }
            const txs = plan.transactions;
            button.disabled = true;
            boxes.forEach(function (box) { box.dataset.locked = box.disabled ? '' : '1'; box.disabled = true; });
            try {
              show('Connect your wallet…');
              const accounts = await eth.request({ method: 'eth_requestAccounts' });
              const account = accounts && accounts[0];
              if (!account || account.toLowerCase() !== state.owner.toLowerCase()) {
                throw { shown: 'The connected account ' + (account || 'none') + ' does not own these positions. Switch to ' + state.owner + ' in your wallet and try again.' };
              }
              const chainId = await eth.request({ method: 'eth_chainId' });
              if (parseInt(chainId, 16) !== state.chainId) {
                show('Switch the wallet to ' + state.chainName + '…');
                await eth.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: chainHex }] });
              }
              const version = sent.length === 0 && txs.length > 1 ? await batchVersion(eth, account) : null;
              if (version) {
                show('Confirm the batch in your wallet…');
                finish(await sendBatch(eth, account, txs, version));
                return;
              }
              for (let i = sent.length; i < txs.length; i++) {
                show(txs.length > 1 ? 'Confirm transaction ' + (i + 1) + ' of ' + txs.length + ' in your wallet…' : 'Confirm the transaction in your wallet…');
                sent.push(await eth.request({
                  method: 'eth_sendTransaction',
                  params: [{ from: account, to: txs[i].to, data: txs[i].data, value: '0x0' }]
                }));
                if (i < txs.length - 1) report({ hashes: sent, pending: true });
              }
              finish(sent);
            } catch (error) {
              const rejected = error && error.code === 4001;
              let message = error && error.shown ? error.shown
                : rejected ? 'Cancelled in the wallet.' : 'Failed: ' + ((error && error.message) || error);
              if (sent.length) message = sent.length + ' of ' + txs.length + ' transactions sent. ' + message;
              if (!sent.length) boxes.forEach(function (box) { if (box.dataset.locked) box.disabled = false; });
              render();
              show(message, 'error');
              if (!(error && error.shown)) report({ error: message });
            }
          }

          boxes.forEach(function (box) { box.addEventListener('change', rebuild); });
          button.addEventListener('click', collect);
          render();
          if (plan.error) show(plan.error, 'error');
        })();
        </script>
        </body>
        </html>
        """
    }

    /// What the page script starts from: the positions, and the check of all of them.
    static func stateJSON(_ batch: CollectBatch, check: CollectBatchCheck, feeLabel: String?) -> String {
        CollectPage.scriptJSON([
            "owner": batch.owner,
            "chainId": batch.chain.chainId,
            "chainName": batch.chain.displayName,
            "explorer": CollectRequest.explorerTxPrefix(chainID: batch.chain.id) ?? "",
            "items": batch.items.map { item -> [String: Any] in
                ["id": item.id, "usd": item.feesUSD.map { $0 as Any } ?? NSNull()]
            },
            "plan": planObject(check, feeLabel: feeLabel),
        ])
    }

    /// The answer to `POST <path>/build`, and the page's starting plan.
    static func planObject(_ check: CollectBatchCheck, feeLabel: String?) -> [String: Any] {
        [
            "transactions": check.transactions.map { tx -> [String: Any] in
                ["to": tx.to, "data": "0x" + tx.data.hexString, "version": tx.versionLabel]
            },
            "gas": feeLabel.map { $0 as Any } ?? NSNull(),
            "failing": check.failing,
            "error": check.error.map { $0 as Any } ?? NSNull(),
        ]
    }

    /// The item IDs in a `POST <path>/build` body, `{"ids": [...]}`.
    static func selection(fromBuildBody body: Data) -> Set<String>? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let ids = object["ids"] as? [String], ids.count <= 200 else { return nil }
        return Set(ids)
    }
}
