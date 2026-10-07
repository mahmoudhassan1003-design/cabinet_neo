// cabinet_neo/ui/html/js/bridge.js
window.CabinetNeoBridge = (() => {
  const pending = new Map();
  let   seq     = 0;

  function ready() {
    return !!(window.sketchup && typeof window.sketchup === 'object');
  }

  // Fire-and-forget Ruby call
  function call(action, ...args) {
    if (!ready() || typeof window.sketchup[action] !== 'function') {
      console.warn('[CabinetNeo] missing Ruby callback:', action);
      return false;
    }
    try {
      window.sketchup[action](...args);
      return true;
    } catch (err) {
      console.error('[CabinetNeo] bridge error on', action, err);
      return false;
    }
  }

  // Request/response wrapper (requires a matching Ruby callback that
  // eventually calls send_event with `reply_to = requestId`).
  function request(action, payload = {}, timeoutMs = 4000) {
    return new Promise((resolve, reject) => {
      if (!ready()) return reject(new Error('Ruby bridge not ready'));
      const id = `req_${++seq}`;
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`Timeout waiting for '${action}'`));
      }, timeoutMs);

      pending.set(id, { resolve, timer, action });
      call(action, JSON.stringify({ requestId: id, payload }));
    });
  }

  // Entry point invoked by Ruby via dialog.execute_script(...)
  function receive(envelope) {
    const { event, payload } = envelope || {};
    console.log('[CabinetNeo] event:', event, payload);

    // Correlated reply?
    if (payload && payload.requestId && pending.has(payload.requestId)) {
      const { resolve, timer } = pending.get(payload.requestId);
      clearTimeout(timer);
      pending.delete(payload.requestId);
      resolve(payload);
      return;
    }

    // Broadcast to app listeners
    document.dispatchEvent(new CustomEvent('cn:event', { detail: envelope }));
  }

  return { call, request, receive, ready };
})();

// Contract expected by Ruby:  window.CabinetNeo.receive({ event, payload })
window.CabinetNeo = { receive: window.CabinetNeoBridge.receive };