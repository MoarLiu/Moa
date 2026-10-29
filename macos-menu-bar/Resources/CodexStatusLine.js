(function (config) {
  "use strict";
  globalThis.__moaCodexStatusLine?.dispose();
  let disposed = false, leasedAt = Date.now(), subscription = 0;
  let thread = "", node = null, host = null, blockedCard = null, lastStatus = "", snapshot = null, scheduled = false;
  const id = "moa-codex-statusline";
  const chinese = (document.documentElement.lang || navigator.language || "").toLowerCase().startsWith("zh");
  const text = chinese ? {
    tip: "估算输出吞吐；包含调用间等待和工具时间，用量写入后更新。",
    context: "已用", cache: "缓存", finished: "本轮最近估算", sample: "采样中", updated: "更新于"
  } : {
    tip: "Estimated output throughput including waits and tool time; updates when usage is recorded.",
    context: "used", cache: "cache", finished: "Last estimate this turn", sample: "Sampling", updated: "Updated"
  };
  const style = document.createElement("style");
  style.id = id + "-style";
  style.textContent = `#${id}{display:inline-flex;align-items:center;gap:6px;min-width:0;flex-shrink:1;white-space:nowrap;font:inherit;font-size:12px;line-height:20px;font-variant-numeric:tabular-nums;color:var(--color-token-text-secondary,inherit);user-select:none;max-width:100%;overflow:hidden;text-overflow:ellipsis}#${id}[data-below=true]{display:flex;justify-content:center;margin-top:5px;width:100%}#${id}[data-stale=true]{opacity:.55}#${id} .moa-extra{display:none}@container composer-footer (min-width:520px){#${id} .moa-extra{display:inline}}#${id}[data-below=true] .moa-extra{display:inline}`;
  document.head.append(style);

  function visible(element) {
    return element && !element.closest("[data-moa-statusline]") && element.getClientRects().length > 0 && getComputedStyle(element).visibility !== "hidden";
  }
  function locate() {
    const cards = [...document.querySelectorAll("[data-composer-surface-variant]")];
    const active = cards.filter(c => visible(c) && c.querySelector('.ProseMirror[contenteditable="true"],textarea:not(:disabled),[role="textbox"][contenteditable="true"]'));
    const card = active.length === 1 ? active[0] : null;
    const root = card?.closest("[data-codex-composer-root]");
    // Some client layouts put placement on the form inside an unlabelled root.
    const placement = card?.closest("[data-composer-placement]")?.getAttribute("data-composer-placement");
    if (!root || placement !== "thread") return {card:null, thread:""};
    let next = root.querySelector("[data-above-composer-conversation-id]")?.getAttribute("data-above-composer-conversation-id") || "";
    // Never guess from the sidebar: a side chat can leave its parent selected there.
    next = next.replace(/^local:/, "");
    if (!/^[A-Za-z0-9][A-Za-z0-9_.-]{7,127}$/.test(next) || ["__proto__","prototype","constructor"].includes(next)) next = "";
    return {card, thread:next};
  }
  function send(status) {
    if (status === lastStatus) return;
    lastStatus = status;
    globalThis.__moaStatusLineRequest(JSON.stringify({version:1, epoch:config.epoch, threadID:thread, subscription, status}));
  }
  function unmount() { node?.remove(); node = null; host = null; }
  function mount(card) {
    if (node?.isConnected && card.contains(host) && !config.belowComposer) return true;
    if (node?.isConnected && config.belowComposer && node.previousElementSibling === card) return true;
    unmount();
    if (config.belowComposer) host = card.parentElement;
    else {
      const footer = card.querySelector("[data-composer-footer-responsive]");
      const add = footer?.querySelector('[data-composer-navigation-target="add-context"]');
      // Use the full leading group: permissions may sit beside an inner add/model group.
      for (let candidate = add?.parentElement; candidate && candidate !== footer; candidate = candidate.parentElement) {
        if (["flex", "inline-flex"].includes(getComputedStyle(candidate).display)) host = candidate;
      }
    }
    if (!host) return false;
    node = document.createElement("span"); node.id = id;
    node.dataset.moaStatusline = "true"; node.dataset.below = String(config.belowComposer);
    node.setAttribute("role", "status");
    if (config.belowComposer) card.insertAdjacentElement("afterend", node);
    else host.append(node);
    return true;
  }
  function render() {
    if (!node) return;
    const stale = !snapshot?.observedAt || Date.now()/1000 - snapshot.observedAt > 120 || snapshot.state === "completed";
    const rate = snapshot?.state === "stopped" ? null : snapshot?.tokensPerSecond;
    const label = `⚡ ${Number.isFinite(rate) ? "~" + Math.max(0, Math.round(rate)) : "--"} t/s`;
    node.replaceChildren(document.createTextNode(label));
    const extras = [];
    if (config.showContext && Number.isFinite(snapshot?.requestTokens)) extras.push(Intl.NumberFormat(undefined,{notation:"compact",maximumFractionDigits:1}).format(snapshot.requestTokens));
    if (config.showContext && Number.isFinite(snapshot?.contextPercent)) extras.push(`${text.context} ${Math.round(snapshot.contextPercent)}%`);
    if (config.showCache && Number.isFinite(snapshot?.cachePercent)) extras.push(`${text.cache} ${snapshot.cachePercent.toFixed(2)}%`);
    if (extras.length) { const extra = document.createElement("span"); extra.className = "moa-extra"; extra.textContent = " · " + extras.join(" · "); node.append(extra); }
    node.dataset.stale = String(stale);
    node.title = `${text.tip}\n${snapshot?.state === "completed" ? text.finished : Number.isFinite(rate) ? "" : text.sample}${snapshot?.observedAt ? "\n" + text.updated + " " + new Date(snapshot.observedAt*1000).toLocaleTimeString() : ""}`;
    node.setAttribute("aria-label", `${label}; ${text.tip}`);
    if (!config.belowComposer) {
      const footer = node.closest("[data-composer-footer-responsive]");
      const rect = node.getBoundingClientRect();
      const overlaps = footer && [...footer.querySelectorAll('button,[role="button"]')].some(button => {
        const other = button.getBoundingClientRect();
        return rect.left < other.right - 1 && rect.right > other.left + 1 && rect.top < other.bottom - 1 && rect.bottom > other.top + 1;
      });
      if (footer && (rect.width < 40 || footer.scrollWidth > footer.clientWidth + 2 || overlaps)) {
        blockedCard = node.closest("[data-composer-surface-variant]"); unmount(); send("unsupported");
      }
    }
  }
  function sync() {
    scheduled = false;
    if (disposed) return;
    if (Date.now() - leasedAt > 30000) { dispose(); return; }
    const found = locate();
    if (found.thread !== thread) {
      thread = found.thread; subscription++; snapshot = null; lastStatus = ""; blockedCard = null; unmount();
    }
    if (!thread || !found.card) { unmount(); send("no-thread"); return; }
    if (blockedCard === found.card) { send("unsupported"); return; }
    if (!mount(found.card)) { send("unsupported"); return; }
    render();
    if (node) send("ready");
  }
  function schedule() { if (!scheduled && !disposed) { scheduled = true; queueMicrotask(sync); } }
  const observer = new MutationObserver(records => {
    if (records.some(record => !record.target.closest?.("[data-moa-statusline]"))) schedule();
  });
  observer.observe(document.documentElement, {subtree:true, childList:true, attributes:true,
    attributeFilter:["data-above-composer-conversation-id","data-composer-placement","data-app-action-sidebar-thread-selected"]});
  const timer = setInterval(sync, 5000);
  document.addEventListener("visibilitychange", schedule);
  function resize() { blockedCard = null; schedule(); }
  globalThis.addEventListener("resize", resize);
  function dispose() {
    if (disposed) return;
    disposed = true; observer.disconnect(); clearInterval(timer);
    document.removeEventListener("visibilitychange", schedule); globalThis.removeEventListener("resize", resize); unmount(); style.remove();
    delete globalThis.__moaCodexStatusLine;
  }
  globalThis.__moaCodexStatusLine = {
    update(value, expectedSubscription) {
      leasedAt = Date.now();
      if (expectedSubscription === subscription && value?.threadID === thread) { snapshot = value; render(); }
    },
    keepAlive() { leasedAt = Date.now(); }, dispose
  };
  sync();
})
